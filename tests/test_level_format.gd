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


func test_draft_validation_skips_the_rules_but_keeps_the_shapes() -> void:
	var many := []
	for i in LevelFormat.MAX_WALLS + 1:
		many.append(WALL)
	var unfinished := {
		"an empty title": with("title", ""), "no fuel": with("ship.fuel", 0), "a ship outside the map": with("ship.position", [60000, 0]),
		"a ship in the goal": with("goal.position", [10, 10]), "a one-point wall": with("walls", [{"kind": "blue", "points": [[0, 0]]}]),
		"a huge planet over the ship": with("bodies", [{"kind": "planet", "position": [40, 0], "radius": 5000}]), "too many walls": with("walls", many),
		"a long hint": with("hint", "x".repeat(201)),
	}
	for why: String in unfinished:
		check(LevelFormat.validate(unfinished[why], true).is_empty(), "a draft with %s must pass: %s" % [why, LevelFormat.validate(unfinished[why], true)])
		check(not LevelFormat.validate(unfinished[why]).is_empty(), "a full validation must still reject %s" % why)
	var broken := {
		"only a format and version": {"format": "zero-gx-level", "version": 1}, "a number for the format": with("format", 5), "a string for the version": with("version", "1"),
		"a number title": with("title", 5), "no title": with("title", null), "a number hint": with("hint", 7), "a lone ship position number": with("ship.position", [5]),
		"a text coordinate": with("ship.position", ["a", 0]), "a goal that is not an object": with("goal", 5), "an unknown wall kind": with("walls", [{"kind": "green", "points": [[0, 0], [1, 1]]}]),
		"wall points that are not a list": with("walls", [{"kind": "blue", "points": 3}]), "walls that are not a list": with("walls", "x"), "an unknown body kind": with("bodies", [{"kind": "moon", "position": [0, 0]}]),
		"an orbit around a missing body": with("asteroids", [{"position": [800, 0], "orbit": {"body": 3}}]), "a tour stop that is not an object": with("tour", [4]),
		"a route without points": with("route", {}), "a bad wall among too many": with("walls", many + [{"kind": "green", "points": [[0, 0], [1, 1]]}]),
	}
	for why: String in broken:
		check(not LevelFormat.validate(broken[why], true).is_empty(), "a draft with %s must be rejected" % why)


func test_a_gzip_file_reads_whatever_its_name() -> void:
	var path := "user://disguised.json"
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	file.store_string(JSON.stringify(minimal()))
	file.close()
	check(LevelFormat.read(path).get("title") == "Test", "a gzip file named .json must read: %s" % LevelFormat.read(path))
	LevelFormat.write("user://plain.json", minimal())
	check(LevelFormat.read("user://plain.json").get("title") == "Test", "a plain file must still read")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://plain.json")


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


func test_par_must_be_a_whole_number_of_at_least_100() -> void:
	var sentence := "par must be a whole number of at least 100 points"
	check(LevelFormat.validate(with("par", 1200)).is_empty(), "a par of 1200 must pass: %s" % LevelFormat.validate(with("par", 1200)))
	check(LevelFormat.validate(with("par", 1200.0)).is_empty(), "a whole float par must pass")
	for bad: Variant in [99, 12.5, "x"]:
		check(LevelFormat.validate(with("par", bad)).has(sentence), "par %s must be refused: %s" % [bad, LevelFormat.validate(with("par", bad))])
	check(LevelFormat.validate(with("par", 99), true).is_empty(), "a draft may have a par below 100")
	check(LevelFormat.validate(with("par", 12.5), true).has(sentence), "a draft must still have a whole par")


func test_par_survives_a_file_and_a_scene() -> void:
	var path := "user://test_level_par.json.gz"
	check(LevelFormat.write(path, with("par", 1200)) == OK, "could not write the level file")
	var back := LevelFormat.read(path)
	var built := LevelFormat.build(back)
	check(built.par == 1200, "par %d after build, expected 1200" % built.par)
	var saved: Variant = JSON.parse_string(JSON.stringify(LevelFormat.serialize(built)))
	built.free()
	check(JSON.stringify(saved) == JSON.stringify(back), "par changed on its way through a file and a scene")


func test_body_limits_keep_each_kind_in_its_role() -> void:
	rejects(with("bodies", [{"kind": "planet", "position": [2000, 0], "radius": 300}]), "a planet as big as a star")
	rejects(with("bodies", [{"kind": "planet", "position": [2000, 0], "radius": 200, "strength": 5000}]), "a planet pulling like a star from afar")
	rejects(with("bodies", [{"kind": "star", "position": [9000, 0], "radius": 300, "strength": 10000}]), "a star as small as a planet")
	rejects(with("bodies", [{"kind": "star", "position": [9000, 0], "radius": 1000, "strength": 100}]), "a star too light")
	var limits: Dictionary = LevelFormat.KIND_LIMITS
	var strongest_star: float = limits.star.total_pull.y / pow(limits.star.radius.x / 1000.0, 2)
	var weakest_hole: float = limits.black_hole.total_pull.x / pow(limits.black_hole.radius.y / 1000.0, 2)
	check(weakest_hole > strongest_star, "every black hole out-pulls every star at its surface: %s vs %s" % [weakest_hole, strongest_star])
	check(limits.black_hole.total_pull.y > limits.star.total_pull.x, "black holes and stars overlap in mass")
	rejects(with("bodies", [{"kind": "black_hole", "position": [2000, 900], "strength": 4000}]), "a black hole lighter than its kind allows")
	var fine := with("bodies", [{"kind": "planet", "position": [2000, 600]}, {"kind": "star", "position": [9000, 0]}, {"kind": "black_hole", "position": [2000, -900]}])
	check(LevelFormat.validate(fine).is_empty(), "presets must pass: %s" % LevelFormat.validate(fine))


func test_json_layout_is_stable() -> void:
	var text := LevelFormat.to_json({"b": 2.0, "a": [1.5, 3.0], "c": {"z": true, "y": "x"}})
	check(text == '{\n  "a": [\n    1.5,\n    3\n  ],\n  "b": 2,\n  "c": {\n    "y": "x",\n    "z": true\n  }\n}\n', "layout: %s" % text)


func test_official_files_round_trip_byte_for_byte() -> void:
	for dir in [Progress.LEVELS_DIR, Progress.TUTORIALS_DIR]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".json"):
				var path: String = dir + file
				check(FileAccess.get_file_as_string(path) == LevelFormat.to_json(LevelFormat.read(path)), "%s is not in the stable layout" % path)


func test_a_small_change_to_an_orbit_angle_changes_the_hash() -> void:
	var data := LevelDoc.blank()
	data.bodies = [{"kind": "planet", "position": [0, 0]}]
	data.asteroids = [{"position": [100, 0], "orbit": {"body": 0, "radius": 100, "speed": 1, "angle": 1.2345}}]
	var other := data.duplicate(true)
	other.asteroids[0].orbit.angle = 1.2355
	check(LevelFormat.sha256(data) != LevelFormat.sha256(other), "angles 0.001 apart must hash differently")


func test_hash_names_the_content() -> void:
	var data := LevelDoc.blank()
	var hash := LevelFormat.sha256(data)
	check(hash.length() == 64 and hash == LevelFormat.to_json(data).sha256_text(), "hash: %s" % hash)
	data.title = "Other"
	check(LevelFormat.sha256(data) != hash, "a change must change the hash")


func test_sketch_keeps_shape_and_is_stable() -> void:
	var data := LevelFormat.read(Progress.LEVELS_DIR + "level_08.json")
	var sketch := LevelFormat.sketch(data)
	check(sketch.walls.size() == data.walls.size() and sketch.bodies.size() == data.get("bodies", []).size(), "every wall and body survives: %s" % [sketch])
	check(sketch.walls[0].kind == data.walls[0].kind, "wall kinds survive")
	var bounds: Array = sketch.bounds
	for wall in data.walls:
		for p in wall.points:
			check(p[0] >= bounds[0] and p[0] <= bounds[0] + bounds[2] and p[1] >= bounds[1] and p[1] <= bounds[1] + bounds[3], "bounds enclose %s" % [p])
	var text := LevelFormat.sketch_json(sketch)
	check(text == LevelFormat.sketch_json(LevelFormat.sketch(data)), "same level, same bytes")
	check(text.length() < 2048 and not text.contains("\n") and not text.contains(" "), "one compact line under 2 KB: %d" % text.length())
	check(text.find("\"asteroids\"") < text.find("\"bodies\""), "keys sorted")


func test_sketch_json_sorts_nested_keys() -> void:
	check(LevelFormat.sketch_json({"walls": [{"points": [], "kind": "blue", "closed": true}]}) == '{"walls":[{"closed":true,"kind":"blue","points":[]}]}', "nested keys must be sorted on one line")


func full_level() -> Dictionary:
	var data := minimal()
	data.walls = []
	for w in LevelFormat.MAX_WALLS:
		var points := []
		for i in LevelFormat.MAX_WALL_POINTS:
			points.append([w * 50 + i * 7 + (i % 3) * 20, (i * 13) % 300])
		data.walls.append({"kind": "blue", "points": points})
	data.asteroids = []
	for i in LevelFormat.MAX_ASTEROIDS:
		data.asteroids.append({"position": [i * 31, (i * 17) % 500]})
	return data


func test_sketch_of_a_maximal_level_fits() -> void:
	var sketch := LevelFormat.sketch(full_level())
	check(LevelFormat.sketch_json(sketch).length() < 2048, "maximal level must fit")
	check(not sketch.walls.is_empty(), "at least one wall survives the cap: %d walls" % sketch.walls.size())


func test_sketch_of_a_level_full_of_pickups_and_bodies_fits() -> void:
	var data := full_level()
	data.pickups = []
	for i in LevelFormat.MAX_PICKUPS:
		data.pickups.append({"kind": "boost", "position": [(i * 2917) % 100000 - 50000, (i * 4001) % 100000 - 50000]})
	data.bodies = []
	for i in LevelFormat.MAX_BODIES:
		data.bodies.append({"kind": "star", "position": [(i * 3517) % 100000 - 50000, (i * 2243) % 100000 - 50000], "radius": 3000})
	var sketch := LevelFormat.sketch(data)
	check(LevelFormat.sketch_json(sketch).length() < 2048, "a level full of pickups and bodies must fit: %d" % LevelFormat.sketch_json(sketch).length())
	check(sketch.has("bounds") and sketch.has("ship") and sketch.has("goal"), "bounds, ship and goal always stay")


func test_sketch_drops_a_straight_run_and_keeps_corners() -> void:
	var data := minimal()
	data.walls = [{"kind": "blue", "points": [[0, 500], [100, 500], [200, 500], [300, 500], [300, 900]]}]
	var kept: Array = LevelFormat.sketch(data).walls[0].points
	check(kept == [[0, 500], [300, 500], [300, 900]], "a straight run collapses to its ends and the corner stays: %s" % [kept])


func test_a_cut_takes_asteroids_before_walls() -> void:
	var data := minimal()
	data.walls = [{"kind": "blue", "points": [[0, 500], [300, 900]]}, {"kind": "red", "points": [[0, -500], [300, -900]]}]
	data.asteroids = []
	for i in LevelFormat.MAX_ASTEROIDS:
		data.asteroids.append({"position": [i * 600 - 50000, (i * 7907) % 90000 - 45000]})
	var sketch := LevelFormat.sketch(data)
	check(sketch.asteroids.size() < LevelFormat.MAX_ASTEROIDS, "the asteroids alone overflow, so some are cut: %d left" % sketch.asteroids.size())
	check(sketch.walls == data.walls, "every wall survives while asteroids are cut: %s" % [sketch.walls])


func test_sketch_keeps_closed_only_on_a_closed_wall() -> void:
	var data := minimal()
	data.walls = [{"kind": "blue", "points": [[0, 500], [300, 500], [300, 900]], "closed": true}, {"kind": "red", "points": [[0, -500], [300, -500]]}]
	var walls: Array = LevelFormat.sketch(data).walls
	check(walls[0].get("closed") == true, "a closed wall stays closed: %s" % [walls[0]])
	check(not walls[1].has("closed"), "an open wall carries no closed key: %s" % [walls[1]])


func test_sketch_bounds_grow_by_the_ships_radius() -> void:
	var data := minimal()  # ship at [0, 0], goal at [3000, 0]
	data.walls = [{"kind": "blue", "points": [[-400, -200], [300, 500]]}]
	var bounds: Array = LevelFormat.sketch(data).bounds
	check(bounds[0] == roundi(-400 - Ship.RADIUS) and bounds[1] == roundi(-200 - Ship.RADIUS), "the box starts a ship radius before the lowest point: %s" % [bounds])
	check(bounds[0] + bounds[2] == roundi(3000 + Ship.RADIUS) and bounds[1] + bounds[3] == roundi(500 + Ship.RADIUS), "and ends a ship radius after the highest: %s" % [bounds])
