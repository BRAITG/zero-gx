# Level Format Design (sub-project 1 of community levels)

Date: 2026-10-16
Status: Approved in conversation

## Purpose

Community levels need a parseable, versioned format that the game, the in-app editor and the community server all share; the server must validate submissions against it. The game's own levels move to the same format. Later sub-projects: the in-app editor, the community server (Play Games sign-in, submissions, storage), rankings, and Play cloud saves.

## Format

A level is a JSON object. Official levels and tutorials are plain `*.json` files in a stable layout (sorted keys, 2-space indent, whole numbers as integers, trailing newline); player drafts are gzip-compressed `*.json.gz`. A level version is identified by `LevelFormat.sha256`, the SHA-256 of that text. Coordinates are world pixels, as integers where possible (10 px = 1 m).

```jsonc
{
  "format": "zero-gx-level", "version": 1,
  "title": "Brake", "hint": "…", "show_velocity": false,
  "ship":  { "position": [0, 0], "rotation": 0, "velocity": [0, 0],
             "fuel": 100,                    // 1–1000 or "unlimited"
             "hull": 100 },                  // 1–1000 or "unlimited"
  "goal":  { "position": [4150, 0] },
  "walls": [ { "kind": "blue", "points": [[x, y], …], "closed": false } ],
  "bodies": [ { "kind": "planet", "position": [x, y],
                "radius": 64, "strength": 3200, "reach": 450,    // optional; preset values if absent
                "destructible": false, "health": 100 } ],        // optional
  "asteroids": [ { "position": [x, y], "velocity": [x, y],
                   "orbit": { "body": 0, "radius": 150, "speed": 0.8, "angle": 0 } } ],  // orbit optional
  "pickups": [ { "kind": "thrust_up", "position": [x, y] } ],
  "tour":  [ { "position": [x, y], "text": "…" } ],
  "route": { "points": [[x, y], …], "cruise": 300, "coast": [2, 3] }  // optional
}
```

- Kinds: walls `blue | orange | red`; bodies `planet | black_hole | star`; pickups `thrust_up | thrust_down | boost`.
- `orbit.body` is an index into `bodies`.
- `route` is the hidden winnability proof the autopilot test flies; community levels may omit it.

## Unlimited fuel and hull

- **Unlimited fuel:** thrust burns nothing, there is no empty-tank countdown, and the fuel score component is 0. The gauge shows full with "∞".
- **Unlimited hull:** non-lethal damage is ignored. Red walls, black holes and stars still destroy the ship. The hull score component is 0, and the gauge shows "∞".
- A limited tank shows on the gauge against at least 100 units, so small tanks look small. A limited hull fills its gauge.

## Validation (game today, server later)

- `format == "zero-gx-level"` and `version == 1`. All numbers are finite.
- Coordinates are within ±50,000 px.
- Counts: at most 300 walls with 2–64 points each, 32 bodies, 150 asteroids, 50 pickups, 12 tour stops, and 64 route points.
- Text: `title` 1–40 characters; `hint` and tour texts up to 200.
- Fuel and hull are 1–1000 or `"unlimited"`.
- Body overrides: radius 8–3000, strength 0–300,000, reach 0–10,000, health 1–10,000. An orbit's body index must exist.
- Each kind keeps its role (`KIND_LIMITS`). Total pull is the pull at 1000 px, `strength × (radius / 1000)²`, and acts like mass; the limits are independent, so any radius pairs with any total pull in range:
  - planet: radius 32–240, total pull 0–100, reach 0–1500.
  - star: radius 300–3000, total pull 150–6000, reach 0–8000.
  - black hole: radius 32–96, total pull 30–260, reach 0–1500.
- The ship must not start inside a wall's collision slab or a body, and must not start inside the goal.
- The file is at most 64 KB uncompressed.

## Game changes

- `scripts/level_format.gd` (`class_name LevelFormat`): `read(path)`, `write(path, data)`, `validate(data) -> PackedStringArray`, `build(data, script) -> Level`, `serialize(level) -> Dictionary`.
- Stages are opened through `Progress.open(id)`. Levels build from `levels/<id>.json` with `level.gd`. Tutorials build from `tutorials/<id>.json` with their lesson script `tutorials/<id>.gd`. Retry rebuilds the same way.
- The `.tscn` level and tutorial scenes are removed. The export packs the `.json` files.

## Verification

- Every shipped level and tutorial passes `validate`.
- Serializing a built level gives back the same data (round trip).
- The existing autopilot, tutorial and level-design tests pass on the converted levels, proving gameplay is unchanged.
- Validation rejects each rule above (one case per rule).
- Unlimited fuel never burns or strands; unlimited hull ignores a hard orange hit but dies on red.
