# In-App Level Editor Design (sub-project 2 of community levels)

Date: 2026-10-16
Status: Approved in conversation

## Purpose

Players build levels inside the game, on the phone, and play them. Publishing them is sub-project 3 (the community server); this part produces valid level files on the device and marks which ones their author has finished.

## Decisions

| Topic | Decision |
|---|---|
| Where | Inside the game app. A desktop or web editor may come later and would share the level format. |
| Input | A tool palette and a snapping grid. One finger edits; two fingers pan and pinch-zoom. |
| Scope | Object presets that can be customized within per-kind limits, plus level settings (title, hint, fuel, hull, each of fuel and hull optionally unlimited). |
| Storage | `user://levels/<id>.json.gz` in the level format, plus `user://levels/index.cfg` holding each level's completion state. |
| Completion | A level is completed when its author finishes it in Test after the last edit. Any edit clears it. Publishing will require it. |

## Body limits

The format gains per-kind limits, enforced by `LevelFormat.validate` (and later the server). "Total pull" is the pull at 1,000 px, `strength × (radius / 1000)²`; "surface pull" is `strength`.

| Kind | Radius | Total pull | Surface pull | Reach |
|---|---|---|---|---|
| Planet | 32–240 px | up to 100 px/s² | — | up to 1,500 px |
| Star | 300–1,500 px | 150–6,000 px/s² | — | up to 6,000 px |
| Black hole | 32–96 px | — | 8,000–64,000 px/s², and above every star's surface pull in the same level | up to 1,500 px |

With these limits a planet can never be bigger than a star or out-pull it from afar, and a black hole always grabs harder up close than any star in its level. Today's presets and levels satisfy them.

## Screens

- **Menu → Create → My levels.** A list of the player's levels, each with its best points and a "completed" mark. Buttons: New, Edit, Play, Delete (asks for confirmation).
- **Editor.**
  - Top bar: Back (saves), Undo, Settings (the level settings sheet), Test.
  - Bottom palette:
    - **Wall**, with a colour toggle (blue, orange or red). Tap to add points; tap the first point to close the shape; **Done** ends the wall.
    - **Planet**, **Black hole** and **Star**: tap to place a preset.
    - **Asteroid**: tap to place, then drag outward to set its drift velocity. Dropping it on a planet's orbit ring makes it orbit that planet.
    - **Pickup**: tap to place; the tool cycles between thrust up, thrust down and boost.
    - **Start** and **Goal**: move the ship's start or the goal.
    - **Select**: tap an object to move it by dragging, and open its sheet.
    - **Erase**.
  - Grid: lines every 10 m (100 px); snapping to 10 m, or 1 m with a toggle.
  - Gestures: one finger runs the current tool; two fingers pan and pinch-zoom (zoom 0.1–1.5).
- **Object sheet**: sliders bound to the limits above (radius, surface pull, reach; destructible and health for planets; orbit speed and direction for orbiting asteroids; drift speed; pickup kind; wall colour).
- **Level settings**: title, hint, fuel and hull sliders (1–1000) each with an "unlimited" switch, and "show velocity arrow".
- **Errors**: Test and Back list `LevelFormat.validate` errors in plain text. Test is blocked while errors exist. Back saves anyway and marks the level as not completed.
- **Test**: builds the level from the current data and plays it. Back or Menu from the test returns to the editor with the same data. Finishing sets the completion mark; editing afterwards clears it.

## Code structure

- `scripts/level_doc.gd` (`class_name LevelDoc`): the edited level as format data, with operations `place(kind, at)`, `add_wall_point(at)`, `finish_wall()`, `move(ref, at)`, `erase(ref)`, `hit(at) -> ref`, `set_property(ref, key, value)`, `set_setting(key, value)`, `undo()`, `snap(at)`. Each operation is undoable and keeps the data valid in shape (but not necessarily passing validation, for example while a wall has one point).
- `scripts/my_levels.gd` (`class_name MyLevels`): list, load, save, delete, and the completion index.
- `scenes/editor.gd`: the editor screen; draws the level with the real game scenes (`LevelFormat.build`) frozen, plus the grid, wall-in-progress and selection.
- `scenes/my_levels_screen.gd`: the list screen.

## Verification

- `LevelDoc` operations, undo, snapping, and hit-testing are unit-tested.
- Body limits reject a planet larger than the smallest star, a star with less total pull than allowed, and a black hole weaker up close than a star in the same level; every shipped level still validates.
- `MyLevels` round-trips a level and its completion mark; an edit clears completion.
- The editor screen, palette, sheets and test flight are checked with renders.
