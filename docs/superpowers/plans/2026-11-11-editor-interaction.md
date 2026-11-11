# Editor Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `docs/superpowers/specs/2026-11-11-editor-interaction-design.md` (Revision 4, approved by the user and by two reviewers): nearest-first picking, selection with handles, wall point insertion, body edit rings, a context menu with a compact property panel, a colour strip, and thumbnails in My levels.

**Architecture:** `LevelDoc` stays the document model: geometry picking, edit operations and undo. It gains edit sessions (one snapshot per edit, cancellable) and wall point insertion. `LevelEditor` owns selection, handles, the device-aware picker, gestures, the menu and the panel. `MyLevelsScreen` reuses `Thumbnail.of_sketch(LevelFormat.sketch(data))`. No new autoload, no tool framework, no format change.

**Tech stack:** Godot 4.7.2, GDScript with warnings as errors (declare types; no inferred `Variant`), the existing headless test runner.

**Spec:** the design file above is authoritative for every behaviour, value and rule. This plan names files, interfaces, order and checks; it does not restate the spec. When the plan and the spec disagree, the spec wins; report the conflict.

## Global constraints

- Worktree: `/Users/andre/git/.zero-gx_worktrees/feat/editor-interaction`, branch `feat/editor-interaction`. Never edit the primary checkout or `.worktrees/play`.
- Tests: `tests/run.sh` (all), or `TEST_FILTER=<file or file::test> tests/run.sh`. Exit 0 with no script errors is the gate. Existing warning noise (ObjectDB leaks at exit, Camera2D interpolation) is not a failure.
- Tests are behavioural: they assert what a player sees or what the level data becomes, through routed `InputEvent`s where input matters (mouse events carry `device = 0`, touch events are `InputEventScreenTouch/Drag`), at a camera zoom other than 1. No tests of source text, wiring or mock echoes.
- Existing tests that pin replaced behaviour (`test_wall_points_win_near_misses`, the sheet tests, `test_opening_an_old_out_of_range_star_brings_it_in_range`, `test_right_drag_pans` if it changes) are rewritten to the new rule, not kept.
- Clean cutover: remove replaced code (`LevelDoc.begin_move`, `_open_sheet`, `_choice`, `_slider`, `_kind_option`, `_ask_reclose` as an Overlay) in the slice that replaces it; no shims.
- `project.godot` may be rewritten by Godot on import or export (the `GodotPlayGameServices` autoload path becomes a `uid://`). Restore it with `git restore project.godot` before committing unless a task changes it on purpose.
- Commits go through the repository hook, which regenerates `graphify-out/graph.json`; run with `PATH=/tmp/zero-gx-graphify/bin:$PATH GRAPHIFY_NO_AUTO_REFRESH=1`.

## Shared interfaces

`scripts/level_doc.gd`:

```gdscript
const HIT_SLOP := 40.0        # viewport units, touch (unchanged value)
const HIT_SLOP_MOUSE := 14.0  # viewport units, mouse

## Geometry pick in four groups (spec "Picking"): points, bodies, wall segments (closing edge
## included), goal. First group with a candidate in reach wins; nearest inside a group; ties keep
## list order. `slop` is world px (the editor divides viewport units by the zoom).
func hit(at: Vector2, slop := HIT_SLOP) -> Dictionary

## Edit sessions: the first change after begin_edit() records one snapshot; later changes in the
## same edit write in place. end_edit() closes it. cancel_edit() restores the data from before the
## edit and drops its snapshot, leaving no history entry. Outside a session every change records
## its own snapshot, as today.
func begin_edit() -> void
func end_edit() -> void
func cancel_edit() -> void
func editing() -> bool

## Inserts a point after point `after` of wall `wall` (spec "Walls"). Returns the new point's ref,
## or {} when `at` equals an adjacent point, in which case nothing is recorded.
func insert_wall_point(wall: int, after: int, at: Vector2) -> Dictionary
```

Every mutating `LevelDoc` method records through one private `_record()` that respects the session. `begin_move()` is removed; callers use `begin_edit()` / `end_edit()`.

`scenes/editor.gd` (internal to the editor, named so slices agree):

```gdscript
var selection: Dictionary = {}   # the selected ref, or {}
func select(ref: Dictionary) -> void        # closes menu/panel and ends their session first
func pick(screen: Vector2, mouse: bool) -> Dictionary  # handles of the selection + LevelDoc.hit, nearest in group 1
```

Selection handles are plain dictionaries `{"type": "handle", "role": "point"|"insert"|"radius"|"reach", ...}` drawn by the editor and never stored in the level.

## Tasks

### Task 1: Picking, selection, edit sessions and gestures (spec slice 1)

**Files:** `scripts/level_doc.gd`, `scenes/editor.gd`, `tests/test_level_doc.gd`, `tests/test_editor.gd`.

- [ ] Write failing tests first, then implement:
  - `LevelDoc.hit`: two points closer than the slop pick the nearer; point within slop inside the goal ring wins; a segment crossing the goal ring wins near it; empty ring picks the goal; a segment through a planet picks the planet; the closing edge of a closed wall is picked. Replace `test_wall_points_win_near_misses`.
  - Edit sessions: two `set_property` calls inside one edit undo in one step; `cancel_edit` restores data and leaves `can_undo()` as before.
  - Editor, routed events at zoom 0.5: a mouse press 20 viewport units from a point does not pick it, a touch press does; Select-tool tap selects and opens no sheet; dragging the middle of a long wall or a body's edge moves it without a jump; Delete/Backspace delete the selection; Esc ends a wall, then clears the selection; Enter ends a wall; with a text field focused Delete and Ctrl+Z do not change the level; mouse left-hold past `LONG_PRESS` opens nothing; long-press (touch) still opens the existing sheet; a second finger during a move or a placing press cancels it with no history entry; Wall-tool press + second finger + first finger up adds no point; selection clears after undo and tool switch.
- [ ] `LevelDoc`: groups, closing edge, `HIT_SLOP_MOUSE`, sessions, `_record()`; remove `begin_move`.
- [ ] Editor: device-aware `pick`, `selection`, hover outline (mouse), selection outline per spec "Visual treatment", press offset for whole-thing moves, `DRAG_START` before any move, Gesture ownership rules, Keyboard table (menu/panel rows apply from Task 4), Android Back order, Select-tool hints for mouse and touch. The sheet stays reachable by long-press until Task 4; its sliders write through one edit session.
- [ ] Run `TEST_FILTER=test_level_doc tests/run.sh`, `TEST_FILTER=test_editor tests/run.sh`, then `tests/run.sh`. Commit: `feat(editor): nearest-first picking, selection and edit sessions`.

### Task 2: Wall handles and point insertion (spec slice 2)

**Files:** `scripts/level_doc.gd`, `scenes/editor.gd`, both test files.

- [ ] Failing tests: `insert_wall_point` on open walls (append), closed walls (after the last point), duplicate insertion records nothing, undo restores; "+" press inserts the exact rounded midpoint and selects it; "+" drag inserts and moves a snapped point in one undo step; double-click on a segment (mouse, Select tool) inserts at the snapped pointer; a selected point shows its wall's handles and Delete removes only the point; all four removal paths (Delete, Backspace, Erase tool, and later Remove point) ask Keep closed / Open here on a closed four-point wall; Erase on a segment removes the wall without asking; a "+" handle loses to a closer foreign point; second finger during a "+" drag leaves no point and no history.
- [ ] Implement handles, insertion, the shared removal rule (still asked with the existing Overlay until Task 4 turns it into a menu), wall-selected hint.
- [ ] Run the two filtered suites, then `tests/run.sh`. Commit: `feat(editor): wall point handles and insertion`.

### Task 3: Body edit rings (spec slice 3)

**Files:** `scenes/editor.gd`, `tests/test_editor.gd`.

- [ ] Failing tests: Radius knob drag keeps `LevelFormat.total_pull`, does not jump on press or first move, clamps to `KIND_LIMITS`; Reach knob likewise; radius equal to reach, reach 0, and a minimum planet at zoom 0.1 keep distinct Radius, Reach and centre targets, and a press on the exact centre moves the body; one undo step per knob drag; second finger cancels a knob drag.
- [ ] Implement rings, labelled knobs, leader-line hit targets strictly beyond one slop, press-offset formula, active-value label, body-selected hint.
- [ ] Run the filtered suite, then `tests/run.sh`. Commit: `feat(editor): resize bodies with radius and reach rings`.

### Task 4: Context menu and property panel (spec slice 4)

**Files:** `scenes/editor.gd`, `tests/test_editor.gd`; a small new scene script only if `editor.gd` would otherwise exceed clarity (e.g. `scenes/property_panel.gd`).

- [ ] Failing tests: right-click opens the menu with the spec's items; right-drag pans and opens nothing; long-press with Wall, Erase and placing tools opens the menu and changes nothing; goal and empty space open no menu; Colour, Kind, Destructible and deletions act at once; a numeric item opens the panel; opening and closing records nothing; one panel session is one undo step, including orbit speed and Start motion (direction kept while speed is 0; speed 0 removes velocity); selecting something else ends the session; invalid number text is not written; an old out-of-range body is not changed by opening; a press on the menu or panel does not reach the canvas; with the menu open Delete does not change the level, Esc closes it, Ctrl+Z closes then undoes; Android Back closes the panel before leaving; the reclose question is a two-item menu.
- [ ] Implement the menu (placement: mouse at pointer; touch above the finger with 24 units clearance, else beside it, clamped and scrolling; rows ≥ 48 dp) and the panel (opaque, placement and keyboard rules, phone two-line title, 48 dp controls). Convert dp once from `DisplayServer.screen_get_dpi()` and the viewport stretch. Remove `_open_sheet`, `_choice`, `_slider`, `_ask_reclose` and the sheet tests; keep `_number_box`.
- [ ] Run the filtered suite, then `tests/run.sh`. Commit: `feat(editor): context menu and in-place property panel`.

### Task 5: Colour strip and My levels thumbnails (spec slice 5)

**Files:** `scenes/editor.gd`, `scenes/my_levels_screen.gd`, `tests/test_editor.gd`, `tests/test_menu_screens.gd` (or the existing My levels test file).

- [ ] Failing tests: the strip shows for the Wall tool and for a selected wall or point; a button recolours the selected wall in one undo step; without a selection it sets the next wall's colour; Done shows only while drawing; a press on the strip does not reach the canvas; a My levels card shows a thumbnail for an imported invalid level, Play stays disabled, and all actions stay visible on a narrow window.
- [ ] Implement the strip (replaces `_kind_option` for walls; the pickup kind picker stays until the menu covers it, then keep whichever the spec requires), Wall-tool hint, the thumbnail slot with `mouse_filter = MOUSE_FILTER_IGNORE`, and wrapping actions.
- [ ] Run the filtered suites, then `tests/run.sh`. Commit: `feat(editor): colour strip and level thumbnails`.

### Task 6: Visual acceptance, review and delivery

- [ ] Render the real editor (not mock-ups) at 1600 × 900 and 1200 × 540 (phone landscape layout) for the cases in the spec's "Visual acceptance" line, using a throwaway capture script under `/var/tmp`. Send them to the visual reviewer (Sol) with the spec; fix findings.
- [ ] Export the macOS build locally and smoke-test editing an official level; export an Android debug build if an emulator or phone is available.
- [ ] Final whole-branch review; fix findings; full `tests/run.sh`.
- [ ] Push, open the PR, follow CI, merge, reinstall the Mac app from the release build.

## Execution

Subagent-driven: one implementer per task (Luna, `luna-task`; Haiku is unavailable for this organisation), tests first with a controller-observed RED, then implementation, then controller GREEN and a task review (`reviewer-gpt61sol`). The controller owns all checks, commits and pushes.
