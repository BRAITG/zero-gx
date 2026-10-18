extends "res://tests/test_case.gd"

const FLIGHT_LIMIT := 4800  # frames: 80 s


## Flies `lvl` along its hidden Route and returns it once won; null when the run is not won.
func fly_level(lvl: Level) -> Level:
	world.add_child(lvl)
	var outcome := {"won": null}
	lvl.finished.connect(func(won: bool): outcome.won = won)
	var route := lvl.get_node("Route") as Line2D
	var waypoints: Array[Vector2] = []
	for point in route.points:
		waypoints.append(route.position + point)
	waypoints.append(lvl.goal.position)
	var coast: PackedInt32Array = route.get_meta("coast", PackedInt32Array())
	var cruise: float = route.get_meta("cruise", CRUISE)
	var pilot := {"next": 0}
	for frame in FLIGHT_LIMIT:
		await frames(1)
		if outcome.won != null:
			break
		fly(lvl.ship, waypoints, pilot, cruise, coast)
	return lvl if outcome.won == true else null


func claim_from(lvl: Level) -> Dictionary:
	return {
		"points": lvl._score().points,
		"fuel": 0.0 if lvl.ship.fuel_unlimited else lvl.ship.fuel,
		"hull": 0.0 if lvl.ship.hull_unlimited else lvl.ship.health,
		"seconds": lvl.ship.flight_time,
	}


## A copy of `demo` with `edit.call(frame, ship_dict)` applied to each frame's ship; the asteroids are not part of any rule.
func rebuilt(demo: Demo, edit: Callable) -> Demo:
	var copy := Demo.new()
	copy.level_sha256 = demo.level_sha256
	for f in demo.frame_count():
		var ship := demo.ship_at(f)
		edit.call(f, ship)
		copy.add_frame(ship, {})
	for event in demo.events():
		copy.add_event(event[1], event[2])
	return copy


func has_error(errors: PackedStringArray, word: String) -> bool:
	for error in errors:
		if word in error:
			return true
	return false


func test_every_official_autopilot_demo_passes() -> void:
	for id in Progress.levels():
		var lvl := await fly_level(Progress.build(id))
		check(lvl != null, "%s: autopilot did not win" % id)
		if lvl:
			var errors := DemoCheck.check(LevelFormat.read(Progress.LEVELS_DIR + id + LevelFormat.EXTENSION), lvl.demo, claim_from(lvl))
			check(errors.is_empty(), "%s: %s" % [id, errors])
			lvl.free()


func test_tampered_demos_fail() -> void:
	var lvl := await fly_level(Progress.build("level_01"))
	check(lvl != null, "level_01: autopilot did not win")
	if lvl == null:
		return
	var level := lvl.level_data
	var demo := lvl.demo
	var claim := claim_from(lvl)
	var mid := demo.frame_count() / 2
	check(DemoCheck.check(level, demo, claim).is_empty(), "the untouched demo must pass")

	var forged := rebuilt(demo, func(f: int, ship: Dictionary): pass)
	forged.level_sha256 = "f".repeat(64)
	var errors := DemoCheck.check(level, forged)
	check(errors.size() == 1 and has_error(errors, "different level"), "a wrong level hash must fail on the hash alone: %s" % [errors])

	var jumped := rebuilt(demo, func(f: int, ship: Dictionary): ship.position += Vector2(0, 200) if f == mid else Vector2.ZERO)
	check(has_error(DemoCheck.check(level, jumped), "moved 2"), "a 200 px jump must fail")

	# Frame `mid` is the reflection of the one before it across the nearest point of the first wall,
	# so the step between them crosses that wall.
	var wall: Array = level.walls[0].points
	var before: Vector2 = demo.ship_at(mid - 1).position
	var edge := Geometry2D.get_closest_point_to_segment(before, Vector2(wall[0][0], wall[0][1]), Vector2(wall[1][0], wall[1][1]))
	var beyond := rebuilt(demo, func(f: int, ship: Dictionary): ship.position = 2.0 * edge - before if f == mid else ship.position)
	check(has_error(DemoCheck.check(level, beyond), "crossed a wall"), "a frame beyond a wall must fail")

	var refueled := rebuilt(demo, func(f: int, ship: Dictionary): ship.fuel += 10.0 if f == mid else 0.0)
	check(has_error(DemoCheck.check(level, refueled), "fuel rose"), "fuel that rises must fail")

	var rich := claim.duplicate()
	rich.points += 100
	check(has_error(DemoCheck.check(level, demo, rich), "points"), "a claim 100 points too high must fail")

	var last := demo.frame_count() - 1
	var goal := Vector2(level.goal.position[0], level.goal.position[1])
	var away := rebuilt(demo, func(f: int, ship: Dictionary): ship.position = goal + (ship.position - goal).normalized() * Goal.RADIUS * 3.0 if f == last else ship.position)
	check(has_error(DemoCheck.check(level, away), "not inside the goal"), "a last frame outside the goal must fail")
	lvl.free()


func test_unlimited_fuel_skips_the_fuel_rule() -> void:
	var data := LevelFormat.read(Progress.LEVELS_DIR + "level_01.json")
	data.ship.fuel = LevelFormat.UNLIMITED
	var id := MyLevels.new_id()
	MyLevels.save(id, data)
	var lvl := await fly_level(Progress.build(id))
	check(lvl != null, "autopilot did not win the unlimited-fuel level")
	if lvl:
		var errors := DemoCheck.check(lvl.level_data, lvl.demo, claim_from(lvl))
		check(errors.is_empty(), "unlimited fuel: %s" % [errors])
		lvl.free()
	MyLevels.delete(id)


## A level with the ship starting at `positions[0]` and the goal at the last one, and a demo that
## visits `positions` frame by frame at full fuel. `codes` are recorded as events after the last
## frame, or before it when `early`.
func flown(level_extra: Dictionary, positions: Array[Vector2], codes := [Demo.Event.GOAL_REACHED], early := false) -> Array:
	var level := {"ship": {"position": [positions[0].x, positions[0].y], "fuel": 100, "hull": 100}, "goal": {"position": [positions[-1].x, positions[-1].y]}}
	level.merge(level_extra)
	var demo := Demo.new()
	demo.level_sha256 = LevelFormat.sha256(level)
	for i in positions.size():
		if early and i == positions.size() - 1:
			for code in codes:
				demo.add_event(code)
		demo.add_frame({"position": positions[i], "rotation": 0.0, "firing": false, "fuel": 100.0, "hull": 100.0}, {})
	if not early:
		for code in codes:
			demo.add_event(code)
	return [level, demo]


## `count` frames 30 px apart along y = `y`, from x = 0.
func along(y: float, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in count:
		out.append(Vector2(30.0 * i, y))
	return out


func test_the_demo_must_end_with_the_goal_event() -> void:
	var path := along(0.0, 8)
	var ok := flown({}, path)
	check(DemoCheck.check(ok[0], ok[1]).is_empty(), "a plain flight to the goal must pass: %s" % [DemoCheck.check(ok[0], ok[1])])
	var planted := flown({}, path, [Demo.Event.GOAL_REACHED, Demo.Event.SHIP_LOST])
	check(has_error(DemoCheck.check(planted[0], planted[1]), "the goal event"), "a goal event followed by SHIP_LOST must fail")
	var lost := flown({}, path, [Demo.Event.SHIP_LOST])
	check(has_error(DemoCheck.check(lost[0], lost[1]), "the goal event"), "a lost run must fail")
	var early := flown({}, path, [Demo.Event.GOAL_REACHED], true)
	check(has_error(DemoCheck.check(early[0], early[1]), "the goal event"), "a goal event before the last frame must fail")


func test_a_frame_beside_a_red_wall_fails() -> void:
	var wall := {"walls": [{"kind": "red", "points": [[-100, 100], [400, 100]]}]}
	var near := flown(wall, along(80.0, 8))  # 20 px from the wall's line: inside slab and ship
	check(has_error(DemoCheck.check(near[0], near[1]), "red wall"), "20 px from a red wall must fail")
	var clear := flown(wall, along(60.0, 8))  # 40 px: clear of the slab (8) and the ship (16)
	check(DemoCheck.check(clear[0], clear[1]).is_empty(), "40 px from a red wall must pass: %s" % [DemoCheck.check(clear[0], clear[1])])


## One step across a black hole with both frames outside it. The speed rule also fires on such a
## step: at the speed limit a step is shorter than any hazard is wide, so that rule is the first
## defence and this one the second.
func test_a_step_through_a_black_hole_fails() -> void:
	var hole := {"bodies": [{"kind": "black_hole", "position": [150, 0], "radius": 40}]}
	var through := flown(hole, [Vector2(80, 0), Vector2(220, 0)])  # 70 px from the centre; contact is under 54
	check(has_error(DemoCheck.check(through[0], through[1]), "hit a black hole"), "a step through a black hole must fail")
	var past := flown(hole, [Vector2(100, 100), Vector2(130, 100), Vector2(160, 100)])
	check(not has_error(DemoCheck.check(past[0], past[1]), "hit a"), "a path 100 px past the hole must not count as a hit")
