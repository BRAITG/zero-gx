# Guided Tutorials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five guided tutorial stages, a velocity vector, tutorials in progression, and level 5's planet in the corner.

**Architecture:** `Tutorial extends Level` adds awaited steps over a running level; each tutorial scene's script overrides `lesson()`. The velocity vector is drawn by the ship when its level asks for it. `Progress` lists `res://tutorials/` before `res://levels/`.

**Spec:** `docs/superpowers/specs/2026-10-16-tutorials-design.md`

## Global Constraints

- Code-built UI; buttons play the tap sound.
- Tests: `tests/run.sh`. Tours stay off in tests.

## Review Focus

1. **A touch off the ring during `touch_target`** → ignored, the ship does not thrust. Pinned by `test_touch_target_ignores_off_ring`.
2. **Dying mid-lesson** → step restarts, stage not lost. Pinned by `test_tutorial_restores_on_death`.
3. **Every tutorial completable** → `test_tutorials_complete` drives each lesson.
4. **Unlock chain across tutorials and levels** → `test_unlock_chain_spans_tutorials`.
5. **Menu fits fifteen buttons** → checked on a render.

---

### Task 1: Velocity vector
- Ship: `var show_velocity := false`; `_draw` draws the vector in world direction (counter-rotated). `velocity_arrow_length() -> float` = `minf(speed / 4, 200)`.
- Level: `@export var show_velocity := false`, copied to the ship in `_ready`. Levels 1–4 set it.
- Test `test_velocity_arrow_length`.

### Task 2: Tutorials in progression and menu
- `Progress.levels()` returns tutorial stems (`tutorial_N`) then level stems; `path_of(id)` gives the scene path. Level, menu and the Next button use `path_of`.
- Menu: label `Training N` for tutorials; three columns.
- Tests: `test_unlock_chain_spans_tutorials`; update tests that count levels.

### Task 3: Tutorial base
- `scenes/tutorial.gd` per spec: `say`, `touch_target`, `until`, `reveal_goal`, checkpoint restore.
- Tests: `test_touch_target_ignores_off_ring`, `test_tutorial_restores_on_death`.

### Task 4: T1–T5 scenes and scripts
- `tutorials/tutorial_N.tscn` + `tutorials/tutorial_N.gd` per the spec's table.
- Test `test_tutorials_complete`: a driver answers each step (presses OK, holds the ring, steers toward the goal) and checks the win.

### Task 5: Level 5 planet into the corner
- Planet to (2200, 200); retune fuel and route; the autopilot proves it.

### Task 6: Docs, build, release.
