extends "res://tests/test_case.gd"


func test_snap_steps() -> void:
	check(LevelDoc.snap(Vector2(149, -51)) == Vector2(100, -100), "coarse snap: %s" % LevelDoc.snap(Vector2(149, -51)))
	check(LevelDoc.snap(Vector2(149, -51), true) == Vector2(150, -50), "fine snap: %s" % LevelDoc.snap(Vector2(149, -51), true))


func test_draw_and_close_a_wall() -> void:
	var doc := LevelDoc.new()
	for p in [Vector2(500, -300), Vector2(900, -300), Vector2(900, 300)]:
		doc.add_wall_point(p, "orange")
	doc.add_wall_point(Vector2(510, -290))  # near the first point: closes
	check(doc.drawing == -1, "tapping the first point must end the wall")
	var wall: Dictionary = doc.data.walls[0]
	check(wall.closed and wall.points.size() == 3 and wall.kind == "orange", "closed orange triangle expected: %s" % wall)
	doc.add_wall_point(Vector2(1500, 0))
	doc.finish_wall()
	check(doc.data.walls.size() == 1, "a one-point wall must be dropped")


func test_asteroid_on_a_planet_ring_orbits_it() -> void:
	var doc := LevelDoc.new()
	doc.place("planet", Vector2(1200, 600))
	doc.place("asteroid", Vector2(1200, 400))  # 200 px out: on the ring
	doc.place("asteroid", Vector2(3000, 600))  # far away: drifts
	check(doc.data.asteroids[0].orbit == {"body": 0, "radius": 200, "speed": LevelDoc.ORBIT_SPEED, "angle": snappedf(-PI / 2, 0.0001)}, "orbit: %s" % doc.data.asteroids[0])
	check(not doc.data.asteroids[1].has("orbit"), "a far asteroid must drift")


func test_erasing_a_body_fixes_orbits() -> void:
	var doc := LevelDoc.new()
	doc.place("planet", Vector2(1200, 600))
	doc.place("planet", Vector2(3000, 600))
	doc.place("asteroid", Vector2(1200, 400))
	doc.place("asteroid", Vector2(3000, 400))
	doc.erase({"type": "body", "index": 0})
	check(not doc.data.asteroids[0].has("orbit"), "an orbit around an erased planet must go")
	check(doc.data.asteroids[1].orbit.body == 0, "orbits must follow the shifted body index")


func test_hit_move_and_undo() -> void:
	var doc := LevelDoc.new()
	doc.place("star", Vector2(5000, 2000))
	var ref := doc.hit(Vector2(5300, 2000))  # inside the star's 600 px radius
	check(ref == {"type": "body", "index": 0}, "hit the star: %s" % ref)
	doc.begin_move()
	doc.move(ref, Vector2(6000, 2000))
	doc.move(ref, Vector2(7000, 2000))
	check(doc.position_of(ref) == Vector2(7000, 2000), "moved star at %s" % doc.position_of(ref))
	doc.undo()
	check(doc.position_of(ref) == Vector2(5000, 2000), "one undo must undo the whole drag")
	doc.undo()
	check(not doc.data.has("bodies") or doc.data.bodies.is_empty(), "the second undo must remove the star")
	check(doc.hit(Vector2(0, 0)).type == "ship" and doc.hit(Vector2(2050, 0)).type == "goal", "start and goal must be pickable")


func test_settings_and_validity() -> void:
	var doc := LevelDoc.new()
	check(doc.errors().is_empty(), "a new level must be valid: %s" % doc.errors())
	doc.set_setting("fuel", LevelFormat.UNLIMITED)
	doc.set_setting("hull", 250)
	doc.set_setting("title", "")
	check(doc.data.ship.fuel == LevelFormat.UNLIMITED and doc.data.ship.hull == 250, "tank settings: %s" % doc.data.ship)
	check(not doc.errors().is_empty(), "an empty title must be reported")
	doc.erase({"type": "ship", "index": 0})
	check(doc.data.has("ship"), "the start cannot be erased")


func test_wall_points_win_near_misses() -> void:
	var doc := LevelDoc.new()
	doc.add_wall_point(Vector2(5000, 3000))
	doc.add_wall_point(Vector2(6000, 3000))
	doc.finish_wall()
	check(doc.hit(Vector2(5055, 3000), 40.0).type == "wall_point", "55 px from a point is within 1.5 x 40: %s" % doc.hit(Vector2(5055, 3000), 40.0))
	check(doc.hit(Vector2(5500, 3030), 40.0).type == "wall", "mid-segment picks the wall: %s" % doc.hit(Vector2(5500, 3030), 40.0))
	check(doc.hit(Vector2(5500, 3100), 40.0).is_empty(), "100 px off the wall picks nothing")


func closed_square() -> LevelDoc:
	var doc := LevelDoc.new()
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000), Vector2(0, 1000)]:
		doc.add_wall_point(p)
	doc.add_wall_point(Vector2(10, 10))  # near the first point: closes
	return doc


func test_removing_a_point_keeps_a_closed_wall_closed() -> void:
	var doc := closed_square()
	doc.erase({"type": "wall_point", "index": 0, "point": 1}, true)
	var wall: Dictionary = doc.data.walls[0]
	check(wall.get("closed", false) and wall.points == [[0, 0], [1000, 1000], [0, 1000]], "closed A-C-D expected: %s" % [wall])


func test_removing_a_point_without_reclose_opens_the_wall_at_the_gap() -> void:
	var doc := closed_square()
	doc.erase({"type": "wall_point", "index": 0, "point": 1}, false)
	var wall: Dictionary = doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[1000, 1000], [0, 1000], [0, 0]], "open C-D-A expected: %s" % [wall])


func test_opening_at_the_first_point_starts_at_its_next_neighbour() -> void:
	var doc := closed_square()
	doc.erase({"type": "wall_point", "index": 0, "point": 0}, false)
	var wall: Dictionary = doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[1000, 0], [1000, 1000], [0, 1000]], "open B-C-D expected: %s" % [wall])


func test_opening_at_the_last_point_starts_at_its_next_neighbour() -> void:
	var doc := closed_square()
	doc.erase({"type": "wall_point", "index": 0, "point": 3}, false)
	var wall: Dictionary = doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[0, 0], [1000, 0], [1000, 1000]], "open A-B-C expected: %s" % [wall])


func test_closed_triangle_minus_a_point_opens_even_with_reclose() -> void:
	var doc := LevelDoc.new()
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000)]:
		doc.add_wall_point(p)
	doc.add_wall_point(Vector2(10, 10))  # closes the triangle
	doc.erase({"type": "wall_point", "index": 0, "point": 1}, true)
	var wall: Dictionary = doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[1000, 1000], [0, 0]], "two points, open: %s" % [wall])


func test_reclose_does_not_change_an_open_wall() -> void:
	var doc := LevelDoc.new()
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000), Vector2(0, 1000)]:
		doc.add_wall_point(p)
	doc.finish_wall()
	for reclose in [true, false]:
		var copy := LevelDoc.new(doc.data)
		copy.erase({"type": "wall_point", "index": 0, "point": 1}, reclose)
		var wall: Dictionary = copy.data.walls[0]
		check(not wall.has("closed") and wall.points == [[0, 0], [1000, 1000], [0, 1000]], "open wall minus B (reclose %s): %s" % [reclose, wall])


func test_undo_restores_the_closed_wall() -> void:
	for reclose in [true, false]:
		var doc := closed_square()
		doc.erase({"type": "wall_point", "index": 0, "point": 1}, reclose)
		doc.undo()
		var wall: Dictionary = doc.data.walls[0]
		check(wall.get("closed", false) and wall.points == [[0, 0], [1000, 0], [1000, 1000], [0, 1000]], "undo restores the closed square (reclose %s): %s" % [reclose, wall])
