# Thrust Pickups, Impact Spin and Live Tuning Design

Date: 2026-10-13
Status: Approved in conversation; the developer pre-approved the written spec and plan until the next playtest

## Purpose

Playtesting `prototype-r5` showed three things:

1. Bounces now feel right, but the speed cap (1200 px/s) makes it too easy to bounce everywhere.
2. The star's pull is obvious; the planet's pull goes unnoticed.
3. The game needs pickups that change how the ship handles. Each pickup can help or hurt depending on where and when it is taken.

The developer also wants to try several turn-rate and thrust settings on the phone without rebuilding. This design adds thrust pickups, impact spin, and an in-game tuning panel.

## Decisions

| Topic | Decision |
|---|---|
| Thrust up / thrust down | Multiply thrust force for a fixed time. The speed cap scales with the same multiplier. A new pickup replaces the current effect. |
| Boost | A free (no fuel) full-power burn for a fixed time. The player can still steer, at a reduced turn rate, while the nose wobbles randomly. |
| Impact spin | Glancing hits spin the ship toward its outgoing direction; head-on hits barely spin it. Spin decays to zero. |
| Turn rate | Capped at all times; lower during a boost. |
| Testing | An in-game tuning panel with live sliders. Values last for the session only. |
| Placement | Level authors place pickups, like barriers and planets. |

## Gameplay rules

All values below are tuning defaults. Each is a slider in the tuning panel.

### Speed cap

- The ship's speed cap is `max_speed × power`, where `power` is 1.0 without an active thrust effect. Default `max_speed` is 800 px/s.
- Above the cap, the ship slows toward it at `OVERSPEED_DECEL` (400 px/s²) instead of snapping down. This covers a thrust-down pickup taken at speed and a thrust-up effect running out.
- A hard limit of 1200 px/s (`TUNNEL_LIMIT`) still applies to ships and asteroids, so nothing can pass through a barrier between physics steps.
- Asteroids keep their own 1200 px/s cap.

### Thrust effects

- Thrust force is `thrust × power`. Default `thrust` is 600.
- **Thrust up** sets `power` to `power_up` (default ×1.5) for `effect_seconds` (default 8 s).
- **Thrust down** sets `power` to `power_down` (default ×0.6) for `effect_seconds`.
- Taking a thrust pickup replaces any active thrust effect or boost and restarts the timer.
- Fuel burn per second does not change with `power`.

### Boost

- Lasts `boost_seconds` (default 1.5 s). It starts the moment the ship touches the pickup and replaces any active effect.
- The engine fires at full power (`thrust × 1.0`) whether or not the finger is down, and burns no fuel. It works with an empty tank, and it pauses the empty-tank countdown while it burns.
- With the finger down, the ship steers toward the touch point at `boost_turn_rate` (default 3 rad/s). With the finger up, it holds its heading.
- A smooth random wobble of up to `boost_wobble` (default 1.5 rad/s) is added to the angular velocity during the whole burn.

### Turning

- Outside a boost, the ship turns toward the touch point at up to `turn_rate` (default 15 rad/s), only while the finger is down.
- With the finger up and no boost, the ship holds its heading. The only exception is impact spin.

### Impact spin

- A contact counts as a hit when the speed change along the contact normal is at least `MIN_IMPACT_SPEED` (20 px/s), the same threshold as damage.
- The hit adds angular velocity of `spin_per_speed × tangential speed` (default 0.01 rad/s per px/s), capped at `spin_max` (default 4 rad/s). The tangential speed is the ship's speed along the contact surface after the hit. The sign turns the nose toward the outgoing direction of travel.
- Spin decays exponentially to zero, with time constant `spin_decay` (default 0.35 s, so it is mostly gone after about 1 s).
- While the finger is down, steering replaces spin, and the spin resets to zero.

### Planet gravity

- A global `planet_gravity` multiplier (default ×1) scales the pull of every `PLANET` preset gravity body, and `black_hole_gravity` (default ×1) does the same for black holes. Stars are unaffected.
- Once the playtest settles on a value, it is baked into the levels and the multiplier stays at ×1.

## Pickups

- `scenes/pickup.tscn` with `scenes/pickup.gd`: `class_name Pickup`, an `@tool` `Area2D` with a circle of radius 28.
- `enum Kind { THRUST_UP, THRUST_DOWN, BOOST }` and `@export var kind`.
- Code-drawn and pulsing:
  - THRUST_UP: a green ring with an up-chevron.
  - THRUST_DOWN: a violet ring with a down-chevron.
  - BOOST: an orange ring with a flame.
- Only a `Ship` collects a pickup. Asteroids pass through. On contact the pickup applies its effect, plays the `pickup` sound, and frees itself. Restarting the level restores it.
- The HUD shows the active effect and its seconds left, for example `Thrust ×1.5 · 6 s`, `Thrust ×0.6 · 3 s` or `Boost`. With no effect the label is hidden.

## Tuning panel

- `scripts/tuning.gd` is autoloaded as `Tuning`. It holds one variable per setting, a `DEFAULTS` table, a `RANGES` table (min, max, step), `reset()`, and a `changed` signal.

| Setting | Default | Range | Step |
|---|---|---|---|
| `max_speed` (px/s) | 800 | 400–1200 | 50 |
| `thrust` (px/s²) | 600 | 300–1200 | 50 |
| `turn_rate` (rad/s) | 15 | 1–20 | 0.5 |
| `boost_turn_rate` (rad/s) | 3 | 0.5–10 | 0.5 |
| `boost_seconds` | 1.5 | 0.5–4 | 0.25 |
| `boost_wobble` (rad/s) | 1.5 | 0–4 | 0.25 |
| `power_up` (×) | 1.5 | 1–3 | 0.1 |
| `power_down` (×) | 0.6 | 0.2–1 | 0.05 |
| `effect_seconds` | 8 | 2–20 | 1 |
| `planet_gravity` (×) | 1 | 0.25–4 | 0.25 |
| `black_hole_gravity` (×) | 1 | 0.25–4 | 0.25 |
| `spin_per_speed` (rad/s per px/s) | 0.01 | 0–0.03 | 0.0025 |
| `spin_max` (rad/s) | 4 | 0–8 | 0.5 |
| `spin_decay` (s) | 0.35 | 0.1–2 | 0.05 |

- The panel (`scenes/tuning_panel.gd`) is a full-screen overlay. It has one labelled slider per setting showing its live value, plus Reset and Close buttons, inside a scroll container.
- A **Tune** button opens the panel from the main menu, and another sits in the level HUD next to Restart and Menu.
- In a level, the game pauses while the panel is open. The panel consumes all touches, so none reach the ship.
- The ship reads `Tuning` every physics step. Gravity bodies listen to `Tuning.changed` and update their field strength. Changes apply without a restart.
- Values last for the session. There is no save data.

## Levels

| Level | Pickups added |
|---|---|
| 1 Corridor | One thrust up on the first long straight; one thrust down before the second orange stretch |
| 2 Slingshot | One boost before the bend, so firing it at the right heading slings the ship around the planet |
| 3 Asteroid field | One thrust down inside the field; one thrust up on the long route |
| 4 Black hole | One boost on the approach to the black hole |
| 5 Gauntlet | One thrust up just before the red section |

Pickups keep at least `radius + 16` px clear of every barrier segment.

## Verification

### Automated

- Thrust up raises acceleration and the speed cap by `power_up`; both return to normal after `effect_seconds`.
- Thrust down at a speed above the new cap slows the ship gradually: no single-step drop larger than `OVERSPEED_DECEL / 60`, and the ship reaches the cap.
- A boost with zero fuel accelerates the ship along its heading and burns no fuel. It ends after `boost_seconds`.
- During a boost with the finger held, the turn rate never exceeds `boost_turn_rate + boost_wobble`.
- With the finger up and no boost, a glancing wall hit spins the ship toward its outgoing direction; a head-on hit spins it less than a quarter as much. The spin decays below 0.05 rad/s within 1.5 s.
- A pickup is collected by a ship and ignored by an asteroid.
- `Tuning.reset()` restores every default; the test runner resets `Tuning` before each test.
- `planet_gravity` scales planet pull only; `black_hole_gravity` scales black hole pull only.
- Levels: no pickup lies within `radius + 16` px of a barrier segment.

### Manual

- The developer installs the next prerelease APK on the phone, plays all five levels, and tries settings in the tuning panel.

## Out of scope

- Saving tuning values between sessions.
- Random pickup placement or respawning pickups.
- Pickup types other than the three above.
