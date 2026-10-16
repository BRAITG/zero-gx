extends "res://tests/test_case.gd"


func editor() -> LevelEditor:
	var e := LevelEditor.create(MyLevels.new_id())
	world.add_child(e)
	return e


func test_placing_on_a_thing_does_not_stack() -> void:
	var e := editor()
	await frames(1)
	var spots := {"planet": Vector2(3000, 0), "black_hole": Vector2(3000, 2000), "star": Vector2(8000, 4000), "asteroid": Vector2(3000, 0), "pickup": Vector2(3000, 2000)}
	for kind: String in spots:
		e.select_tool(kind)
		var at: Vector2 = spots[kind]
		for i in 3:
			e.press(at)
			e.release(at, false)
	var data: Dictionary = e.doc.data
	check(data.bodies.size() == 3, "one of each body: %s" % [data.bodies.map(func(b): return b.kind)])
	check(data.get("asteroids", []).is_empty() and data.get("pickups", []).is_empty(), "no asteroid or pickup on top of a body")


func test_placing_on_a_thing_drags_it() -> void:
	var e := editor()
	await frames(1)
	e.select_tool("planet")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	e.press(Vector2(3000, 0))
	e.drag(Vector2(3500, 500))
	e.release(Vector2(3500, 500), true)
	check(e.doc.data.bodies.size() == 1 and LevelDoc._v(e.doc.data.bodies[0].position) == Vector2(3500, 500), "the planet must move, not multiply: %s" % [e.doc.data.bodies])


func test_things_go_where_they_are_put_and_walls_snap() -> void:
	var e := editor()
	await frames(1)
	e.doc.add_wall_point(Vector2(4000, -500))
	e.doc.add_wall_point(Vector2(4000, 500))
	e.doc.finish_wall()
	e.select_tool("asteroid")
	e.press(Vector2(4035.4, 13.2))  # beside the wall, off the grid
	e.release(Vector2(4035.4, 13.2), false)
	var rocks: Array = e.doc.data.get("asteroids", [])
	check(rocks.size() == 1 and LevelDoc._v(rocks[0].position) == Vector2(4035, 13), "asteroid beside the wall, unsnapped: %s" % [rocks])
	e.select_tool("wall")
	e.press(Vector2(3049, 951))
	e.release(Vector2(3049, 951), false)
	check(LevelDoc._v(e.doc.data.walls[1].points[0]) == Vector2(3000, 1000), "wall points snap: %s" % [e.doc.data.walls[1].points])
