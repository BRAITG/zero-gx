# Zero-GX Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable 2D Godot prototype of Zero-GX: a ship crosses barrier-lined courses full of gravity wells and asteroids, from A to B, within fuel and health limits.

**Architecture:** One Godot 4.7 project. Each game object is a reusable scene with a single script: ship, gravity body, asteroid, barrier, goal, level, HUD, main menu. Godot's own physics provides gravity (`Area2D` point gravity), collisions, and bounce. Our scripts add fuel, damage, orbits on rails, shattering, and level flow. Tests are plain GDScript run headless at a fixed 60 FPS.

**Tech Stack:** Godot 4.7.2 stable (Linux x86_64 binary on the server, macOS app on the MacBook), GDScript, Godot Physics 2D, `gl_compatibility` renderer.

**Spec:** `docs/superpowers/specs/2026-10-12-zero-gx-prototype-design.md`

## Global Constraints

- Godot 4.7.2 stable. No plugins or addons.
- Typed GDScript (`var x: float`, typed signatures). Tunable numbers are `const` or `@export` with the spec's starting values. No literal tuning numbers inside logic.
- Project settings: `physics/2d/default_gravity = 0`, `physics/2d/default_linear_damp = 0`, `physics/2d/default_angular_damp = 0`. Keep Godot's default `input_devices/pointing/emulate_mouse_from_touch = true`, so a phone touch arrives as a left mouse button event.
- Every physics body uses friction 0.
- Art is code-drawn only (`_draw`, `Line2D`, `Polygon2D`). No image, audio, or font assets.
- The server is a shared machine with limited disk. Install only the Godot binary there: no export templates, no Android SDK.
- Test command (all tasks): `tests/run.sh`. It exits 0 when everything passes.

## Shared interfaces

Later tasks rely on these names. Each one is defined in the task named.

| Name | Defined in | Contract |
|---|---|---|
| `Impact.LETHAL` | Task 2 `scripts/impact.gd` | `const LETHAL := INF` |
| `impact_multiplier() -> float` | Barrier (T4), GravityBody (T2), Asteroid (T5) | Damage multiplier for anything hitting this body. `Impact.LETHAL` means instant death. |
| `class_name GravityBody` | T2 | `enum Preset { PLANET, BLACK_HOLE, STAR }`; exports `preset`, `radius`, `strength`, `range`, `destructible`, `health`; `take_damage(amount: float) -> void`; `signal shattered`; `signal struck(by: Node)` |
| `class_name Ship` | T3 | `var thrusting: bool`, `var aim_point: Vector2` (world), `var fuel: float`, `var health: float`; `take_damage(amount: float) -> void`; `signal destroyed`, `signal stranded` |
| `class_name Asteroid` | T5/T6 | exports `orbit_parent: NodePath`, `orbit_radius`, `orbit_speed` (rad/s, sign = direction), `orbit_angle`; `var on_rails: bool`; `release(impulse: Vector2) -> void` |
| `class_name Barrier` | T4 | `enum Kind { BLUE, ORANGE, RED }`; export `kind`; geometry from its child `Line2D` named `Shape` |
| `class_name Goal` | T7 | `signal reached` |
| `class_name Level` | T7 | `signal finished(won: bool)` |

---

### Task 1: Toolchain, project skeleton, test runner

**Files:**
- Create: `project.godot`, `.gitignore`, `physics/frictionless.tres`, `tests/run.sh`, `tests/run_tests.gd`, `tests/test_case.gd`, `tests/test_smoke.gd`

**Interfaces:**
- Produces: `tests/test_case.gd` (base class for every test file):
  - `var world: Node2D`. The runner creates a fresh one for each test method, adds it under `root`, and frees it afterwards.
  - `func check(cond: bool, msg: String) -> void` records a failure without stopping the test.
  - `func frames(n: int) -> void` is a coroutine that awaits `n` physics frames.
  - `func spawn(path: String, pos: Vector2, props: Dictionary = {}) -> Node` instantiates the scene, sets `props` before `add_child` to `world`, sets `global_position`, and returns the node.

- [ ] **Step 1: Install Godot on the server**

```bash
mkdir -p ~/.local/opt/godot && cd ~/.local/opt/godot
curl -fLO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip -o Godot_v4.7.2-stable_linux.x86_64.zip && rm Godot_v4.7.2-stable_linux.x86_64.zip
ln -sf ~/.local/opt/godot/Godot_v4.7.2-stable_linux.x86_64 ~/.local/bin/godot
godot --version
```
Expected: `4.7.2.stable.official...`

- [ ] **Step 2: Write `project.godot` and `.gitignore`**

- `project.godot`: name `Zero-GX`, `run/main_scene="res://scenes/main.tscn"` (created in Task 7), the Global Constraints physics and input settings, a 1280×720 window with `stretch/mode="canvas_items"`, `rendering/renderer/rendering_method="gl_compatibility"`, and `display/window/handheld/orientation=4` (sensor landscape).
- `.gitignore`: `.godot/`, `/android/`, `*.apk`, `export_presets.cfg`.
- `physics/frictionless.tres`: a `PhysicsMaterial` with `friction = 0.0` and `bounce = 0.0`.

- [ ] **Step 3: Write the runner**

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1 || true
exec godot --headless --path . --fixed-fps 60 -s tests/run_tests.gd
```

`tests/run_tests.gd` extends `SceneTree`. In `_initialize()` it starts an async `_run()`. `_run()` does the following:

1. List `res://tests/test_*.gd`.
2. For each method whose name starts with `test_`, create a new instance, make a new `world` under `root`, `await` the method, then free `world`.
3. Print `PASS file::method` or `FAIL file::method: <msgs>`.
4. Finish with `quit(1 if any failed else 0)`.

A script error inside a test must also count as a failure. Check the instance's `failures` and that the method returned. If the method never finished, report it as a failure with a 600-frame timeout per test.

- [ ] **Step 4: Write a smoke test that must fail first**

`tests/test_smoke.gd`:
```gdscript
extends "res://tests/test_case.gd"
func test_runner_reports_failures() -> void:
    check(false, "deliberate")
```
Run `tests/run.sh`. Expected: `FAIL test_smoke.gd::test_runner_reports_failures: deliberate` and exit code 1.

- [ ] **Step 5: Make the smoke test real and pass**

Replace the body with: spawn a plain `RigidBody2D` (create it in code and add it to `world`), give it `linear_velocity = Vector2(60, 0)`, run `await frames(60)`, then `check(abs(body.position.x - 60.0) < 1.5, ...)`. This proves zero gravity, zero damping, and the fixed 60 FPS timing. Run `tests/run.sh`. Expected: PASS, exit 0.

- [ ] **Step 6: Commit** `chore: Godot project skeleton and headless test runner`

---

### Task 2: Gravity bodies

**Files:**
- Create: `scripts/impact.gd`, `scenes/gravity_body.tscn`, `scenes/gravity_body.gd`
- Test: `tests/test_gravity.gd`

**Interfaces:**
- Produces: `GravityBody` and `Impact.LETHAL`, as in Shared interfaces.

**Preset defaults.** `_ready()` applies these only when the instance has not overridden them; the simplest rule is to use exports defaulting to `-1` to mean "from preset".

| Preset | radius | strength (px/s² at surface) | range | lethal | destructible default | health |
|---|---|---|---|---|---|---|
| PLANET | 64 | 400 | 450 | no (multiplier 1.0) | false | 100 |
| BLACK_HOLE | 64 | 4000 | 800 | yes | never | — |
| STAR | 600 | 3000 | 3000 | yes | never | — |

**Scene.** The root `StaticBody2D` has:
- a `CollisionShape2D` circle with radius `radius`, using the `frictionless` material
- a child `Area2D` named `Field` with:
  - `gravity_space_override = SPACE_OVERRIDE_COMBINE`
  - `gravity_point = true`
  - `gravity_point_center = Vector2.ZERO`
  - `gravity_point_unit_distance = radius`
  - `gravity = strength`
  - a circle shape with radius `range`
  - `monitorable = false`

`_draw()` draws a filled circle colored by preset. Black holes get a thin bright ring.

- [ ] **Step 1: Write failing tests** in `tests/test_gravity.gd`. Probes are plain `RigidBody2D`s with a circle shape of radius 2 and mass 1, starting at rest. Measure the velocity after 1 frame.
  - `test_inverse_square`: planet at the origin, with probes at distance 128 and at distance 256 (2× radius and 4× radius). Expected velocity after 1 frame = `400 * (64/d)^2 / 60`, pointing toward the planet. Check each probe within 2%, and check that the near probe's speed is 4× the far one's (±2%).
  - `test_zero_beyond_range`: a probe at distance 500 (> 450) stays at velocity 0 after 10 frames.
  - `test_pulls_add`: two planets at x = ±200 and a probe at (0, 100). The x-velocity is about 0, and the y-velocity matches the sum of both expected pulls (±2%).
  - `test_multipliers`: a planet's `impact_multiplier()` is `1.0`, and a black hole's and a star's are `Impact.LETHAL`.
- [ ] **Step 2: Run** `tests/run.sh`. Expected: these four fail because the scene is missing.
- [ ] **Step 3: Implement** `scripts/impact.gd` (`class_name Impact`, holding only `const LETHAL := INF`) and the gravity body scene and script from the tables above. `take_damage` and shattering come in Task 5. For now, declare the signals and give `take_damage` an empty body: `pass`.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: all PASS.
- [ ] **Step 5: Commit** `feat: gravity bodies with inverse-square point gravity`

---

### Task 3: Ship core — thrust, turning, fuel, stranding, camera

**Files:**
- Create: `scenes/ship.tscn`, `scenes/ship.gd`
- Test: `tests/test_ship.gd`

**Interfaces:**
- Produces: `Ship`, as in Shared interfaces. `take_damage` reduces `health`, clamps it at 0, and emits `destroyed` the first time health reaches 0, then sets `freeze = true` and hides the ship.

**Constants:**
- `MAX_FUEL = 100.0`
- `FUEL_BURN = 10.0` (per second of thrust)
- `THRUST = 600.0` (force, mass 1, so px/s²)
- `TURN_RATE = 6.0` rad/s
- `MAX_HEALTH = 100.0`
- `STRAND_SPEED = 5.0`
- `STRAND_TIME = 2.0`
- `LOOKAHEAD = 0.3` s
- `LOOKAHEAD_MAX = 250.0` px

**Scene:**
- Root `RigidBody2D`: mass 1, `frictionless` material, `continuous_cd = CCD_MODE_CAST_SHAPE`, `contact_monitor = true`, `max_contacts_reported = 8`, `lock_rotation = false`.
- A circle collider of radius 16.
- A `Camera2D` child with `position_smoothing_enabled` and `ignore_rotation = true`.
- `_draw()` draws a triangle pointing along local +X, plus a flame while thrusting.

**Behavior in `_integrate_forces(state)`:**
1. **Turning:** set `state.angular_velocity` toward the direction of `aim_point`, capped at `TURN_RATE`. Use the same wrap-to-±π shortest-turn logic AstroCat used.
2. **Thrust:** while `thrusting and fuel > 0`, apply `Vector2.RIGHT.rotated(rotation) * THRUST` and reduce `fuel` by `FUEL_BURN * state.step`, clamped at 0.
3. **Stranding:** while `fuel == 0` and `state.linear_velocity.length() < STRAND_SPEED`, accumulate `state.step`. Once the total reaches `STRAND_TIME`, emit `stranded` once. Reset the accumulator whenever the speed is at or above `STRAND_SPEED`.
4. **Camera:** in `_process`, set the camera's `offset = (linear_velocity * LOOKAHEAD).limit_length(LOOKAHEAD_MAX)`.

**Input.** `_unhandled_input` handles only `InputEventMouseButton` (left button) and `InputEventMouseMotion`. On a phone these are the touch events Godot emulates as mouse input. GUI controls consume them first, so a tap on a HUD button never thrusts the ship. Only one finger is supported.
- `thrusting` = the left button or the finger is down.
- `aim_point` = `get_canvas_transform().affine_inverse() * event.position`.

- [ ] **Step 1: Write failing tests:**
  - `test_fuel_burns_at_rate`: ship at the origin with `thrusting = true` and `aim_point = Vector2(1000, 0)`. After `frames(60)`, check `abs(fuel - 90.0) < 0.5` and `linear_velocity.x > 0`.
  - `test_no_thrust_without_fuel`: `fuel = 0`, `thrusting = true`, ship at rest. After 30 frames, its speed is below 0.01.
  - `test_coasting_on_empty_is_not_stranded`: `fuel = 0`, `linear_velocity = Vector2(100, 0)`. After 180 frames, `stranded` has not been emitted.
  - `test_stranded_when_still_on_empty`: `fuel = 0`, ship at rest. `stranded` has not been emitted at frame 110, and has been emitted by frame 130.
  - `test_turns_toward_aim`: `aim_point = Vector2(0, 1000)`, ship at rotation 0. After 30 frames, `abs(wrapf(rotation - PI/2, -PI, PI)) < 0.05`.
  - `test_destroyed_once`: `take_damage(60)` twice gives `health == 0` and `destroyed` emitted exactly once.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the scene and script.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: ship thrust, turning, fuel, stranding, camera`

---

### Task 4: Barriers and impact damage

**Files:**
- Create: `scenes/barrier.tscn`, `scenes/barrier.gd`
- Modify: `scenes/ship.gd` (contact handling in `_integrate_forces`)
- Test: `tests/test_damage.gd`

**Interfaces:**
- Consumes: `Impact.LETHAL`, `GravityBody.impact_multiplier()`, `Ship.take_damage`.
- Produces: `Barrier` with `impact_multiplier()`. Values: BLUE `0.1`, ORANGE `1.0`, RED `Impact.LETHAL`.

**Barrier scene.**
- Root `StaticBody2D`, with a child `Line2D` named `Shape` whose points designers edit in the editor, and `@export var closed := false`.
- In `_ready()`, add one `CollisionShape2D` holding a `SegmentShape2D` per consecutive point pair. If `closed`, also add the last→first segment. Set `Shape.closed` to match.
- Color the line: BLUE `#3aa0ff`, ORANGE `#ff8a1f`, RED `#a00010`. Width: 6 for blue and orange, 9 for red.
- Physics material: friction 0, `bounce = BARRIER_BOUNCE` (`0.8`).

**Ship contact handling** (constants `DAMAGE_PER_SPEED = 0.05`, `MIN_IMPACT_SPEED = 20.0`). For each contact `i` in `state`:
1. `collider := state.get_contact_collider_object(i)`. Let `mult` be `collider.impact_multiplier()` when the collider has that method, otherwise 0.
2. If `mult == Impact.LETHAL`, call `take_damage(health)`, which destroys the ship.
3. Otherwise, compute `dv := state.get_contact_impulse(i).length() * state.inverse_mass`. If `dv >= MIN_IMPACT_SPEED`, call `take_damage(dv * DAMAGE_PER_SPEED * mult)`.

**Fallback:** if Step 2's diagnostic shows `get_contact_impulse` returning zero, compute `dv` instead from the change in the normal component of velocity between the previous step and this one: store `_prev_velocity` each step and use `state.get_contact_local_normal(i)`. Record which method was used in the commit message.

- [ ] **Step 1: Write failing tests.** Barriers in the tests are a vertical wall of `Shape` points `[(0,-500),(0,500)]` at x = 300. The ship starts at x = 0.
  - `test_head_on_orange_damage`: orange wall, ship velocity `(500, 0)`. After 90 frames, `100 - health` lies in `[35, 55]`.
  - `test_graze_hurts_less`: same speed, but the velocity is rotated so it hits the wall at 15° from the wall's surface: `Vector2(500,0).rotated(deg_to_rad(-75))`, with the ship placed so it reaches the wall. Its damage is less than 40% of the head-on damage.
  - `test_blue_is_mild`: blue wall head-on at 500. Damage is in `[3.5, 5.5]`, which is 0.1× the orange range.
  - `test_red_kills_on_touch`: red wall, ship velocity `(30, 0)`. `destroyed` is emitted.
  - `test_resting_contact_is_harmless`: blue wall plus a planet placed so it presses the ship against the wall. After 300 frames, `health == 100`.
  - `test_black_hole_kills`: ship drifting at `(50, 0)` toward a black hole. `destroyed` is emitted.
  - `test_planet_surface_damage`: ship at 500 head-on into a planet. Damage is in `[15, 55]`. The planet's bounce is 0, so the range is wider.
- [ ] **Step 2: Run.** Expected: FAIL. If `test_head_on_orange_damage` shows 0 damage once the barrier exists, apply the fallback.
- [ ] **Step 3: Implement** the barrier scene and the ship's contact handling.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: barriers and speed-scaled impact damage`

---

### Task 5: Free asteroids, planet damage, swallowing, shattering

**Files:**
- Create: `scenes/asteroid.tscn`, `scenes/asteroid.gd`
- Modify: `scenes/gravity_body.gd` (`take_damage`, shattering)
- Test: `tests/test_asteroids.gd`

**Interfaces:**
- Consumes: `GravityBody`, `Impact.LETHAL`.
- Produces:
  - `Asteroid` with `impact_multiplier() -> 1.0`.
  - `GravityBody.take_damage`: does nothing unless `destructible`. Otherwise it reduces `health`, and at or below 0 it shatters once.

**Asteroid scene.** Root `RigidBody2D`: mass 2, circle radius 20, `frictionless` material, CCD cast shape, `contact_monitor = true`, `max_contacts_reported = 4`. `_draw()` draws a gray irregular polygon of 8 points, with radii jittered ±20% by a seeded RNG from `get_instance_id()`.

**Contacts** (constant `PLANET_DAMAGE_PER_IMPULSE = 0.04`). For each contact with a `GravityBody` `g`:
1. If `g.impact_multiplier() == Impact.LETHAL`, call `queue_free()` once.
2. Otherwise, emit `g.struck.emit(self)`. If the contact impulse's length × the inverse mass is at least `MIN_IMPACT_SPEED` (20), call `g.take_damage(impulse.length() * PLANET_DAMAGE_PER_IMPULSE)`.

**Shattering** (constants `SHARDS_MIN = 12`, `SHARDS_MAX = 20`, `SHARD_SPEED_MIN = 100.0`, `SHARD_SPEED_MAX = 250.0`):
1. Spawn N asteroid instances, with `rng.randi_range(12, 20)`, as siblings of the planet. Place them evenly around angles `2π·k/N` at distance `radius + 24`, with outward velocity `rng.randf_range(100, 250)`.
2. Emit `shattered`.
3. Free the planet with `queue_free()`. Spawn the shards with `call_deferred`, because the physics callback cannot add bodies directly.

- [ ] **Step 1: Write failing tests:**
  - `test_swallowed_by_black_hole`: an asteroid at velocity `(200, 0)` heads toward a black hole 400 px away. Within 180 frames the asteroid is no longer valid (`is_instance_valid` is false).
  - `test_planet_takes_damage_from_asteroid`: destructible planet with health 100, asteroid at 400 px/s head-on. After the impact, `0 < health < 100`, and `struck` was emitted with the asteroid.
  - `test_indestructible_planet_ignores_hits`: same setup with `destructible = false`. `health == 100`, and `struck` is still emitted.
  - `test_shatter`: destructible planet with health 1, asteroid at 400 px/s. Within 60 frames, the planet is invalid, `shattered` was emitted, and the number of `Asteroid` children in `world` is between 12 and 20, plus 1 if the original asteroid is still alive.
  - `test_gravity_gone_after_shatter`: after `test_shatter`'s sequence plus 5 frames, a probe placed at distance 150 from the former center, with all shards removed first, stays at rest for 10 frames.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: asteroids damage, shatter planets, fall into black holes`

---

### Task 6: Orbits on rails

**Files:**
- Modify: `scenes/asteroid.gd`, `scenes/ship.gd` (release on contact)
- Test: `tests/test_rails.gd`

**Interfaces:**
- Consumes: `GravityBody.shattered`.
- Produces: `Asteroid.release(impulse: Vector2) -> void`. It sets `on_rails = false` and `freeze = false`, and sets `linear_velocity = tangential + impulse / mass`, where `tangential = Vector2(-sin θ, cos θ) * orbit_radius * orbit_speed`. Calling it again when the asteroid is not on rails does nothing.

**Behavior:**
1. **On ready:** if `orbit_parent` is set, `on_rails = true`, `freeze_mode = FREEZE_MODE_KINEMATIC`, `freeze = true`, and the asteroid connects to the parent's `shattered` signal, calling `release(Vector2.ZERO)`.
2. **Each physics frame while on rails:** `orbit_angle += orbit_speed * delta`, and `global_position = parent.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius`.
3. **Releasing:** the ship's and asteroids' contact loops call `release(-state.get_contact_impulse(i))` on a collider that is an `Asteroid` with `on_rails`. This is the equal-and-opposite impulse. Use the same fallback as Task 4 if impulses read zero: `-(Δv_normal * own mass)`. A rail asteroid has no contact callbacks of its own while frozen; release is always triggered by the free body.

- [ ] **Step 1: Write failing tests:**
  - `test_orbit_is_exact_under_foreign_gravity`: planet at the origin, black hole at (400, 0), and an asteroid with radius 150, `orbit_speed = 1.0`, angle 0. For 3600 frames, every 60 frames, check that the asteroid's distance from the planet is `abs(d - 150) < 1.0`.
  - `test_ship_knocks_asteroid_off_rails`: same orbit with no black hole. Ship fired at 400 px/s into the asteroid's path. Afterwards, `on_rails == false`, `freeze == false`, and within 60 more frames the distance from the planet differs from 150 by more than 5.
  - `test_released_when_parent_shatters`: destructible planet with an orbiting asteroid. Call `planet.take_damage(1e9)`. After 2 frames, the asteroid is valid, `on_rails == false`, and its speed is about `150 * 1.0` (±5%).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: asteroid orbits on rails until disturbed`

---

### Task 7: Goal, HUD, level flow, main menu

**Files:**
- Create: `scenes/goal.tscn`, `scenes/goal.gd`, `scenes/hud.tscn`, `scenes/hud.gd`, `scenes/level.gd`, `scenes/main.tscn`, `scenes/main.gd`
- Test: `tests/test_flow.gd`

**Interfaces:**
- Consumes: `Ship` signals and properties.
- Produces:
  - **`Goal`:** an `Area2D` with a circle of radius 80, drawn as a pulsing ring. It emits `reached` when a `Ship` enters.
  - **`Level`:** the root script of every level scene. In `_ready()` it finds the single `Ship` child and the single `Goal` child. It instantiates `hud.tscn`, then connects:
    - `reached` → `finish(true)`
    - `destroyed` → `finish(false)`
    - `stranded` → `finish(false)`

    `finish(won)` is idempotent. It emits `finished(won)`, freezes the ship, and tells the HUD to show "Course clear" or "Lost" with **Retry** and **Menu** buttons. Retry calls `get_tree().reload_current_scene()`, and Menu changes the scene to `res://scenes/main.tscn`.
  - **`HUD`:** a `CanvasLayer` with a fuel bar and a health bar (`ProgressBar`s, updated each frame from the ship), a **Restart** button that is always visible, and the result panel. Its buttons must not leak touches to the ship, so set `mouse_filter = STOP` on the panels.
  - **`Main`:** a `Control` with a `VBoxContainer` holding one button per entry of `ResourceLoader.list_directory("res://levels/")` that ends in `.tscn`, sorted by name, labeled with the file stem. A button press calls `change_scene_to_file`.

- [ ] **Step 1: Write failing tests.** Each builds a level in code: a `Node2D` with `level.gd`, plus a ship and a goal.
  - `test_reaching_goal_wins`: goal at (300, 0), ship at velocity (300, 0). `finished(true)` is emitted within 120 frames.
  - `test_destroyed_loses`: calling `ship.take_damage(100)` emits `finished(false)`.
  - `test_finish_is_idempotent`: destroyed and then reaching the goal emits `finished` exactly once.
  - `test_main_lists_levels`: instantiating `main.tscn` gives one button per `levels/*.tscn`. This test is written now and run after Task 8.
- [ ] **Step 2: Run.** Expected: the three flow tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: the flow tests PASS. `test_main_lists_levels` passes with 0 levels only if `levels/` exists; create an empty `levels/.gitkeep`.
- [ ] **Step 5: Commit** `feat: goal, HUD, level flow, level menu`

---

### Task 8: Five test levels and the level-design check

**Files:**
- Create: `levels/level_01.tscn` … `levels/level_05.tscn`
- Test: `tests/test_levels.gd`

**Interfaces:**
- Consumes: every scene above. Each level is a `Node2D` with `level.gd` containing exactly one `Ship` (its position is point A), one `Goal` (point B), and any number of `Barrier`, `GravityBody` and `Asteroid` instances.

**Level content** (from the spec, in world pixels; the course should take 20–60 s to fly):

| Level | Content |
|---|---|
| `level_01` Corridor | A bending course 400 px wide built from blue barrier pairs, about 4000 px long with two 90° turns. Two stretches are orange. No gravity bodies. |
| `level_02` Slingshot | One planet, `strength` 600, sitting in the bend of an L-shaped course, so a direct thrust route costs more than 100 fuel while a swing around the planet saves it. Blue walls. |
| `level_03` Asteroid field | One indestructible planet with 4 rail asteroids at two radii. A second, destructible planet (`health 100`) blocks a short gap, with the long route around it lined with orange. Plus 3 drifting asteroids moving parallel to the course, away from both planets. |
| `level_04` Black hole | A black hole beside a 300 px gap between orange walls. The route must pass within 350 px of it. |
| `level_05` Gauntlet | A star outside the right-hand wall pulls the whole middle section sideways. The middle walls are red, and the course turns 180° (a U-turn) after that section. |

- [ ] **Step 1: Write the failing check** in `tests/test_levels.gd`:
  - `test_level_files_exist`: all 5 paths load as `PackedScene`.
  - `test_levels_are_well_formed`: each level has exactly one `Ship` and one `Goal`, its root has `level.gd`, and every `Asteroid.orbit_parent` resolves to a `GravityBody`.
  - `test_no_default_asteroid_planet_hits`: for each level, instantiate it into `world`, set `ship.freeze = true` so the ship plays no part, connect every `GravityBody.struck` signal, and run 3600 frames. Any `struck` from a planet fails with `level_NN: <asteroid name> hit <planet name> at t=<s>`.
- [ ] **Step 2: Run.** Expected: FAIL (no levels).
- [ ] **Step 3: Build the five levels** as `.tscn` text files, using the editor-editable `Line2D` `Shape` points for barriers.
- [ ] **Step 4: Run.** Expected: all PASS, including `test_main_lists_levels`, which now shows 5 buttons. If the no-hit check fails, adjust asteroid orbits or drift paths. Never adjust the check.
- [ ] **Step 5: Commit** `feat: five prototype levels and level-design check`

---

### Task 9: README and push

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`** with:
  - one paragraph on what the prototype is
  - how to run the tests (`tests/run.sh`, which needs `godot` on `PATH`)
  - MacBook steps:
    1. Install Godot 4.7.2.
    2. Open `project.godot`.
    3. Press F5 to play.
  - Android export:
    1. Install Android Studio for the SDK, plus JDK 17.
    2. In the editor, set Editor Settings → Export → Android SDK path and Java SDK path.
    3. Add an Android export preset with package `com.braitg.zerogx` and arm64-v8a. The standard export works; the Android build template isn't needed.
    4. Run Export Project → `zero-gx.apk` and `adb install zero-gx.apk`.
  - where the tuning constants live: `scenes/ship.gd`, `barrier.gd`, `asteroid.gd`, `gravity_body.gd`.
- [ ] **Step 2: Run** `tests/run.sh` once more. Expected: exit 0.
- [ ] **Step 3: Commit and push** with `git add README.md && git commit -m "docs: README with Mac and Android steps" && git push`.

## Review Focus

1. **Tunneling at high speed through thin segment barriers** → the ship must still bounce or die, not pass through. Task 4 sets CCD. Add `test_fast_hit_does_not_tunnel` to Task 4: a ship at 3000 px/s into a blue wall ends on the near side.
2. **Resting or sliding contact accumulating damage** → no damage over time. This is pinned by Task 4's `test_resting_contact_is_harmless`.
3. **A shard spawning inside a barrier or another body** after shattering → shards are placed at `radius + 24`. Levels must keep 60 px clear around destructible planets. Add to Task 8's `test_levels_are_well_formed`: no barrier segment lies within `radius + 60` of a destructible planet.
4. **A touch on HUD buttons also thrusting the ship** → the ship reads only emulated mouse events in `_unhandled_input`, and HUD controls consume those first. Add `test_hud_touch_not_thrust` to Task 7: push an `InputEventMouseButton` (left, pressed) at the Restart button's center through `Viewport.push_input`, and the ship's `thrusting` stays false.
5. **Ship destroyed and goal reached on the same frame** → only one result is shown. This is pinned by Task 7's `test_finish_is_idempotent`.
