# Scoring and Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Points per level, saved bests, and levels that unlock in order.

**Architecture:** A `Progress` autoload owns the level list, the points formula, the progress file, and unlocking. `Level` reads flight time and the death cause from the ship, scores wins through `Progress`, and passes the result to the HUD. The menu and Tune panel read and drive `Progress`.

**Tech Stack:** Godot 4.7.2, typed GDScript, `ConfigFile`.

**Spec:** `docs/superpowers/specs/2026-10-14-scoring-progression-design.md`

## Global Constraints

- No new assets or plugins. Code-built UI, as in `hud.gd`.
- Points weights in `Tuning` (`points_fuel` 15, `points_hull` 3, `points_per_second` 2); `BASE_POINTS = 1000`, `MIN_POINTS = 100` are consts in `Progress`.
- Test command: `tests/run.sh`; the runner points `Progress` at `user://test_progress.cfg` and resets it before each test.

## Review Focus

1. **Winning a level loaded from code, without a file** → scores and shows points but saves nothing (`level_id` empty). Pinned by the existing flow tests passing.
2. **Corrupt or missing progress file** → no progress, no crash. Pinned by `test_corrupt_file_is_no_progress`.
3. **Lower score after a best** → best unchanged, "New best!" not shown. Pinned by `test_lower_score_keeps_best`.
4. **Unlock all, then reset** → reset clears saved bests but leaves the session switch alone. Pinned by `test_unlock_chain`.
5. **Win and loss on the same frame** → one result, which `test_finish_is_idempotent` already pins.

---

### Task 1: Progress autoload and points

**Files:** Create `scripts/progress.gd` (autoload `Progress`, registered after `Tuning`); modify `scripts/tuning.gd`, `tests/run_tests.gd`. Test: `tests/test_progress.gd`.

**Produces:** `Progress.path: String`, `Progress.unlock_all: bool`, `signal changed`, `levels() -> PackedStringArray` (sorted stems of `res://levels/*.tscn`), `points(fuel: float, hull: float, seconds: float) -> int`, `best_points(id: String) -> int` (−1 when none), `best_time(id: String) -> float`, `record_win(id: String, points: int, seconds: float) -> bool` (true when it is a new best; saves), `is_unlocked(id: String) -> bool`, `next_level(id: String) -> String` ("" if last), `load_file() -> void`, `reset() -> void` (clears and saves).

- [ ] Tests: `test_points_formula` (1780; floor 100 at 10000 s), `test_record_and_reload`, `test_lower_score_keeps_best`, `test_corrupt_file_is_no_progress`, `test_unlock_chain`. RED, implement, GREEN, commit `feat: Progress autoload with points, saved bests and unlocking`.

### Task 2: Flight time, death cause, scored finish, end panel

**Files:** Modify `scenes/ship.gd` (`flight_time`, `death_cause`), `scenes/level.gd` (`level_id`, scoring in `finish`, Next), `scenes/hud.gd` (`show_result(won, result: Dictionary)`, time label, Next button). Test: `tests/test_flow.gd`.

- Ship: `var flight_time := 0.0` counts physics steps once thrusting or boosting has happened. `var death_cause := ""`: `"Lethal surface"` on a lethal contact, `"Hull destroyed"` otherwise. Level maps `stranded` to `"Out of fuel"`.
- Level: `var level_id := ""`, defaulting to `scene_file_path.get_file().get_basename()` when empty. `finish(won)` builds `{points, breakdown, new_best, cause, has_next}` and calls `hud.show_result`.
- [ ] Tests: `test_win_saves_points` (level_id `level_01`, goal reached → `Progress.best_points("level_01") > 0`), `test_loss_saves_nothing`, `test_clock_waits_for_first_thrust` (60 idle frames → `flight_time == 0`), `test_loss_cause_shown` (stranded → HUD result text contains "Out of fuel"). RED, implement, GREEN, commit `feat: scored finish with breakdown, loss cause and flight time`.

### Task 3: Menu locks and bests, Tune debug controls

**Files:** Modify `scenes/main.gd`, `scenes/tuning_panel.gd`. Test: `tests/test_flow.gd`.

- Menu: a button per `Progress.levels()`, labelled per the spec, disabled when locked; it rebuilds on `Progress.changed`.
- Tune panel: an "Unlock all levels" CheckButton; a "Reset progress" button with a `ConfirmationDialog`.
- [ ] Tests: `test_menu_locks_levels` (fresh progress: Level 01 enabled, Level 02 disabled; after `record_win("level_01", ...)` Level 02 enabled). RED, implement, GREEN, commit `feat: level menu shows bests and locks; debug unlock and reset`.

### Task 4: Docs, build, release

- [ ] README: scoring and progress file; `scripts/progress.gd` in the tuning table. Run `tests/run.sh`, push `master`, wait for the release, and install it on the emulator: win level 1, check the panel, the best on the menu, and level 2 unlocking.
