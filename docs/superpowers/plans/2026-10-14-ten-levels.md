# Ten Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ten new teaching levels, each proven winnable by an autopilot test.

**Architecture:** Levels are `.tscn` files generated once by a throwaway script from corridor centrelines, then committed. They stay editable in Godot. Each level carries a hidden `Route` `Line2D`. `tests/test_levels.gd` flies it.

**Spec:** `docs/superpowers/specs/2026-10-14-ten-levels-design.md`

## Global Constraints

- Barrier instances keep `[editable path=...]`.
- Pickups stay at least `Pickup.RADIUS + 16` px from every barrier segment.
- Autopilot constants: `CRUISE = 450` px/s, arrive gain `1.2`/s, floor `80` px/s, waypoint reach `110` px, dead band `40` px/s, limit `4800` frames.

## Review Focus

1. **A level winnable only by the autopilot's exact timing** (for example, asteroid gaps) → the developer playtests levels 8–10 first.
2. **The menu overflowing the screen** → two-column grid, checked on the emulator.
3. **The idle check timing out** with ten levels → it runs only where asteroids and gravity bodies coexist.

---

### Task 1: Level tests for ten levels and the autopilot

- [ ] `test_levels.gd`: level list from `Progress.levels()`, `test_level_files_exist` expects `level_01`…`level_10`, the well-formed check requires a hidden `Route` and drops "has pickups", the idle check is filtered, and `test_levels_are_winnable` is added.
- [ ] Run: FAIL (five old levels, no routes).

### Task 2: Generate the ten levels

- [ ] Delete `levels/level_01..05.tscn`; generate `level_01..10.tscn` per the spec table; run tests; fix geometry until all pass, never the checks.
- [ ] Menu: two-column `GridContainer`.
- [ ] Commit `feat: ten teaching levels with autopilot-proven routes`.

### Task 3: Docs, build, release

- [ ] Update the prototype spec's "Test levels" section to point here; push `master`; check the menu and two levels on the emulator.
