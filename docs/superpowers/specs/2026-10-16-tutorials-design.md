# Guided Tutorials and Velocity Vector Design

Date: 2026-10-16
Status: Approved in conversation

## Purpose

A first-time player reported that too many hard things arrive at once (no friction, walls, limited fuel) and asked for one at a time:

1. no friction
2. walls
3. limited fuel
4. orange barriers with limited fuel

She also skips text. The developer agreed that a real tutorial is needed, and asked that it be interactive:

- touch a marked point and see the velocity vector;
- touch 90° down and see the vector compose instead of the ship turning down, because there is no friction to cancel the sideways motion;
- touch opposite to the motion to nearly stop, learning that braking in space means accelerating the other way.

## Decisions

| Topic | Decision |
|---|---|
| Structure | Six guided **tutorial stages** before the levels. Levels 1–4 stay as harder, unguided versions of the same mechanics. |
| Tutorials | T1 no friction, T2 walls, T3 fuel, T4 orange and red walls with fuel, T5 gravity, T6 black holes and stars |
| Step system | Each tutorial is a script of awaited steps (message, touch the target, wait for a condition) running on a normal, unpaused level. |
| Camera | Unchanged: the level tour and the goal arrow are enough. |
| Velocity vector | A translucent arrow from the ship, its length proportional to speed. Shown in tutorials and levels 1–4. |

## Tutorial step system

- `scenes/tutorial.gd` (`class_name Tutorial extends Level`). Each tutorial scene's root uses its own script extending `Tutorial` and overriding `lesson()`, a coroutine of steps. Physics runs normally.
- Steps:
  - `await say(text)`: a caption card with an **OK** button. The ship is frozen while it shows, so nothing drifts away mid-read.
  - `await touch_target(direction, hold, text)`: a pulsing ring on screen, 300 px from the ship in `direction` (a Vector2, or a Callable returning one, so the ring can follow "opposite to your motion"). Only touches on the ring count; while held, the ship steers and thrusts toward it. The step ends after `hold` seconds of holding.
  - `await until(condition, text)`: shows `text` until `condition` (a Callable returning bool) is true.
  - `reveal_goal()`: shows the goal, hidden until then.
- A lethal hit or an empty tank loses a training stage like any level, and Retry restarts the stage. The only rescue is Training 6's scripted black hole close call.
- Tutorials have no tour and no intro card. Their lesson is the introduction.

## Tutorials

| # | Setting | Lesson |
|---|---|---|
| T1 Coast | Open space bounded by distant blue walls; a full tank | Say "your ship has one engine". Touch a ring to the right (1.5 s). Say "that arrow is your velocity". Release and coast 2 s: no friction, no fuel used. Touch a ring straight down (1.5 s). Say "you did not turn down: the engine adds to your velocity". Touch the ring opposite your motion until speed < 40. Say "braking means accelerating the other way". Reveal the goal. |
| T2 Bounce | A blue corridor with one corner; a full tank | Say "blue walls are safe". Touch a ring toward the wall until the ship hits it. Say "you bounce and keep your speed". Reveal the goal around the corner. |
| T3 Fuel | A long straight; the tank holds 25 | Say "thrust burns fuel; when it runs out you have 5 s". Touch a ring ahead until fuel ≤ 15. Say "let go and coast the rest". Reveal the goal at the far end. |
| T4 Damage | An orange zigzag with a red gate above the corner; the tank holds 40 | Say "orange walls hurt, more the faster you hit". Touch a ring ahead (0.8 s), then brake on a ring opposite the motion until speed < 150. Say "slow down before corners", then "red walls destroy your ship on contact: fly through the middle of the gate". Reveal the goal. |
| T5 Gravity | A planet 300 px from the ship's path; the ship starts drifting past it | Say "planets pull you; watch your arrow bend". Wait until the ship has passed the planet, without touching. Say "fly close past the planet to swing around it". Reveal the goal behind the planet. |
| T6 Danger | A black hole beside the ship's drift and a star off to the right, outside the walls | Say \"black holes pull far harder and destroy anything that touches them\". Watch 2 s (the path bends about 40°). Touch a ring pointing away from the black hole until 950 px clear. Say \"stars burn on touch and their pull reaches across a course\". Reveal the goal, past the star's pull. |

## Velocity vector

- Drawn from the ship's centre along its velocity: 1 px per 4 px/s, up to 200 px. Translucent white, with an arrowhead.
- Always on in tutorials (their `show_velocity` export). In levels it is off unless the player turns it on in Settings.

## Progression and menu

- Tutorials live in `res://tutorials/` as `tutorial_1.tscn` … `tutorial_6.tscn`. `Progress.levels()` lists tutorials first, then levels. Unlocking runs along that whole list.
- The menu labels them "Training 1–6" and lays out all seventeen buttons in three columns.

## Swing level

- The planet sits inside the corner at (2200, 200), 136 px from each inner wall, so the swing hugs the turn. Only the slingshot fits the 14-unit tank.

## Verification

- A tutorial runner test drives each lesson through its steps with scripted touches and checks that it reaches the goal, and that no guided step kills the ship.
- `touch_target` ignores touches off the ring.
- A lethal hit or an empty tank loses a training stage like any level, and Retry restarts it. Training 6's scripted black hole close call is the only rescue.
- The velocity vector length follows speed and caps at 200 px.
- Progress lists tutorials before levels and unlocks Level 1 after Training 5.
