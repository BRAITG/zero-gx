# Zero-GX Prototype Design

Date: 2026-10-12
Status: Approved design, pending spec review

## Purpose

Zero-GX is a 2D physics game for Android. A spaceship crosses a zero-gravity course from point A to point B. The course has no air and no friction. This prototype answers one question: **is steering through gravity wells fun?** It is not a release candidate.

The game borrows only its premise from AstroCat, a mini game in `andrebrait/cefet-games-meow-au`. All code is new, and the player is a spaceship.

## Decisions

| Topic | Decision |
|---|---|
| Audience | Prototype for evaluating the mechanics |
| Engine | Godot 4.7 (latest stable: 4.7.2), GDScript |
| View | Full 2D |
| Failure | Running out of fuel, or crashing hard enough to lose all health |
| Course | Artificial barriers placed by an unseen builder. The camera follows the ship in any direction. |
| Orbit model | Asteroids follow fixed circular paths until something disturbs them, then switch to full physics |

## Gameplay rules

All numbers are starting values to tune during playtests. They live as named constants or exported properties, so they can be changed without editing logic.

### Ship

- **Controls:** touch and hold anywhere. The ship turns toward the touch point and thrusts while the finger is down. On release it stops thrusting and coasts.
- **Fuel:** 100 units, burned at 10 units per second of thrust.
- **Coasting on empty:** a ship with no fuel keeps moving, but a 5-second countdown starts and shows on screen. When it reaches 0, the level is lost. A boost pauses the countdown.
- **Restart:** the HUD has a restart button. It covers cases such as a ship stuck orbiting forever.
- **Health:** 100. At 0 the ship explodes and the level is lost.

### Impact damage

```
damage = (impulse / ship_mass) * DAMAGE_PER_SPEED * multiplier
```

`impulse / ship_mass` is the change in speed along the contact normal, rebound included. It is read from the physics engine's reported contact impulse, so glancing hits produce little damage. `DAMAGE_PER_SPEED` starts at 0.05 per px/s. With barrier bounce 0.8, a head-on 500 px/s hit on an orange barrier changes normal speed by about 900 px/s and deals about 45 damage. Changes below `MIN_IMPACT_SPEED` (20 px/s) deal no damage, so resting contact is harmless.

| Surface | Multiplier |
|---|---|
| Blue barrier | 0.1. The ship bounces and stays nearly safe even at high speed. |
| Orange barrier | 1.0 |
| Asteroid | 1.0 |
| Planet surface | 1.0 |
| Deep-red barrier | Instant death |
| Black hole or star | Instant death |

### Gravity bodies

One body type with three presets. Pull follows an inverse-square law and drops to zero beyond the body's range. Pulls from overlapping bodies add together.

| Preset | Size | Pull | Range | On contact |
|---|---|---|---|---|
| Planet | Medium | Moderate | Local | 1.0 crash damage |
| Black hole | Planet-sized | Huge | Medium | Instant death |
| Star | Huge | Strong | Very long, covering a whole course section | Instant death |

Stars sit outside the barriers. They bend the trajectory of everything in their section, but the ship cannot normally reach them.

### Asteroids

- Asteroids have no pull of their own. Every gravity body pulls them.
- They bounce off barriers, the ship, and each other.
- An asteroid that touches a black hole or a star is destroyed.
- An asteroid that hits a planet damages it by `impulse * PLANET_DAMAGE_PER_IMPULSE`. Impulse is the asteroid's mass times its change in normal speed, so heavier and faster asteroids do more damage.
- **Flinging:** the ship can ram an asteroid toward a planet. The ship takes 1.0 crash damage from the ram. This is meant to be a costly side strategy.

### Orbiting asteroids (rails until disturbed)

- Level authors give an orbiting asteroid an `orbit_parent` planet, an orbit radius, an angular speed, a direction, and a start angle.
- While on rails, the asteroid is a frozen kinematic `RigidBody2D` that a script moves along an exact circle. Other gravity bodies do not affect it.
- It still collides. The ship bounces off it and takes the usual asteroid damage.
- **Release:** when the ship or another asteroid hits it, the asteroid unfreezes. It keeps its current tangential orbital velocity and receives an impulse equal and opposite to the one the colliding body received. After release it follows full physics.
- If its parent planet shatters, the asteroid is released with its current orbital velocity.

### Planets: destruction

- Planets have a `destructible` flag and a `health` value. Black holes and stars are never destructible.
- The ship cannot damage planets. Only asteroid impacts can.
- At 0 health, the planet is removed and its pull disappears. 12–20 asteroids spawn at its surface and fly outward with randomized speed.

### Level-design rule

With no player input, no asteroid hits a planet. Asteroids should reach planets only because of the player. This is a rule for level authors, not an engine constraint. The engine fully supports asteroid–planet collisions, and an automated check (see Verification) flags levels that break the rule.

### Barriers

- Barriers are glowing line segments or polygon outlines, each with a `kind`: blue, orange, or deep red.
- All barriers bounce bodies with no friction. Every collision between solid bodies bounces at 0.8: Godot adds both bodies' bounce, and each side contributes 0.4.
- Ships are capped at a tunable speed (800 px/s by default, scaled by thrust pickups) and never exceed 1200 px/s; asteroids are capped at 1200 px/s. Barriers collide as 16 px thick slabs, so nothing can pass through a wall between physics steps.
- The color communicates danger. Deep red should look obviously lethal.

### Camera and win

- The camera follows the ship with smoothing. It looks slightly ahead in the direction of travel, so the course can run in any direction.
- Entering the goal area at point B wins the level.

## Godot structure

### Project settings

- Default 2D gravity is 0.
- Default linear and angular damping are 0.

### Scenes

Each scene is a `.tscn` with one `.gd` script, stored in `scenes/`.

| Scene | Root node | Responsibilities |
|---|---|---|
| `ship` | `RigidBody2D` | Input, turning, thrust, fuel, health, impact damage, explosion, lost/won signals |
| `gravity_body` | `StaticBody2D`, with a circle collider and an `Area2D` child | Uses `Area2D` point gravity with `gravity_space_override = COMBINE`, `gravity_point_unit_distance` = body radius (inverse square), and an influence circle sized to `range`. Exports `preset`, `strength`, `range`, `radius`, `lethal`, `destructible`, `health`. Also handles shattering. |
| `asteroid` | `RigidBody2D` | Drifting or orbiting on rails, release on hit, planet damage, destruction by lethal bodies |
| `barrier` | `StaticBody2D`, with a polygon or segment collider and a `Line2D` | Exports `kind`, which sets the damage multiplier, color, and a bouncy, frictionless physics material |
| `goal` | `Area2D` | Emits a win signal when the ship enters |
| `pickup` | `Area2D` | Thrust up, thrust down or boost; applies its effect to the ship on contact. See `2026-10-13-thrust-pickups-tuning-design.md`. |
| `level` | `Node2D` script on each level's root | Uses the level's `Ship` position as point A, connects win and lose signals, handles restart and returning to the menu |
| `hud` | `CanvasLayer` | Fuel bar, health bar, active effect, restart, menu and tune buttons. Android's back gesture also returns to the menu. |
| `main` | `Control` | Lists levels from `levels/` and loads the selected one |

Levels are stored at `levels/level_NN.tscn`. Each is built in the Godot editor from the scenes above.

### Collision handling

- The ship and asteroids enable `contact_monitor` and read contact impulses and colliders in `_integrate_forces`.
- Each colliding surface reports its damage multiplier or lethality through a small shared method, `impact_multiplier()`. Lethal surfaces return a sentinel meaning instant death.

## Test levels

1. **Corridor:** a bending blue course with some orange stretches. It teaches thrust, fuel, and bouncing.
2. **Slingshot:** one planet. The route that fits within the fuel budget requires a gravity assist around it.
3. **Asteroid field:** asteroids on rails plus drifting asteroids. A destructible planet blocks a shortcut, so flinging asteroids at it is the costly option.
4. **Black hole:** a narrow pass beside a black hole whose pull bends the line hard.
5. **Gauntlet:** a star outside the barriers pulls the section sideways, the edges are deep red, and the course changes direction.

## Verification

### Automated

- Run with `godot --headless -s tests/run_tests.gd`. The runner is plain GDScript that extends `SceneTree` and uses asserts. It needs no plugins and exits with a nonzero status on failure.
- **Damage:** a head-on hit deals more damage than a graze at the same speed. Color multipliers apply. Deep red, black holes, and stars kill instantly.
- **Fuel:** thrust burns fuel at the configured rate. An empty ship keeps coasting and loses 5 seconds after the tank empties; a boost pauses that countdown.
- **Gravity:** pull follows the inverse-square law and is zero beyond the configured range. Overlapping bodies' pulls add together.
- **Rails:** an orbiting asteroid next to a black hole stays on its circle for 60 simulated seconds. It switches to full physics when hit.
- **Shatter:** a planet hit until its health reaches 0 spawns 12–20 asteroids and its pull disappears.
- **Swallow:** a black hole destroys an asteroid that touches it.
- **Level-design check:** each level runs for 200 simulated seconds with no input (longer than a slow first attempt). Any asteroid–planet contact fails the check and names the level and the bodies involved.

### Manual

- Code is written, tested headless, and exported to a debug-signed Android APK on a Linux server. The APK is published as a prerelease on `BRAITG/zero-gx`.
- The developer installs the APK on a phone and plays all five levels. The MacBook is optional, for editing levels in the Godot editor.

## Out of scope

- Ship customization. The design keeps the ship as its own scene so customization can be added later.
- Art beyond simple shapes and glowing lines.
- Music. Sound effects are generated in code; there are no audio files.
- Save data and progression.
- Menus beyond the level list.
- Play Store requirements.
