extends "res://tests/test_case.gd"
## Level-design checks. A failure here is a level to fix, not an engine bug.

const LEVEL_COUNT := 10
const SHARD_CLEARANCE := 60.0  # px between a destructible planet and any barrier
const PICKUP_CLEARANCE := 16.0  # px between a pickup's edge and any barrier
const IDLE_FRAMES := 12000  # 200 s with no input: longer than a slow first attempt
## Autopilot: a velocity controller toward the next Route waypoint that slows as it arrives.
const CRUISE := 450.0  # px/s
const ARRIVE_GAIN := 1.2  # 1/s: desired speed per px left to the waypoint
const ARRIVE_FLOOR := 80.0  # px/s
const WAYPOINT_REACH := 110.0  # px
const DEAD_BAND := 40.0  # px/s of velocity error tolerated before thrusting
const FLIGHT_LIMIT := 4800  # frames: 80 s


func load_level(id: String) -> Node:
	return load("res://levels/%s.tscn" % id).instantiate()


func of_type(root: Node, type: Variant) -> Array:
	return root.find_children("*", "", true, false).filter(func(n): return is_instance_of(n, type))


func test_level_files_exist() -> void:
	check(Progress.levels().size() == LEVEL_COUNT, "found levels %s, expected %d" % [Progress.levels(), LEVEL_COUNT])


func test_levels_are_well_formed() -> void:
	for id in Progress.levels():
		var root := load_level(id)
		check(root.get_script() == load("res://scenes/level.gd"), "%s: root must use level.gd" % id)
		check(of_type(root, Ship).size() == 1, "%s: needs exactly one Ship" % id)
		check(of_type(root, Goal).size() == 1, "%s: needs exactly one Goal" % id)
		for rock: Asteroid in of_type(root, Asteroid):
			if not rock.orbit_parent.is_empty():
				check(rock.get_node_or_null(rock.orbit_parent) is GravityBody, "%s: %s orbits a non-planet" % [id, rock.name])
		for wall: Barrier in of_type(root, Barrier):
			# Without [editable path=...], export's binary scene conversion drops the Shape points override.
			check(root.is_editable_instance(wall), "%s: %s needs editable children" % [id, wall.name])
		var route := root.get_node_or_null("Route") as Line2D
		check(route != null and not route.visible and route.points.size() > 0, "%s: needs a hidden Route Line2D with waypoints" % id)
		check(root.title != "", "%s: needs a title" % id)
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
		var waypoints: Array[Vector2] = []
		for point in (root.get_node("Route") as Line2D).points:
			waypoints.append(root.get_node("Route").position + point)
		waypoints.append(root.goal.position)
		var next := 0
		for frame in FLIGHT_LIMIT:
			await frames(1)
			if outcome.won != null:
				break
			var at := ship.global_position
			while next < waypoints.size() - 1 and at.distance_to(waypoints[next]) < WAYPOINT_REACH:
				next += 1
			var to := waypoints[next] - at
			# Slow down only as much as the turn at this waypoint needs: none on a straight line.
			var turn := 0.0
			if next < waypoints.size() - 1:
				turn = absf(to.angle_to(waypoints[next + 1] - waypoints[next]))
			var arrive := lerpf(CRUISE, ARRIVE_FLOOR, clampf(turn / (PI / 2.0), 0.0, 1.0))
			var speed := minf(CRUISE, ARRIVE_GAIN * to.length() + arrive)
			var error := to.normalized() * speed - ship.linear_velocity
			ship.thrusting = error.length() > DEAD_BAND
			ship.aim_point = at + error.normalized() * 1000.0
		check(outcome.won == true, "%s: autopilot %s at %s heading for waypoint %d/%d (hull %d, fuel %d, %s)" % [id, "lost" if outcome.won == false else "timed out", ship.global_position.round(), next, waypoints.size(), ship.health, ship.fuel, ship.death_cause])
		root.free()
