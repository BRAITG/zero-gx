extends "res://tests/test_case.gd"
## Level-design checks. A failure here is a level to fix, not an engine bug.

const SHARD_CLEARANCE := 60.0  # px between a destructible planet and any barrier
const PICKUP_CLEARANCE := 16.0  # px between a pickup's edge and any barrier
const IDLE_FRAMES := 12000  # 200 s with no input: longer than a slow first attempt
const FLIGHT_LIMIT := 4800  # frames: 80 s


func load_level(id: String) -> Level:
	return Progress.build(id)


func of_type(root: Node, type: Variant) -> Array:
	return root.find_children("*", "", true, false).filter(func(n): return is_instance_of(n, type))


func test_levels_are_well_formed() -> void:
	for id in Progress.levels():
		var root := load_level(id)
		check(root.get_script() == load("res://scenes/level.gd"), "%s: root must use level.gd" % id)
		check(of_type(root, Ship).size() == 1, "%s: needs exactly one Ship" % id)
		check(of_type(root, Goal).size() == 1, "%s: needs exactly one Goal" % id)
		for rock: Asteroid in of_type(root, Asteroid):
			if not rock.orbit_parent.is_empty():
				check(rock.get_node_or_null(rock.orbit_parent) is GravityBody, "%s: %s orbits a non-planet" % [id, rock.name])
		var file := LevelFormat.read("res://levels/%s%s" % [id, LevelFormat.EXTENSION])
		check(LevelFormat.validate(file).is_empty(), "%s: invalid level file: %s" % [id, LevelFormat.validate(file)])
		var saved: Variant = JSON.parse_string(JSON.stringify(LevelFormat.serialize(root)))  # numbers as JSON reads them
		check(JSON.stringify(saved) == JSON.stringify(file), "%s: building and saving the level changes it" % id)
		var route := root.get_node_or_null("Route") as Line2D
		check(route != null and not route.visible and route.points.size() > 0, "%s: needs a hidden Route Line2D with waypoints" % id)
		check(root.title != "" and root.hint != "", "%s: needs a title and a hint" % id)
		var tour := root.get_node_or_null("Tour")
		check(tour != null and tour.get_child_count() > 0, "%s: needs a Tour with at least one stop" % id)
		for stop in tour.get_children() if tour else []:
			check(stop is Marker2D and stop.get_meta("text", "") != "", "%s: tour stop %s needs a Marker2D with text" % [id, stop.name])
		for pickup: Pickup in of_type(root, Pickup):
			for wall: Barrier in of_type(root, Barrier):
				var points: PackedVector2Array = wall.get_node("Shape").points
				for i in points.size() - 1:
					var gap := Geometry2D.get_closest_point_to_segment(pickup.position, wall.position + points[i], wall.position + points[i + 1]).distance_to(pickup.position)
					check(gap >= Pickup.RADIUS + PICKUP_CLEARANCE, "%s: %s is %d px from %s" % [id, pickup.name, gap, wall.name])
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
	for id in Progress.levels():
		var root := load_level(id)
		if of_type(root, Asteroid).is_empty() or of_type(root, GravityBody).is_empty():
			root.free()  # nothing to collide: skip the 200 s idle run
			continue
		world.add_child(root)
		var hits := []
		for planet: GravityBody in of_type(root, GravityBody):
			planet.struck.connect(func(by: Node): hits.append("%s: %s hit %s" % [id, by.name, planet.name]))
		var ship: Ship = of_type(root, Ship)[0]
		ship.freeze = true
		await frames(IDLE_FRAMES)
		check(hits.is_empty(), "with no input, %s" % (hits[0] if hits else ""))
		root.free()


## Every level must be winnable: an autopilot flies its hidden Route to the goal.
func test_levels_are_winnable() -> void:
	for id in Progress.levels():
		var root: Level = load_level(id)
		world.add_child(root)
		var outcome := {"won": null}
		root.finished.connect(func(won: bool): outcome.won = won)
		var ship := root.ship
		var route := root.get_node("Route") as Line2D
		var waypoints: Array[Vector2] = []
		for point in route.points:
			waypoints.append(route.position + point)
		waypoints.append(root.goal.position)
		# Route metadata "coast": waypoints flown to without thrust, as a player rides a slingshot.
		var coast: PackedInt32Array = route.get_meta("coast", PackedInt32Array())
		var cruise: float = route.get_meta("cruise", CRUISE)  # px/s; a slingshot wants its own speed
		var pilot := {"next": 0}
		for frame in FLIGHT_LIMIT:
			await frames(1)
			if outcome.won != null:
				break
			fly(ship, waypoints, pilot, cruise, coast)
		var next: int = pilot.next
		check(outcome.won == true, "%s: autopilot %s at %s heading for waypoint %d/%d (hull %d, fuel %d, %s)" % [id, "lost" if outcome.won == false else "timed out", ship.global_position.round(), next, waypoints.size(), ship.health, ship.fuel, ship.death_cause])
		root.free()
