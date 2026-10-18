# Demos and JSON Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record every level run as a 30 fps demo that plays back identically on any device, check demos against their level, and store official levels and tutorials as plain JSON.

**Architecture:** `LevelFormat` gains a stable JSON writer and a content hash; official files become `.json`, player drafts stay `.json.gz`. A `Demo` class holds a run's frames and events and encodes them to a gzip binary; a `DemoRecorder` node inside each `Level` samples the ship and asteroids every second physics tick; `DemoCheck` validates a demo against level data; a `DemoViewer` scene replays a demo by placing frozen nodes, without physics.

**Tech Stack:** Godot 4.7.2, GDScript, the existing headless test runner (`tests/run.sh`).

**Spec:** `docs/superpowers/specs/2026-10-16-community-design.md` (sub-project 1 of "Sub-projects and order"; sections "Demos" and "Demo checks").

## Global Constraints

- Demos are sampled at 30 frames per second: `Demo.STEP = 1.0 / 30.0`; physics runs at 60 Hz, so one frame per two physics ticks.
- A demo names its level by `level_sha256`: SHA-256 (64 lowercase hex characters) of the level's JSON text as `LevelFormat.to_json` writes it.
- Official level and tutorial files are plain JSON in a stable layout: keys sorted, 2-space indent, whole numbers written as integers, trailing newline.
- Player drafts stay `user://levels/<id>.json.gz`.
- An encoded demo must stay under 512 KB (`Demo.MAX_BYTES = 524288`); recording stops after `Demo.MAX_FRAMES = 18000` frames (10 minutes) and marks the demo truncated.
- Tutorials are not recorded (training is not ranked).
- Public text and code comments use normal English; every level stays autopilot-winnable; `tests/run.sh` exits 0.

## Review Focus

1. **A run that ends in a loss** (crash, burned up, stranded): the demo must still encode, decode and play back to its last frame; only `DemoCheck` rejects it. Test in Task 3 and Task 5.
2. **Asteroids that appear or vanish mid-run** (planet shards, asteroids destroyed on impact): playback must show each shard from its spawn frame and hide removed ones. Test in Task 2 (codec) and Task 3 (recorded on a level with a destructible planet).
3. **Unlimited fuel or hull:** recorded values must not overflow or read as empty; `DemoCheck` must skip the fuel rule for unlimited fuel. Test in Task 4.
4. **Scrubbing backwards in the viewer:** seeking to an earlier frame must restore every object, including shards that had not spawned yet. Test in Task 5.
5. **Editing a draft after its finishing test run:** the stored demo no longer matches the draft's hash and must not be offered for watching or submission. Test in Task 3.

---

### Task 1: Plain JSON level files and the level hash

**Files:**
- Modify: `scripts/level_format.gd` (`read`, `write`, `EXTENSION`; add `to_json`, `sha256`)
- Modify: `scripts/progress.gd`, `scripts/my_levels.gd`, `tests/test_levels.gd`, `export_presets.cfg` (`include_filter`)
- Replace: `levels/level_NN.json.gz` → `levels/level_NN.json`, `tutorials/tutorial_N.json.gz` → `tutorials/tutorial_N.json`
- Test: `tests/test_level_format.gd`

**Interfaces:**
- Produces: `LevelFormat.EXTENSION := ".json"`; `MyLevels.EXTENSION := ".json.gz"`; `static func to_json(data: Dictionary) -> String`; `static func sha256(data: Dictionary) -> String`; `read(path)` and `write(path, data)` choose gzip when the path ends in `.gz`, plain text otherwise; `write` of a plain path writes `to_json(data)`.

- [ ] **Step 1: Write the failing tests** in `tests/test_level_format.gd`:

```gdscript
func test_json_layout_is_stable() -> void:
	var text := LevelFormat.to_json({"b": 2.0, "a": [1.5, 3.0], "c": {"z": true, "y": "x"}})
	check(text == '{\n  "a": [\n    1.5,\n    3\n  ],\n  "b": 2,\n  "c": {\n    "y": "x",\n    "z": true\n  }\n}\n', "layout: %s" % text)

func test_official_files_round_trip_byte_for_byte() -> void:
	for dir in [Progress.LEVELS_DIR, Progress.TUTORIALS_DIR]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".json"):
				var path: String = dir + file
				check(FileAccess.get_file_as_string(path) == LevelFormat.to_json(LevelFormat.read(path)), "%s is not in the stable layout" % path)

func test_hash_names_the_content() -> void:
	var data := LevelDoc.blank()
	var hash := LevelFormat.sha256(data)
	check(hash.length() == 64 and hash == LevelFormat.to_json(data).sha256_text(), "hash: %s" % hash)
	data.title = "Other"
	check(LevelFormat.sha256(data) != hash, "a change must change the hash")
```

- [ ] **Step 2: Run** `TEST_FILTER=test_level_format tests/run.sh`. Expected: FAIL (`to_json` not found).

- [ ] **Step 3: Implement** `to_json` (normalize recursively with the existing `_num` so whole floats become ints, then `JSON.stringify(value, "  ", true)` plus `"\n"`), `sha256` (`to_json(data).sha256_text()`), and extension-aware `read`/`write`. Point `MyLevels` at its own `EXTENSION`.

- [ ] **Step 4: Migrate the files** with a throwaway script: for each `levels/*.json.gz` and `tutorials/*.json.gz`, `LevelFormat.write(<same stem>.json, LevelFormat.read(gz))`, then `git rm` the `.json.gz` files. Update `include_filter` to `levels/*.json, tutorials/*.json`.

- [ ] **Step 5: Run** `tests/run.sh`. Expected: exit 0, every test passes.

- [ ] **Step 6: Verify the export ships the files raw:** `godot --headless --path . --export-pack "Android" build/check.zip && unzip -l build/check.zip | grep -E 'levels/level_01.json$'`. Expected: one line listing `levels/level_01.json`. Delete `build/check.zip`.

- [ ] **Step 7: Commit** `feat: official levels and tutorials as plain JSON; level content hash`.

### Task 2: The demo codec

**Files:**
- Create: `scripts/demo.gd`
- Test: `tests/test_demo.gd`

**Interfaces:**
- Produces `class_name Demo extends RefCounted` with:
  - `const FORMAT_VERSION := 1`, `const STEP := 1.0 / 30.0`, `const MAX_FRAMES := 18000`, `const MAX_BYTES := 524288`, `const POSITION_SCALE := 8` (stored units per px)
  - `enum Event { PICKUP_TAKEN = 1, PLANET_SHATTERED = 2, SHIP_LOST = 3, GOAL_REACHED = 4, ASTEROID_SPAWNED = 5, ASTEROID_REMOVED = 6 }`
  - `var level_sha256: String`, `var truncated := false`
  - `func add_frame(ship: Dictionary, asteroids: Dictionary) -> bool` — `ship` keys `position: Vector2`, `rotation: float`, `firing: bool`, `fuel: float`, `hull: float`; `asteroids` maps an `int` id to `Transform2D`. Returns false (and sets `truncated`) at `MAX_FRAMES`.
  - `func add_event(code: Event, args: Array = []) -> void` — recorded at the current frame. Args: `PICKUP_TAKEN [pickup index]`, `PLANET_SHATTERED [body index]`, `ASTEROID_SPAWNED [id]`, `ASTEROID_REMOVED [id]`, none otherwise.
  - `func frame_count() -> int`, `func ship_at(frame: int) -> Dictionary` (same keys as `add_frame`), `func asteroids_at(frame: int) -> Dictionary` (id → `Transform2D`, only those alive at that frame), `func events() -> Array` (each `[frame, code, args]`), `func seconds() -> float` (`frame_count() * STEP`)
  - `func encode() -> PackedByteArray` and `static func decode(bytes: PackedByteArray) -> Demo` (null for anything malformed, oversized, or of another `FORMAT_VERSION`)

Binary layout before gzip (`StreamPeerBuffer`, little-endian):

| Field | Type |
|---|---|
| magic `ZGXD`, format version | 4 bytes, u8 |
| level SHA-256 | 32 bytes |
| frame count, truncated flag | u32, u8 |
| per frame: ship x, y | s32 each, px × `POSITION_SCALE` |
| ship rotation | s16, milliradians wrapped to ±3142 |
| ship flags (bit 0 firing), fuel, hull | u8, u16 tenths, u16 tenths (unlimited stored as 0) |
| changed asteroid count, then each: id, dx, dy, drotation | u16; u16, s16, s16 (px × `POSITION_SCALE` relative to its previous frame, or absolute from 0 on its spawn frame, clamped), s16 milliradians |
| event count, then each: frame, code, arg | u32, u8, u16 (0 when unused) |

Gzip with `PackedByteArray.compress(FileAccess.COMPRESSION_GZIP)`; decode with `decompress_dynamic(8 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)` and reject any read past the buffer.

- [ ] **Step 1: Write the failing tests** in `tests/test_demo.gd`:

```gdscript
func test_round_trip_keeps_every_object() -> void:
	var demo := Demo.new()
	demo.level_sha256 = "ab".repeat(32)
	for f in 90:
		var rocks := {0: Transform2D(f * 0.01, Vector2(100 + f, -50))}
		if f >= 30:
			rocks[7] = Transform2D(0.0, Vector2(400 - f * 2, 10))  # a shard from frame 30
		if f == 30: demo.add_event(Demo.Event.ASTEROID_SPAWNED, [7])
		demo.add_frame({"position": Vector2(f * 3.5, -f), "rotation": f * 0.05, "firing": f % 2 == 0, "fuel": 100 - f * 0.1, "hull": 100.0}, rocks)
	demo.add_event(Demo.Event.GOAL_REACHED)
	var back := Demo.decode(demo.encode())
	check(back != null and back.frame_count() == 90 and back.level_sha256 == demo.level_sha256, "header")
	check(back.ship_at(60).position.distance_to(Vector2(210, -60)) <= 1.0 / Demo.POSITION_SCALE, "ship at 60: %s" % back.ship_at(60))
	check(not back.asteroids_at(29).has(7) and back.asteroids_at(60)[7].origin.distance_to(Vector2(280, 10)) < 0.2, "shard appears at 30")
	check(back.events().back()[1] == Demo.Event.GOAL_REACHED, "events")

func test_decode_rejects_garbage() -> void:
	check(Demo.decode(PackedByteArray([1, 2, 3])) == null, "garbage must not decode")
	var good := Demo.new()
	good.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 1.0, "hull": 1.0}, {})
	var bytes := good.encode().decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	bytes.resize(bytes.size() - 3)
	check(Demo.decode(bytes.compress(FileAccess.COMPRESSION_GZIP)) == null, "a truncated body must not decode")

func test_recording_stops_at_the_frame_limit() -> void:
	var demo := Demo.new()
	for f in Demo.MAX_FRAMES:
		demo.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 1.0, "hull": 1.0}, {})
	check(not demo.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 1.0, "hull": 1.0}, {}) and demo.truncated, "frame limit")
```

- [ ] **Step 2: Run** `TEST_FILTER=test_demo tests/run.sh`. Expected: FAIL (`Demo` not found).
- [ ] **Step 3: Implement `scripts/demo.gd`.** Keep decoded data in packed arrays per object so `ship_at`/`asteroids_at` are O(1) per object.
- [ ] **Step 4: Run** `TEST_FILTER=test_demo tests/run.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: demo codec`.

### Task 3: Recording runs

**Files:**
- Create: `scenes/demo_recorder.gd`
- Modify: `scenes/level.gd` (add `level_sha256`, `demo`, recording, saving), `scripts/progress.gd` (`build` sets `level_sha256`), `scripts/my_levels.gd` (draft demos)
- Test: `tests/test_recording.gd`

**Interfaces:**
- Consumes: `Demo` (Task 2), `LevelFormat.sha256` (Task 1).
- Produces:
  - `Level.level_sha256: String` (set by `Progress.build` from the level data; empty for tutorials)
  - `Level.demo: Demo` — the current run's demo, complete after `finished` is emitted; null for tutorials
  - `MyLevels.save_demo(id: String, demo: Demo) -> void`, `MyLevels.demo(id: String) -> Demo` — returns the draft's last finishing test-run demo only while `demo.level_sha256 == LevelFormat.sha256(load_level(id))`, else null; `delete` also removes it. File: `user://levels/<id>.demo.gz`.
  - `Progress.best_demo(id: String) -> Demo` — the demo of the best score on an official level; file `user://demos/<id>.demo.gz`, written when `record_win` reports a new best.

`DemoRecorder` is a `Node` added by `Level._ready` when `level_sha256` is set. In `_physics_process` it records a frame on every second tick: ship state, and every `Asteroid` in the level keyed by an id assigned on first sight (initial asteroids in tree order get 0..n−1). Connect: each `Pickup`'s `body_entered` → `PICKUP_TAKEN [index in tree order]`, each `GravityBody.shattered` → `PLANET_SHATTERED [index]`, asteroid `tree_exiting` → `ASTEROID_REMOVED [id]`, new asteroids → `ASTEROID_SPAWNED [id]`. `Level.finish(won)` adds `GOAL_REACHED` or `SHIP_LOST` and records a final frame. A test flight that is won calls `MyLevels.save_demo`; an official new best saves the best demo.

- [ ] **Step 1: Write the failing tests** in `tests/test_recording.gd` (use `fly()` from `test_case.gd` as `test_levels.gd` does):

```gdscript
func test_autopilot_run_is_recorded_frame_by_frame() -> void:
	# Build level_01 via Progress.build, fly its Route; every 30 frames compare
	# lvl.demo.ship_at(lvl.demo.frame_count() - 1).position with lvl.ship.global_position (within 1 px).
	# After the win: last event GOAL_REACHED; level_sha256 == LevelFormat.sha256(LevelFormat.read("res://levels/level_01.json")).

func test_a_lost_run_is_still_a_whole_demo() -> void:
	# A level whose ship is destroyed after 1 s: demo decodes from encode(), ends with SHIP_LOST.

func test_shards_are_recorded_from_their_spawn() -> void:
	# A level with a destructible planet struck by an asteroid (as in test_asteroids.gd):
	# an ASTEROID_SPAWNED event exists and asteroids_at(that frame) contains the shard id.

func test_tutorials_are_not_recorded() -> void:
	# Progress.build("tutorial_1").demo == null after _ready.

func test_draft_demo_is_kept_only_while_the_draft_is_unchanged() -> void:
	# Save a draft, run Progress.build(id, true), finish(true): MyLevels.demo(id) != null.
	# Save the draft again with a changed title: MyLevels.demo(id) == null.
```

- [ ] **Step 2: Run** `TEST_FILTER=test_recording tests/run.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `DemoRecorder`, the `Level` and `Progress` changes, and the `MyLevels` demo helpers.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: exit 0 (existing level and flow tests still pass).
- [ ] **Step 5: Commit** `feat: record every level run as a demo`.

### Task 4: Checking a demo against its level

**Files:**
- Create: `scripts/demo_check.gd`
- Test: `tests/test_demo_check.gd`

**Interfaces:**
- Consumes: `Demo`, `LevelFormat.sha256`, `Progress.points`, `Ship.TUNNEL_LIMIT`, `Ship.RADIUS`, `Goal.RADIUS`.
- Produces `class_name DemoCheck` with `static func check(level: Dictionary, demo: Demo, claim: Dictionary = {}) -> PackedStringArray` — empty when the demo passes. `claim` keys `points: int`, `fuel: float`, `hull: float`, `seconds: float`; when empty, the claim rule is skipped. Error strings name the rule and the frame, e.g. `"frame 212: the ship moved 61 px in one frame"`.

Rules, in the spec's order: hash match; frame 0 within 2 px of the start and the last frame inside the goal with a `GOAL_REACHED` event; per-frame movement ≤ `(Ship.TUNNEL_LIMIT * 1.1) * Demo.STEP`; no frame-to-frame segment crosses a wall segment, and no frame is within `Ship.RADIUS - 2` px of a red wall or of a star or black hole surface; fuel never rises (skipped when fuel is unlimited); with a claim, `|claim.seconds - demo.seconds()| <= Demo.STEP`, claimed fuel and hull equal the last frame within 0.5, and `claim.points == Progress.points(fuel, hull, seconds)` within 2.

- [ ] **Step 1: Write the failing tests:**

```gdscript
func test_every_official_autopilot_demo_passes() -> void:
	# For each id in Progress.levels(): fly the Route as test_levels.gd does; then
	# check(DemoCheck.check(LevelFormat.read(path), lvl.demo, claim_from(lvl)).is_empty(), ...)

func test_tampered_demos_fail() -> void:
	# From one passing level_01 demo, build copies that each break one rule and assert the error names it:
	# wrong level_sha256 → "level"; a frame moved by 200 px → "moved"; a frame placed beyond a wall → "wall";
	# fuel raised by 10 mid-run → "fuel"; claim.points + 100 → "points"; last frame moved out of the goal → "goal".

func test_unlimited_fuel_skips_the_fuel_rule() -> void:
	# A level with fuel "unlimited" flown by the autopilot passes.
```

- [ ] **Step 2: Run** `TEST_FILTER=test_demo_check tests/run.sh`. Expected: FAIL.
- [ ] **Step 3: Implement `scripts/demo_check.gd`.** Use `Geometry2D.segment_intersects_segment` and `Geometry2D.get_closest_point_to_segment`.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: exit 0.
- [ ] **Step 5: Commit** `feat: demo checks`.

### Task 5: Watching a demo

**Files:**
- Create: `scenes/demo_viewer.gd`
- Modify: `scenes/hud.gd` (a **Replay** button on the end panel, signal `replay_requested`), `scenes/level.gd` (opens the viewer; a static `Level.leave_to(tree, level_id, testing)` replaces `_to_menu`'s body so the viewer's Back goes where Menu would), `scenes/my_levels_screen.gd` (**Watch** on drafts whose `MyLevels.demo(id)` is not null)
- Test: `tests/test_demo_viewer.gd`

**Interfaces:**
- Consumes: `Demo`, `LevelFormat.build`, `scenes/level_preview.gd`.
- Produces `class_name DemoViewer extends Node2D` with `static func create(level: Dictionary, demo: Demo, back: Callable) -> DemoViewer`, `func seek(frame: int) -> void`, `var speed := 1.0`, `var paused := false`. Controls: Back, pause/play, 0.5× / 1× / 2×, a timeline `HSlider`. The camera follows the ship; the ship's flame shows when `firing`.

The viewer builds the level with the frozen preview script, keeps the ship and initial asteroids, instantiates shards on demand, hides pickups and planets as their events pass, and interpolates positions between frames during playback.

- [ ] **Step 1: Write the failing tests:**

```gdscript
func test_seek_places_every_object() -> void:
	# Record a level_01 autopilot demo; DemoViewer.create(...); seek(n) for n in [0, middle, last]:
	# viewer ship position == demo.ship_at(n).position (within 0.2 px).

func test_seeking_back_restores_unspawned_shards() -> void:
	# A demo with an ASTEROID_SPAWNED event at frame 30: seek(60) shows the shard; seek(10) hides it.

func test_a_lost_run_plays_to_its_end() -> void:
	# A SHIP_LOST demo: playing at 2× reaches the last frame without errors.
```

- [ ] **Step 2: Run** `TEST_FILTER=test_demo_viewer tests/run.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the viewer, the Replay button and the My levels Watch button.
- [ ] **Step 4: Run** `tests/run.sh`. Expected: exit 0.
- [ ] **Step 5: Render check:** a throwaway script that wins level_08 (Rocks) by autopilot, opens Replay, seeks to the middle and saves a screenshot; confirm ship, asteroids and controls are visible.
- [ ] **Step 6: Commit** `feat: watch a run's demo`.

### Task 6: Documentation and release

**Files:**
- Modify: `README.md` (Level files: plain JSON and drafts as `.json.gz`; a Demos paragraph), `docs/superpowers/specs/2026-10-16-level-format-design.md` (file extension), `docs/superpowers/specs/2026-10-16-community-design.md` (status: sub-project 1 implemented)

- [ ] **Step 1:** Update the three documents.
- [ ] **Step 2: Run** `tests/run.sh`. Expected: exit 0.
- [ ] **Step 3: Commit** `docs: demos and JSON levels`, push `master`, and wait for CI: `gh run watch <id> --exit-status`. Expected: a new `prototype-rN` release.
