# Scoring and Progression Design

Date: 2026-10-14
Status: Approved in conversation
Part 1 of 3 of the vertical slice (1: scoring and progression, 2: ten levels, 3: visuals and sound)

## Purpose

The prototype proved that steering through gravity wells is fun. The vertical slice tests whether the game holds up over many levels. Players need a reason to replay a level and a sense of moving forward. This part adds points per level, saved best results, and levels that unlock in order.

## Decisions

| Topic | Decision |
|---|---|
| Score | Points, favouring fuel efficiency |
| Unlocking | Finishing level N, at any score, unlocks level N+1. Level 1 is always open. |
| Storage | Godot `ConfigFile` at `user://progress.cfg` |
| Losses | Score nothing and save nothing |

## Points

```
points = max(100, round(fuel_left × points_fuel + hull_left × points_hull − seconds × points_per_second))
```

| Weight | Default | Tune range | Step |
|---|---|---|---|
| `points_fuel` | 15 | 0–30 | 1 |
| `points_hull` | 3 | 0–10 | 0.5 |
| `points_per_second` | 2 | 0–30 | 1 |

- Example: a 30 s finish with 40 fuel and 80 hull scores 600 + 240 − 60 = 780. (Until 2026-10-26 a 1000-point base was added for reaching the goal; it was dropped as a constant that said nothing, and saved bests were migrated.)
- `seconds` is flight time. It starts at the ship's first thrust or boost, not when the level loads.
- The weights live in `Tuning` with sliders. The floor (100) is a constant.

## Progress file

- Path `user://progress.cfg`. One section per level id (the level file's stem, for example `level_01`), with keys `best_points` (int) and `best_time` (float, seconds of the best-points run).
- Written immediately after each win that improves `best_points`. A lower or equal score changes nothing.
- A missing or unreadable file means no progress. It never crashes the game.
- **Reset progress** deletes all sections and saves an empty file.

## Screens

- **Level menu:**
  - Each button shows `Level 01 · 1780`, or `Level 01 · —` when the level has not been finished.
  - Locked levels show `Level 03 · locked`, are disabled, and cannot be pressed.
- **Win panel:**
  - "Course clear", the total points, and three breakdown lines: fuel +600, hull +240, time −60.
  - "New best!" when the run improved the saved best.
  - Buttons: **Next** (only when a following level exists), **Retry**, **Menu**.
- **Loss panel:**
  - "Lost", with the cause: `Hull destroyed`, `Out of fuel` or `Lethal surface`.
  - Buttons: **Retry**, **Menu**.
- **HUD:** the flight time, bottom right, for example `12.3 s`. It is always shown, not tied to the debug-overlay switch.
- **Tune panel debug section:**
  - "Unlock all levels" switch. It lasts for the session and is not saved.
  - "Reset progress" button, which asks for confirmation first.
  - The three points weights as sliders.

## Verification

### Automated

- The points formula gives 1780 for the example, and never goes below 100.
- Saving and loading round-trips best points and time. A lower score does not overwrite the best.
- A corrupt file loads as no progress.
- Unlocking: only level 1 is open at first. Winning level 1 opens level 2 but not level 3. "Unlock all" opens everything.
- A loss saves nothing; a win saves the points shown on the panel.
- Flight time does not run before the first thrust.
- The menu disables locked levels.
- Tests use a separate progress file, reset before each test.

### Manual

- The developer installs the next prerelease, finishes levels in order, and checks points, bests, unlocking and reset.

## Out of scope

- Cloud saves and multiple save slots.
- Points thresholds for unlocking.
- Leaderboards.
