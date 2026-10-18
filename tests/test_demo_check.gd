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

	var other := LevelFormat.read(Progress.LEVELS_DIR + "level_02.json")
	check(has_error(DemoCheck.check(other, demo), "level"), "another level's data must fail on the level hash")

	var jumped := rebuilt(demo, func(f: int, ship: Dictionary): ship.position += Vector2(0, 200) if f == mid else Vector2.ZERO)
	check(has_error(DemoCheck.check(level, jumped), "moved"), "a 200 px jump must fail")

	# Frame `mid` is the reflection of the one before it across the nearest point of the first wall,
	# so the step between them crosses that wall.
	var wall: Array = level.walls[0].points
	var before: Vector2 = demo.ship_at(mid - 1).position
	var edge := Geometry2D.get_closest_point_to_segment(before, Vector2(wall[0][0], wall[0][1]), Vector2(wall[1][0], wall[1][1]))
	var beyond := rebuilt(demo, func(f: int, ship: Dictionary): ship.position = 2.0 * edge - before if f == mid else ship.position)
	check(has_error(DemoCheck.check(level, beyond), "wall"), "a frame beyond a wall must fail")

	var refueled := rebuilt(demo, func(f: int, ship: Dictionary): ship.fuel += 10.0 if f == mid else 0.0)
	check(has_error(DemoCheck.check(level, refueled), "fuel"), "fuel that rises must fail")

	var rich := claim.duplicate()
	rich.points += 100
	check(has_error(DemoCheck.check(level, demo, rich), "points"), "a claim 100 points too high must fail")

	var last := demo.frame_count() - 1
	var goal := Vector2(level.goal.position[0], level.goal.position[1])
	var away := rebuilt(demo, func(f: int, ship: Dictionary): ship.position = goal + (ship.position - goal).normalized() * Goal.RADIUS * 3.0 if f == last else ship.position)
	check(has_error(DemoCheck.check(level, away), "goal"), "a last frame outside the goal must fail")
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
