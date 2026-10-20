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
	check(LevelDoc._v(e.doc.data.walls[1].points[0]) == Vector2(3050, 950), "wall points snap to 1 m: %s" % [e.doc.data.walls[1].points])


func test_ten_metre_toggle_restores_the_coarse_snap() -> void:
	var e := editor()
	await frames(1)
	e.fine_snap = false
	e.select_tool("wall")
	e.press(Vector2(3049, 951))
	e.release(Vector2(3049, 951), false)
	check(LevelDoc._v(e.doc.data.walls[0].points[0]) == Vector2(3000, 1000), "10 m snap: %s" % [e.doc.data.walls[0].points])


func test_zoomed_out_press_near_a_wall_point_moves_only_the_point() -> void:
	var e := editor()
	await frames(1)
	e.doc.add_wall_point(Vector2(5000, 3000))
	e.doc.add_wall_point(Vector2(6000, 3000))
	e.doc.finish_wall()
	e._camera.zoom = Vector2.ONE * 0.2
	e.select_tool("select")
	e.press(Vector2(5150, 3000))  # 30 screen px from the point at zoom 0.2
	e.drag(Vector2(5200, 3500))
	e.release(Vector2(5200, 3500), true)
	var points: Array = e.doc.data.walls[0].points
	check(LevelDoc._v(points[1]) == Vector2(6000, 3000), "the other point stays: %s" % [points])
	check(LevelDoc._v(points[0]) != Vector2(5000, 3000), "the grabbed point moves: %s" % [points])


func _mouse(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	return ev


func _key(code: Key, command := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = command  # Ctrl on Linux and Windows, Cmd on macOS: set both so the test holds on either
	ev.meta_pressed = command
	return ev


func test_right_drag_pans() -> void:
	var e := editor()
	await frames(1)
	var before: Vector2 = e._camera.position
	e._unhandled_input(_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(600, 300)))
	var move := InputEventMouseMotion.new()
	move.position = Vector2(700, 300)
	move.button_mask = MOUSE_BUTTON_MASK_RIGHT
	e._unhandled_input(move)
	check(e._camera.position.x < before.x, "dragging right moves the view left: %s -> %s" % [before, e._camera.position])
	check(e.doc.data.get("bodies", []).is_empty() and e.doc.data.get("walls", []).is_empty(), "panning places nothing")


func test_wheel_zoom_keeps_the_point_under_the_cursor() -> void:
	var e := editor()
	await frames(1)
	var cursor := Vector2(1000, 200)
	var before: Vector2 = e._to_world(cursor)
	e._unhandled_input(_mouse(MOUSE_BUTTON_WHEEL_UP, true, cursor))
	await frames(3)  # the canvas transform follows the camera a few frames later
	check(e._to_world(cursor).distance_to(before) < 1.0, "world point under cursor moved: %s -> %s" % [before, e._to_world(cursor)])


func test_ctrl_z_undoes_and_ctrl_s_saves() -> void:
	var e := editor()
	await frames(1)
	e.select_tool("planet")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	e._unhandled_input(_key(KEY_S, true))
	check(MyLevels.load_level(e.level_id).get("bodies", []).size() == 1, "Ctrl+S saves the planet")
	e._unhandled_input(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "Ctrl+Z removes the planet")


func test_typing_in_a_text_field_is_not_a_shortcut() -> void:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelFormat.read("res://levels/level_05.json"))  # a valid level, so a T that gets through really starts a flight
	var e := LevelEditor.create(id)
	world.add_child(e)
	await frames(1)
	var field := LineEdit.new()
	e.add_child(field)
	field.grab_focus()
	await frames(1)
	var typed := _key(KEY_T)
	typed.unicode = "t".unicode_at(0)
	tree.root.push_input(typed)
	await frames(2)
	check(field.text == "t", "the letter goes into the focused field: '%s'" % field.text)
	check(not (tree.current_scene is Level), "T in a text field must not start a test flight: %s" % [tree.current_scene])
	field.free()
