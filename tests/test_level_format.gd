extends "res://tests/test_case.gd"

const WALL := {"kind": "orange", "points": [[300, -500], [300, 500]]}


func minimal() -> Dictionary:
	return {"format": "zero-gx-level", "version": 1, "title": "Test",
		"ship": {"position": [0, 0], "fuel": 100, "hull": 100}, "goal": {"position": [3000, 0]}}


## `data` with `change` applied at a dotted path, e.g. "ship.fuel".
func with(path: String, value: Variant) -> Dictionary:
	var data := minimal().duplicate(true)
	var keys := path.split(".")
	var node: Variant = data
	for k in keys.slice(0, -1):
		node = node[int(k)] if node is Array else node[k]
	if node is Array:
		node[int(keys[-1])] = value
	else:
		node[keys[-1]] = value
	return data


func rejects(data: Dictionary, why: String) -> void:
	check(not LevelFormat.validate(data).is_empty(), "accepted a level with %s" % why)


func test_minimal_level_is_valid() -> void:
	var errors := LevelFormat.validate(minimal())
	check(errors.is_empty(), "minimal level rejected: %s" % errors)


func test_validation_rejects_each_rule() -> void:
	rejects(with("format", "other"), "a wrong format name")
	rejects(with("version", 2), "an unknown version")
	rejects(with("title", ""), "an empty title")
	rejects(with("title", "x".repeat(41)), "a long title")
	rejects(with("hint", "x".repeat(201)), "a long hint")
	rejects(with("ship.fuel", 0), "zero fuel")
	rejects(with("ship.hull", 5000), "too much hull")
	rejects(with("ship.fuel", "lots"), "a word for fuel")
	rejects(with("ship.position", [60000, 0]), "a ship outside the map")
	rejects(with("ship.position", [NAN, 0]), "a NaN coordinate")
	rejects(with("goal.position", [10, 10]), "a ship starting in the goal")
	rejects(with("walls", [{"kind": "green", "points": [[0, 0], [1, 1]]}]), "an unknown wall kind")
	rejects(with("walls", [{"kind": "blue", "points": [[0, 0]]}]), "a one-point wall")
	rejects(with("walls", [{"kind": "blue", "points": [[-100, 0], [100, 0]]}]), "a ship starting inside a wall")
	var many := []
	for i in LevelFormat.MAX_WALLS + 1:
		many.append(WALL)
	rejects(with("walls", many), "too many walls")
	rejects(with("bodies", [{"kind": "planet", "position": [2000, 0], "radius": 5000}]), "a huge planet")
	rejects(with("bodies", [{"kind": "planet", "position": [40, 0]}]), "a ship starting inside a planet")
	rejects(with("asteroids", [{"position": [800, 0], "orbit": {"body": 3}}]), "an orbit around a missing body")
	rejects(with("pickups", [{"kind": "shield", "position": [800, 0]}]), "an unknown pickup")
	var big := minimal()
	big.hint = ""
	big.tour = []
	for i in 40:
		big.tour.append({"position": [i, i], "text": "x".repeat(200)})
	rejects(big, "too many tour stops")


func test_unlimited_fuel_never_burns_or_strands() -> void:
	var lvl := LevelFormat.build(with("ship.fuel", "unlimited"))
	world.add_child(lvl)
	var lost := []
	lvl.finished.connect(func(won: bool): lost.append(won))
	lvl.ship.thrusting = true
	lvl.ship.aim_point = Vector2(0, -100000)
	await frames(600)
	check(lvl.ship.fuel == Ship.MAX_FUEL, "unlimited fuel burned down to %f" % lvl.ship.fuel)
	check(lost.is_empty() and lvl.ship.empty_seconds_left() < 0.0, "unlimited fuel must not time out")


func test_unlimited_hull_ignores_damage_but_not_red() -> void:
	var data := with("ship.hull", "unlimited")
	data.ship.velocity = [700, 0]
	data.walls = [WALL]
	var lvl := LevelFormat.build(data)
	world.add_child(lvl)
	await frames(60)
	check(lvl.ship.health == Ship.MAX_HEALTH and lvl.ship.visible, "a hard orange hit hurt an unlimited hull")
	lvl.free()
	data.walls = [{"kind": "red", "points": WALL.points}]
	lvl = LevelFormat.build(data)
	world.add_child(lvl)
	await frames(60)
	check(lvl.ship.health == 0.0, "a red wall must still destroy an unlimited hull")


func test_unlimited_resources_score_nothing() -> void:
	var data := with("ship.fuel", "unlimited")
	data.ship.hull = "unlimited"
	data.ship.velocity = [400, 0]
	var lvl := LevelFormat.build(data)
	lvl.level_id = "level_01"
	world.add_child(lvl)
	await frames(500)
	var text: String = lvl.hud.result_text()
	check(text.contains("+0\n+0"), "unlimited fuel and hull must score 0 each: %s" % text)


func test_round_trip_through_a_file() -> void:
	var data := minimal()
	data.walls = [WALL]
	data.bodies = [{"kind": "black_hole", "position": [1500, 900]}]
	data.asteroids = [{"position": [1500, 700], "orbit": {"body": 0, "radius": 200, "speed": 1, "angle": 0}}]
	data.pickups = [{"kind": "boost", "position": [600, 200]}]
	var path := "user://test_level.json.gz"
	check(LevelFormat.write(path, data) == OK, "could not write the level file")
	var back := LevelFormat.read(path)
	var built := LevelFormat.build(back)
	var saved: Variant = JSON.parse_string(JSON.stringify(LevelFormat.serialize(built)))
	built.free()
	check(JSON.stringify(saved) == JSON.stringify(back), "a level changed on its way through a file and a scene")
