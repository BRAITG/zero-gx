# Thrust Pickups, Impact Spin and Live Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add thrust-up, thrust-down and boost pickups, impact spin, a lower speed cap, and an in-game tuning panel to the Zero-GX prototype.

**Architecture:** A `Tuning` autoload holds every tunable value; the ship and gravity bodies read it live. The ship owns its effect state (`power`, effect timer, boost timer, spin). One `Pickup` scene with a `kind` applies effects on contact. A `TuningPanel` overlay edits `Tuning`.

**Tech Stack:** Godot 4.7.2, typed GDScript, Godot Physics 2D, `gl_compatibility` renderer.

**Spec:** `docs/superpowers/specs/2026-10-13-thrust-pickups-tuning-design.md`

## Global Constraints

- Godot 4.7.2 stable. No plugins, no image/audio/font assets; art is code-drawn, sound is procedural (`Sfx`).
- Typed GDScript. Tunable numbers live in `Tuning` (`DEFAULTS`, `RANGES`); fixed engineering numbers are named `const`s.
- Hard speed limit `TUNNEL_LIMIT = 1200.0` px/s for ships; asteroids keep `MAX_SPEED = 1200.0`.
- Level barrier instances keep `[editable path=...]` (export drops their `Shape` overrides otherwise).
- Test command: `tests/run.sh`; exits 0 when everything passes.

## Review Focus

1. **Pickup taken while another effect is active** → the new effect replaces the old one and its timer restarts. Pinned by `test_new_effect_replaces_old` (Task 2).
2. **Thrust down at high speed** → gradual slowdown, never a snap. Pinned by `test_overspeed_eases_down` (Task 1).
3. **Tuning values leaking between tests or levels** → the runner calls `Tuning.reset()` before each test (Task 1); level reload keeps session values on purpose.
4. **Touches on the tuning panel reaching the ship** → the panel's root `Control` uses `MOUSE_FILTER_STOP` and the tree pauses. Pinned by `test_panel_blocks_touch` (Task 5).
5. **Destroyed ship collecting a pickup or boosting** → `apply_power`/`start_boost` do nothing at 0 health. Pinned by `test_dead_ship_ignores_pickups` (Task 2).

---

### Task 1: Tuning autoload, speed cap, planet gravity multiplier

**Files:**
- Create: `scripts/tuning.gd`
- Modify: `project.godot` (autoload `Tuning="*res://scripts/tuning.gd"` before `Sfx`), `tests/run_tests.gd` (call `root.get_node("Tuning").reset()` before each test), `scenes/ship.gd`, `scenes/gravity_body.gd`
- Test: `tests/test_tuning.gd`

**Interfaces:**
- Produces: `Tuning` with vars `max_speed, thrust, turn_rate, boost_turn_rate, boost_seconds, boost_wobble, power_up, power_down, effect_seconds, planet_gravity, spin_per_speed, spin_max, spin_decay` (all `float`), `const DEFAULTS: Dictionary`, `const RANGES: Dictionary` (name → `[min, max, step]`), `func reset() -> void`, `func set_value(name: String, value: float) -> void` (sets and emits), `signal changed`. Values and ranges from the spec table.
- Ship: remove `THRUST`, `TURN_RATE`, `MAX_SPEED` consts; read `Tuning.thrust`, `Tuning.turn_rate`, cap at `Tuning.max_speed` (Task 2 multiplies by `power`). Add `const TUNNEL_LIMIT := 1200.0`, `const OVERSPEED_DECEL := 400.0`. Above the cap: `speed = maxf(cap, speed - OVERSPEED_DECEL * step)`; then `limit_length(TUNNEL_LIMIT)`.
- GravityBody: `Field.gravity = strength * (Tuning.planet_gravity if preset == Preset.PLANET else 1.0)`, updated on `Tuning.changed`.

- [ ] **Step 1: Write failing tests** in `tests/test_tuning.gd`:
  - `test_reset_restores_defaults`: set every value to its range max via `set_value`, `reset()`, check each equals `DEFAULTS[name]`.
  - `test_speed_capped_at_max_speed`: ship thrusting along +X from rest for 300 frames; `linear_velocity.length() <= Tuning.max_speed + 1`.
  - `test_overspeed_eases_down`: ship at `Vector2(1200, 0)`, no thrust; per-frame speed drop never exceeds `400/60 + 0.5`; after 120 frames speed is `800 ± 1`.
  - `test_planet_gravity_multiplier`: planet at origin, probe at 128 px; `Tuning.set_value("planet_gravity", 2.0)`; velocity after 1 frame is 2× the spec value (`400 * (64/128)^2 / 60`, ±2%). A star probe in the same test is unchanged.
- [ ] **Step 2: Run** `tests/run.sh`. Expected: the new tests FAIL (no `Tuning`).
- [ ] **Step 3: Implement** as in Interfaces. Existing tests that relied on 1200 px/s (`test_fast_hit_does_not_tunnel`) must still pass because the hard limit is unchanged and a 3000 px/s start eases down.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: all PASS.
- [ ] **Step 5: Commit** `feat: live Tuning values, 800 px/s cap with gradual slowdown, planet gravity multiplier`

### Task 2: Thrust effects, boost, HUD effect label

**Files:**
- Modify: `scenes/ship.gd`, `scenes/hud.gd`
- Test: `tests/test_effects.gd`

**Interfaces:**
- Consumes: `Tuning` (Task 1).
- Produces on `Ship`: `var power := 1.0`; `func apply_power(multiplier: float) -> void` (uses `Tuning.effect_seconds`); `func start_boost() -> void` (uses `Tuning.boost_seconds`); `func effect_text() -> String` (`""`, `"Thrust ×1.5 · 6 s"`, `"Boost"`); `var boosting: bool` (read-only use). Both effect functions do nothing when `health <= 0`, and each replaces any active effect.
- Boost: thrust force `Tuning.thrust` (power 1) regardless of `thrusting`, no fuel burn; turn cap `Tuning.boost_turn_rate` while finger down, heading held when up; wobble = `Tuning.boost_wobble * sin(...)` from a smooth noise (sum of two sines at incommensurate rates, seeded phase) added to angular velocity. Engine sound plays while boosting.
- HUD: a `Label` under the bars shows `ship.effect_text()`, hidden when empty.

- [ ] **Step 1: Write failing tests:**
  - `test_power_up_scales_thrust_and_cap`: `apply_power(Tuning.power_up)`, thrust 30 frames from rest; velocity ≈ `600*1.5*0.5` (±3%). Thrust 300 more frames; speed ≤ `800*1.5 + 1` and > 800.
  - `test_power_expires`: `Tuning.set_value("effect_seconds", 2)`, `apply_power(1.5)`; after 130 frames `power == 1.0`.
  - `test_new_effect_replaces_old`: `apply_power(1.5)`, 60 frames, `apply_power(0.6)`; `power == 0.6` and expires `effect_seconds` after the second call (check still 0.6 at +7.5 s, 1.0 at +8.1 s using `effect_seconds = 8`).
  - `test_boost_on_empty_tank`: `fuel = 0`, `start_boost()`; after 60 frames speed > 300, `fuel == 0`; after `boost_seconds` + 0.1 s `boosting == false` and speed stays constant (±1) over the next 30 frames.
  - `test_boost_turn_rate_limited`: `start_boost()`, `thrusting = true`, `aim_point` behind the ship; every frame `abs(angular_velocity) <= boost_turn_rate + boost_wobble + 0.01`.
  - `test_dead_ship_ignores_pickups`: `take_damage(100)`, `apply_power(1.5)`, `start_boost()`; `power == 1.0`, `boosting == false`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: thrust power effects and wobbling boost`

### Task 3: Impact spin

**Files:**
- Modify: `scenes/ship.gd` (`_take_impacts`, turning)
- Test: `tests/test_effects.gd`

**Interfaces:**
- Ship keeps `var _spin := 0.0` (rad/s). On a hit (normal speed change ≥ `MIN_IMPACT_SPEED`): `_spin += clampf(Tuning.spin_per_speed * tangential_speed, 0, Tuning.spin_max) * signf(wrapf(velocity.angle() - rotation, -PI, PI))`, then clamp `_spin` to `±spin_max`. Each step with finger up and no boost: `angular_velocity = _spin`; `_spin *= exp(-step / Tuning.spin_decay)`. Finger down: `_spin = 0`, steer as before.

- [ ] **Step 1: Write failing tests** (blue wall from `test_damage.gd`'s helper pattern):
  - `test_glancing_hit_spins_toward_travel`: ship heading +X, velocity `Vector2(500,0).rotated(deg_to_rad(-60))`, wall at x=300; after the hit, the heading has turned toward the outgoing velocity (angle between heading and velocity decreases by > 0.2 rad within 30 frames of the hit).
  - `test_head_on_spins_less`: head-on at 500; peak `abs(angular_velocity)` < 25% of the glancing case's peak.
  - `test_spin_decays`: after the glancing hit, `abs(angular_velocity) < 0.05` within 90 frames.
- [ ] **Step 2: Run.** Expected: FAIL. `test_coasting_holds_heading` must keep passing.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: glancing hits spin the ship`

### Task 4: Pickup scene and sound

**Files:**
- Create: `scenes/pickup.tscn`, `scenes/pickup.gd`
- Modify: `scripts/sfx.gd` (add `pickup`: two quick rising sine blips, 0.25 s)
- Test: `tests/test_pickups.gd`

**Interfaces:**
- Consumes: `Ship.apply_power`, `Ship.start_boost`, `Tuning.power_up`, `Tuning.power_down`.
- Produces: `class_name Pickup`, `enum Kind { THRUST_UP, THRUST_DOWN, BOOST }`, `@export var kind`, `const RADIUS := 28.0`. Colours: up `#5be37d`, down `#b07cff`, boost `#ff9a3c`.

- [ ] **Step 1: Write failing tests:**
  - `test_ship_collects_thrust_up`: pickup at (150,0), ship at origin moving (300,0); within 60 frames `ship.power == Tuning.power_up` and the pickup is freed.
  - `test_thrust_down_and_boost_apply`: same with `THRUST_DOWN` (`power == Tuning.power_down`) and `BOOST` (`ship.boosting`).
  - `test_asteroid_passes_through`: asteroid moving through a pickup; after 60 frames the pickup is still valid.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the scene, drawing (pulsing ring + chevron/flame) and sound.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: thrust and boost pickups`

### Task 5: Tuning panel

**Files:**
- Create: `scenes/tuning_panel.gd` (`class_name TuningPanel extends Control`, built in code like `hud.gd`)
- Modify: `scenes/hud.gd` (Tune button), `scenes/main.gd` (Tune button below the level list)
- Test: `tests/test_tuning.gd`

**Interfaces:**
- Consumes: `Tuning.RANGES`, `Tuning.set_value`, `Tuning.reset`.
- Produces: `TuningPanel.open(parent: Node) -> TuningPanel` static helper: adds the panel as a full-rect child of a new `CanvasLayer` (layer 10) under `parent`, sets `get_tree().paused = true`, `process_mode = PROCESS_MODE_ALWAYS`; Close unpauses and frees it. One `HSlider` per `RANGES` entry, label `name: value`.

- [ ] **Step 1: Write failing tests:**
  - `test_slider_sets_tuning`: open panel, set the `turn_rate` slider's `value = 3.0`; `Tuning.turn_rate == 3.0`.
  - `test_panel_blocks_touch`: level with ship, open panel, push a left-button press at screen centre via `Viewport.push_input`; `ship.thrusting == false`. Close unpauses (`get_tree().paused == false`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: in-game tuning panel`

### Task 6: Pickups in the levels

**Files:**
- Modify: `levels/level_01.tscn` … `levels/level_05.tscn`, `tests/test_levels.gd`

- [ ] **Step 1: Add the failing check** to `test_levels_are_well_formed`: every `Pickup` lies at least `Pickup.RADIUS + 16` px from every barrier segment, and every level has at least one `Pickup`.
- [ ] **Step 2: Run.** Expected: FAIL (no pickups).
- [ ] **Step 3: Place pickups** per the spec's Levels table, inside the corridors.
- [ ] **Step 4: Run.** Expected: PASS, including `test_no_default_asteroid_planet_hits`.
- [ ] **Step 5: Commit** `feat: place pickups in all five levels`

### Task 7: Docs, build, release

- [ ] **Step 1:** README tuning table: point to `scripts/tuning.gd` and the in-game panel; add `scenes/pickup.gd`. Spec `2026-10-12-zero-gx-prototype-design.md`: add the `pickup` scene row and the 800 px/s cap.
- [ ] **Step 2:** Run `tests/run.sh`. Expected: exit 0.
- [ ] **Step 3:** Commit `docs: pickups and tuning panel`, push `feat/prototype`, run the `Build` workflow with `publish=true`.
- [ ] **Step 4:** Install the published APK on the emulator; play level 1 through both thrust pickups; open the tuning panel from the HUD and change a slider. Expected: effects shown in the HUD, panel pauses the game.
