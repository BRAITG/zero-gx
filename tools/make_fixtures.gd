extends SceneTree
## Regenerates fixtures/: the levels, demos and expected check results the community server's tests
## share with the game's DemoCheck and LevelFormat. Run from the project root:
##   godot --headless --path . -s tools/make_fixtures.gd

const DIR := "res://fixtures/"
const OFFICIAL := ["level_01", "level_05", "level_10"]
const CLOCK_SHIFT := 30  # frames

# Untyped and loaded after the first frame: a -s script compiles before the autoloads exist and
# cannot use the global class names.
var _demo_class
var _format
var _check
var _levels := {}  # file -> level data
var _expected := {"levels": {}, "demos": {}}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_demo_class = load("res://scripts/demo.gd")
	_format = load("res://scripts/level_format.gd")
	_check = load("res://scripts/demo_check.gd")
	root.get_node("Tuning").tours = false
	var progress = root.get_node("Progress")
	progress.path = "user://fixtures_progress.cfg"  # the flights must not touch the player's progress or demos
	progress.demos_dir = "user://fixtures_demos/"
	progress.reset()
	for sub in ["levels", "demos"]:
		DirAccess.make_dir_recursive_absolute(DIR + sub)
		for file in DirAccess.get_files_at(DIR + sub):
			DirAccess.remove_absolute(DIR + sub + "/" + file)

	var pilot = load("res://tests/test_demo_check.gd").new()  # flies a level along its hidden route
	pilot.tree = self
	pilot.world = Node2D.new()
	root.add_child(pilot.world)
	var flights := {}
	for id in OFFICIAL:
		var lvl = await pilot.fly_level(progress.build(id), 60 if id == "level_10" else 0)
		if lvl == null:
			push_error("make_fixtures: the autopilot did not win %s" % id)
			quit(1)
			return
		var stem: String = id + (".idle" if id == "level_10" else "")
		flights[id] = lvl.demo
		_add_level(id + ".json", lvl.level_data, [])
		_add_demo(stem + ".demo.gz", lvl.demo, id + ".json", [], true)
		lvl.free()

	var data: Dictionary = _levels["level_01.json"]
	var demo = flights.level_01
	var mid: int = demo.frame_count() / 2
	_add_demo("level_01.wrong_hash.demo.gz", _rebuilt(demo, func(f, ship): pass, 0, "f".repeat(64)), "level_01.json", ["different level"])
	_add_demo("level_01.teleport.demo.gz", _rebuilt(demo, func(f, ship): ship.position += Vector2(0, 200) if f == mid else Vector2.ZERO), "level_01.json", ["px in one frame"])
	var crossed := _with_wall(data, "blue", _point_span(demo, mid))
	_add_level("level_01.crossed.json", crossed, [])
	_add_demo("level_01.wall_crossing.demo.gz", _rebuilt(demo, func(f, ship): pass, 0, _format.sha256(crossed)), "level_01.crossed.json", ["crossed a wall"])
	_add_demo("level_01.clock_moved.demo.gz", _rebuilt(demo, func(f, ship): pass, CLOCK_SHIFT), "level_01.json", ["clock"])
	var truncated = _rebuilt(demo, func(f, ship): pass)
	truncated.truncated = true
	_add_demo("level_01.truncated.demo.gz", truncated, "level_01.json", ["truncated"])

	# A short red wall 12 px beside the ship's path: the demo grazes it.
	var path_point: Vector2 = demo.ship_at(mid).position
	var along: Vector2 = (demo.ship_at(mid + 1).position - demo.ship_at(mid - 1).position).normalized()
	var side := path_point + along.rotated(PI / 2.0) * 12.0
	var red := _with_wall(data, "red", [_point(side - along * 2.0), _point(side + along * 2.0)])
	_add_level("level_01.red.json", red, [])
	_add_demo("level_01.red_graze.demo.gz", _rebuilt(demo, func(f, ship): pass, 0, _format.sha256(red)), "level_01.red.json", ["red wall"])

	_add_level("invalid.wall_kind.json", _variant(data, func(d): d.walls[0].kind = "green"), ["unknown kind"])
	_add_level("invalid.planet_radius.json", _variant(data, func(d): d.bodies = [{"kind": "planet", "position": [1000, 500], "radius": 400, "strength": 300}]), ["radius must be"])
	_add_level("invalid.black_hole_weak.json", _variant(data, func(d): d.bodies = [
		{"kind": "star", "position": [2000, -2000], "radius": 300, "strength": 60000},
		{"kind": "black_hole", "position": [-1500, 1500], "radius": 64, "strength": 8000},
	]), ["black hole must pull harder"])
	_add_level("invalid.oversized.json", _oversized(data), ["larger than"], true)

	_expected.official_hashes = {}
	for id in progress.levels():
		_expected.official_hashes[id] = _format.sha256(_format.read(progress.LEVELS_DIR + id + _format.EXTENSION))
	FileAccess.open(DIR + "expected.json", FileAccess.WRITE).store_string(JSON.stringify(_expected, "  ", true) + "\n")
	quit(0)


func _add_level(file: String, data: Dictionary, errors: Array, compact := false) -> void:
	_levels[file] = data
	if compact:  # the 64 KB limit counts compact JSON, so the oversized fixture is stored as such
		FileAccess.open(DIR + "levels/" + file, FileAccess.WRITE).store_string(JSON.stringify(data))
	else:
		_format.write(DIR + "levels/" + file, data)
	_expected.levels[file] = errors


## `points` is the server-side score of a demo that passes, null for a tampered one.
func _add_demo(file: String, demo, level_file: String, errors: Array, scored := false) -> void:
	demo.save(DIR + "demos/" + file)
	var found = _demo_class.load_file(DIR + "demos/" + file)
	var level: Dictionary = _levels[level_file]
	var actual: PackedStringArray = _check.check(level, found)
	# The fixture must say what the game's rules say; a mismatch means the tampering is wrong.
	for word in errors:
		assert(Array(actual).any(func(e: String) -> bool: return word in e), "%s: no error contains \"%s\": %s" % [file, word, actual])
	assert(errors.is_empty() == actual.is_empty() and actual.size() <= errors.size(), "%s: unexpected errors %s" % [file, actual])
	_expected.demos[file] = {"level": level_file, "errors": errors, "points": _check.score(level, found).points if scored else null}


## A copy of `demo` with `edit.call(frame, ship)` applied to each frame's ship and the clock event
## moved `clock_shift` frames later; `sha` replaces the level hash when given.
func _rebuilt(demo, edit: Callable, clock_shift := 0, sha := ""):
	var copy = _demo_class.new()
	copy.level_sha256 = sha if sha != "" else demo.level_sha256
	var events: Array = demo.events().map(func(e: Array) -> Array: return [e[0] + (clock_shift if e[1] == _demo_class.Event.CLOCK_STARTED else 0), e[1], e[2]])
	events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var next := 0
	for f in demo.frame_count():
		while next < events.size() and events[next][0] <= f:  # an event belongs before the frame it was recorded at
			copy.add_event(events[next][1], events[next][2])
			next += 1
		var ship: Dictionary = demo.ship_at(f)
		edit.call(f, ship)
		copy.add_frame(ship, demo.asteroids_at(f))
	for event in events.slice(next):
		copy.add_event(event[1], event[2])
	return copy


func _variant(data: Dictionary, edit: Callable) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	edit.call(copy)
	return copy


## `data` with enough long walls to pass the byte limit.
func _oversized(data: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var big: Dictionary = data.duplicate(true)
	while JSON.stringify(big).to_utf8_buffer().size() <= _format.MAX_BYTES:
		var points := []
		for i in _format.MAX_WALL_POINTS:
			points.append([rng.randi_range(-9000, 9000), rng.randi_range(-9000, 9000)])
		big.walls.append({"kind": "blue", "points": points})
	return big


func _point(p: Vector2) -> Array:
	return [roundi(p.x), roundi(p.y)]


## A wall of `kind` through `points`, added to a copy of `data`.
func _with_wall(data: Dictionary, kind: String, points: Array) -> Dictionary:
	return _variant(data, func(d): d.walls.append({"kind": kind, "points": points}))


## A wall across the demo's step into frame `f`.
func _point_span(demo, f: int) -> Array:
	var from: Vector2 = demo.ship_at(f - 1).position
	var to: Vector2 = demo.ship_at(f).position
	var across := (to - from).normalized().rotated(PI / 2.0) * 60.0
	return [_point((from + to) / 2.0 - across), _point((from + to) / 2.0 + across)]
