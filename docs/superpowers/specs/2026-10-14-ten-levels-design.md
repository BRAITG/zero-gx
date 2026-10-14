# Ten Levels Design

Date: 2026-10-14
Status: Approved in conversation
Part 2 of 3 of the vertical slice (1: scoring and progression, 2: ten levels, 3: visuals and sound)

## Purpose

Replace the five prototype levels with ten new ones that teach the game through play, not through a tutorial. The test is whether the game holds up over a sequence of levels.

## Rules

- Each level introduces at most one new mechanic. It may reuse any mechanic introduced earlier.
- Every level opens with a title card ("Level 2 · Drift") that fades out at the first thrust.
- Levels 1–5 add a one-line hint to the card, because people do not understand frictionless motion, inertia and gravity without being told. From level 6 on there is no hint: the layout teaches the new mechanic.
- Asteroids on fixed orbits, destructible planets, and stars are deferred to world 2. The engine keeps them.

## Curriculum

| # | Name | New mechanic | Layout |
|---|---|---|---|
| 1 | Launch | Thrust and steering | Wide blue corridor with one gentle bend. Blue walls only bounce. |
| 2 | Drift | Inertia and fuel | 13,500 px course, and the ship starts with 20 fuel. Reaching full speed and making the bend takes about 16, so the player must let go and coast. |
| 3 | Brake | Orange walls | Orange zigzag with three 90° corners. Fast corner hits hurt, so players learn to turn around and brake. |
| 4 | Pull | Planet gravity | Wide straight with a planet in the lower half. Flying straight drags the ship into it; aiming high wins. |
| 5 | Swing | Slingshot | L-shaped course with a planet at the corner. Swinging around it turns the ship for free. |
| 6 | Edge | Red walls | A narrow red S-bend (260 px wide) between two wide blue sections. |
| 7 | Power | Thrust up and down pickups | Thrust-up on the first straight before an orange climb; thrust-down at the start of the climb. |
| 8 | Rocks | Drifting asteroids | Wide corridor crossed by eight slowly drifting asteroids. |
| 9 | Abyss | Black hole | A black hole inside the course; an orange spike from the floor forces the route to pass about 500 px from it. |
| 10 | Burn | Boost pickup | Finale: planet straight, orange climb through a red gate, a black hole straight, and a boost before the goal. |

## Winnability

- Every level has a hidden `Line2D` named `Route`: waypoints from the start to the goal, invisible in the game.
- A test autopilot flies each route with the real ship physics. It steers toward a velocity that points at the next waypoint and slows near it, thrusting only when its velocity error exceeds a dead band.
- The level must be won within 80 s of simulated time. The route is a proof that the level can be won, not the best line.

## Other changes

- The level menu lays out its buttons in two columns, because ten rows do not fit the 720 px screen.
- The level-design check that idles each level for 200 s runs only on levels that have both asteroids and gravity bodies.

## Out of scope

- Level names in the menu.
- World 2 mechanics.
