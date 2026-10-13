extends "res://tests/test_case.gd"
## Level-design checks. A failure here is a level to fix, not an engine bug.

const LEVELS := ["level_01", "level_02", "level_03", "level_04", "level_05"]
const SHARD_CLEARANCE := 60.0  # px between a destructible planet and any barrier
const IDLE_FRAMES := 12000  # 200 s with no input: longer than a slow first attempt


func load_level(id: String) -> Node:
	return load("res://levels/%s.tscn" % id).instantiate()


func of_type(root: Node, type: Variant) -> Array:
	return root.find_children("*", "", true, false).filter(func(n): return is_instance_of(n, type))


func test_level_files_exist() -> void:
	for id in LEVELS:
		check(ResourceLoader.exists("res://levels/%s.tscn" % id), "%s.tscn is missing" % id)


func test_levels_are_well_formed() -> void:
	for id in LEVELS:
		var root := load_level(id)
		check(root.get_script() == load("res://scenes/level.gd"), "%s: root must use level.gd" % id)
		check(of_type(root, Ship).size() == 1, "%s: needs exactly one Ship" % id)
		check(of_type(root, Goal).size() == 1, "%s: needs exactly one Goal" % id)
		for rock: Asteroid in of_type(root, Asteroid):
			if not rock.orbit_parent.is_empty():
				check(rock.get_node_or_null(rock.orbit_parent) is GravityBody, "%s: %s orbits a non-planet" % [id, rock.name])
		for planet: GravityBody in of_type(root, GravityBody):
			if not planet.destructible:
				continue
			var r: float = planet.radius if planet.radius > 0 else GravityBody.PRESETS[planet.preset][0]
			for wall: Barrier in of_type(root, Barrier):
				var points: PackedVector2Array = wall.get_node("Shape").points
				for i in points.size() - 1:
					var a := wall.position + points[i]
					var b := wall.position + points[i + 1]
					var gap := Geometry2D.get_closest_point_to_segment(planet.position, a, b).distance_to(planet.position)
					check(gap >= r + SHARD_CLEARANCE, "%s: %s is %d px from %s (needs %d)" % [id, wall.name, gap, planet.name, r + SHARD_CLEARANCE])
		root.free()


func test_no_default_asteroid_planet_hits() -> void:
	for id in LEVELS:
		var root := load_level(id)
		world.add_child(root)
		var hits := []
		for planet: GravityBody in of_type(root, GravityBody):
			planet.struck.connect(func(by: Node): hits.append("%s: %s hit %s" % [id, by.name, planet.name]))
		var ship: Ship = of_type(root, Ship)[0]
		ship.freeze = true
		await frames(IDLE_FRAMES)
		check(hits.is_empty(), "with no input, %s" % (hits[0] if hits else ""))
		root.free()
