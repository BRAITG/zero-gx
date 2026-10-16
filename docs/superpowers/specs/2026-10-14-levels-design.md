# Levels Design

Date: 2026-10-14
Status: Approved in conversation
Part 2 of 3 of the vertical slice (1: scoring and progression, 2: ten levels, 3: visuals and sound)

## Purpose

Replace the five prototype levels with new ones that teach the game through play. The guided tutorials (`2026-10-16-tutorials-design.md`) come first; Launch and Drift stay as slightly harder, unguided repeats of their lessons, and a star level brings the total to eleven. The test is whether the game holds up over a sequence of levels.

## Rules

- Each level introduces at most one new mechanic. It may reuse any mechanic introduced earlier.
- Every level opens with a title card ("Level 2 · Drift") that fades out at the first thrust.
- Every level adds a one-line hint to the card that names its new mechanic and what it means for the player. Playtesting showed that layout alone does not teach these mechanics.
- Asteroids on fixed orbits and destructible planets are deferred to world 2. The engine keeps them.

## Curriculum

| # | Name | New mechanic | Layout |
|---|---|---|---|
| 1 | Launch | Thrust and steering | A 340 px wide blue corridor with two bends. |
| 2 | Drift | Inertia and fuel | A 13,500 px, 400 px wide course, and the ship starts with 15 fuel. Reaching speed and making the bend leaves about 5, so the player must coast. |
| 3 | Brake | Orange walls | Orange zigzag with three 90° corners. Fast corner hits hurt, so players learn to turn around and brake. |
| 4 | Pull | Planet gravity | Wide straight with a planet in the lower half. Flying straight drags the ship into it; aiming high wins. |
| 5 | Swing | Slingshot | L-shaped course with a planet in the inside of the corner (2200, 200), and the ship starts with 14 fuel. Coasting around the planet from about 300 px/s leaves about 3 fuel; braking through the corner runs dry. |
| 6 | Edge | Red walls | A narrow red S-bend (260 px wide) between two wide blue sections. |
| 7 | Power | Thrust up and down pickups | Thrust-up on the first straight before an orange climb; thrust-down at the start of the climb. |
| 8 | Rocks | Drifting asteroids | Wide corridor crossed by 30 drifting asteroids (40–120 px/s, random directions). Flying straight through costs the autopilot about a third of its hull. |
| 9 | Abyss | Black hole | A black hole 500 px above an orange spike from the floor. The pass between them is inside its strongest pull: a slow ship gets swallowed, a fast and low one (about 100 px above the spike tip) gets through. 14 drifting asteroids, some of which the black hole swallows. |
| 10 | Sun | Stars | A vertical corridor whose middle 1,400 px are red, with a star (radius 900, surface pull 533) just outside the right wall dragging the ship toward it the whole way up; the course then turns left to the goal. |
| 11 | Burn | Boost pickup | Finale: planet straight, orange climb through a red gate, a black hole straight. Boosts near the start, at the start of the black-hole straight and before the goal; 16 asteroids on the upper climb and the black-hole straight, none near the planet. |

## Winnability

- Every level has a hidden `Line2D` named `Route`: waypoints from the start to the goal, invisible in the game.
- A test autopilot flies each route with the real ship physics. It steers toward a velocity that points at the next waypoint and slows near it, thrusting only when its velocity error exceeds a dead band.
- The level must be won within 80 s of simulated time. The route is a proof that the level can be won, not the best line.
- A route can set `metadata/cruise` (its speed) and `metadata/coast` (waypoint indices flown to without thrust, reached within 300 px). Level 5 (Swing) uses both to ride the slingshot.

## Other changes

- The menu lists the six tutorials ("Training 1–6") before the eleven levels, in three columns. See `2026-10-16-tutorials-design.md`.
- The level-design check that idles each level for 200 s runs only on levels that have both asteroids and gravity bodies.

## Out of scope

- Level names in the menu.
- World 2 mechanics.
