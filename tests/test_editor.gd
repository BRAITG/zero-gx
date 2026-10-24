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


func test_tapping_a_stars_glow_grabs_it() -> void:
	var e := editor()
	await frames(1)
	e.select_tool("star")
	e.press(Vector2(8000, 4000))
	e.release(Vector2(8000, 4000), false)
	e.press(Vector2(8000 + 700, 4000))  # on the prominences, 100 px past the rim
	check(e._moving, "the tap grabs the star")
	e.release(Vector2(8000 + 700, 4000), false)
	check(e.doc.data.bodies.size() == 1, "no second star beside the first: %s" % [e.doc.data.bodies])


func test_long_press_opens_the_sheet_whatever_the_tool() -> void:
	var e := editor()
	await frames(1)
	var screen := Vector2(500, 300)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("wall")
	e._one_finger(true, screen)
	await frames(40)  # past LONG_PRESS at 60 FPS
	check(e.find_children("*", "Overlay", true, false).size() == 1, "holding still on the planet opens its sheet")
	e._one_finger(false, screen)
	check(e.doc.data.get("walls", []).is_empty(), "the release after a long press adds no wall point")
	await _close_sheet(e)


func _sheet_sliders(e: LevelEditor) -> Array:
	return e.find_children("*", "Overlay", true, false)[0].find_children("*", "HSlider", true, false)


func _close_sheet(e: LevelEditor) -> void:  # before the editor goes, whose camera a closing sheet refreshes
	e.find_children("*", "Overlay", true, false)[0].close()
	await frames(2)


func test_radius_and_mass_change_independently() -> void:
	var e := editor()
	await frames(1)
	e.doc.place("star", Vector2(8000, 4000))
	e._open_sheet({"type": "body", "index": 0})
	var sliders := _sheet_sliders(e)  # radius, mass, reach
	var star: Dictionary = e.doc.data.bodies[0]
	for corner: Array in [[0, 0], [0, 1], [1, 0], [1, 1]]:  # every pairing of smallest and largest
		sliders[0].value = sliders[0].max_value if corner[0] else sliders[0].min_value
		sliders[1].value = sliders[1].max_value if corner[1] else sliders[1].min_value
		check(is_equal_approx(LevelFormat.body_value(star, "radius"), sliders[0].value) and is_equal_approx(LevelFormat.total_pull(star), sliders[1].value), "radius and mass as set: %s" % [star])
		check(e.doc.errors().is_empty(), "%s: %s" % [star, e.doc.errors()])
	await _close_sheet(e)


func test_opening_an_old_out_of_range_star_brings_it_in_range() -> void:
	var e := editor()
	await frames(1)
	e.doc.place("star", Vector2(8000, 4000))
	e.doc.set_property({"type": "body", "index": 0}, "radius", 300)  # valid under the old limits
	e.doc.set_property({"type": "body", "index": 0}, "strength", 60000)
	check(not e.doc.errors().is_empty(), "the old star breaks the new limits")
	e._open_sheet({"type": "body", "index": 0})
	check(e.doc.errors().is_empty(), "opening its sheet stores the in-range values it shows: %s %s" % [e.doc.data.bodies[0], e.doc.errors()])
	await _close_sheet(e)


func test_ship_starting_velocity_is_saved() -> void:
	var e := editor()
	await frames(1)
	e._open_sheet({"type": "ship", "index": 0})
	var sliders := _sheet_sliders(e)
	sliders[0].value = 90  # down
	sliders[1].value = 250
	e.save()
	var ship: Dictionary = MyLevels.load_level(e.level_id).ship
	check(LevelDoc._v(ship.get("velocity", [0, 0])) == Vector2(0, 250), "velocity saved and loaded back: %s" % [ship])
	sliders[1].value = 0
	check(not e.doc.data.ship.has("velocity"), "speed 0 removes it: %s" % [e.doc.data.ship])
	await _close_sheet(e)


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
	check(LevelDoc._v(e.doc.data.walls[1].points[0]) == Vector2(3000, 1000), "wall points snap to 10 m by default: %s" % [e.doc.data.walls[1].points])


func test_fine_grid_toggle_snaps_to_one_metre() -> void:
	var e := editor()
	await frames(1)
	var toggle: CheckButton
	for button: CheckButton in e.find_children("*", "CheckButton", true, false):
		if button.text == "Fine grid":
			toggle = button
	check(toggle != null, "the editor has a Fine grid toggle")
	toggle.button_pressed = true
	e.select_tool("wall")
	e.press(Vector2(3049, 951))
	e.release(Vector2(3049, 951), false)
	check(LevelDoc._v(e.doc.data.walls[0].points[0]) == Vector2(3050, 950), "Fine grid snaps to 1 m: %s" % [e.doc.data.walls[0].points])


func test_closing_a_wall_scales_with_zoom() -> void:
	var e := editor()
	await frames(1)
	e.fine_snap = true
	e.select_tool("wall")
	e._camera.zoom = Vector2.ONE * 0.2
	for at: Vector2 in [Vector2(5000, 3000), Vector2(6000, 3000), Vector2(6000, 4000)]:
		e.press(at)
		e.release(at, false)
	e.press(Vector2(5080, 3000))  # 16 screen px from the first point at zoom 0.2
	e.release(Vector2(5080, 3000), false)
	check(e.doc.data.walls.size() == 1 and e.doc.data.walls[0].get("closed", false), "16 screen px closes at zoom 0.2: %s" % [e.doc.data.walls])
	e._camera.zoom = Vector2.ONE
	for at: Vector2 in [Vector2(5000, 6000), Vector2(6000, 6000), Vector2(6000, 7000)]:
		e.press(at)
		e.release(at, false)
	e.press(Vector2(5030, 6000))  # 30 screen px from the first point at zoom 1.0
	e.release(Vector2(5030, 6000), false)
	var second: Dictionary = e.doc.data.walls[1]
	check(not second.get("closed", false) and second.points.size() == 4, "30 screen px does not close at zoom 1.0: %s" % [second])


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


func _key(code: Key, command := false, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = command  # Ctrl on Linux and Windows, Cmd on macOS: set both so the test holds on either
	ev.meta_pressed = command
	ev.shift_pressed = shift
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


func test_magnify_gesture_zooms_around_the_cursor() -> void:
	var e := editor()
	await frames(1)
	var cursor := Vector2(1000, 200)
	var before: Vector2 = e._to_world(cursor)
	var zoom_before: float = e._camera.zoom.x
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = cursor
	pinch.factor = 1.2
	e._unhandled_input(pinch)
	await frames(3)
	check(is_equal_approx(e._camera.zoom.x, zoom_before * 1.2), "the pinch factor scales the zoom: %s -> %s" % [zoom_before, e._camera.zoom.x])
	check(e._to_world(cursor).distance_to(before) < 1.0, "world point under cursor moved: %s -> %s" % [before, e._to_world(cursor)])
	pinch.factor = 100.0
	e._unhandled_input(pinch)
	check(is_equal_approx(e._camera.zoom.x, LevelEditor.ZOOM_RANGE.y), "zoom stops at the limit: %s" % e._camera.zoom.x)


func test_pan_gesture_pans_the_view() -> void:
	var e := editor()
	await frames(1)
	var before: Vector2 = e._camera.position
	var swipe := InputEventPanGesture.new()
	swipe.delta = Vector2(100, -40)  # screen px; the content follows the fingers
	e._unhandled_input(swipe)
	check((e._camera.position - before).is_equal_approx(swipe.delta / e._camera.zoom.x), "the view moves by the swipe in world units: %s -> %s" % [before, e._camera.position])


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


func test_shortcuts_do_nothing_while_an_overlay_is_open() -> void:
	var e := editor()
	await frames(1)
	e.select_tool("planet")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	e._open_settings()
	e._unhandled_input(_key(KEY_Z, true))
	e._unhandled_input(_key(KEY_S, true))
	check(e.doc.data.get("bodies", []).size() == 1, "Ctrl+Z must not undo under an open sheet")
	check(MyLevels.load_level(e.level_id).is_empty(), "Ctrl+S must not save under an open sheet")
	e.find_children("*", "Overlay", true, false)[0].close()
	await frames(2)
	e._unhandled_input(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "Ctrl+Z works again once the sheet is closed")


func test_shift_z_does_not_undo() -> void:
	var e := editor()
	await frames(1)
	e.select_tool("planet")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	e._unhandled_input(_key(KEY_Z, true, true))
	check(e.doc.data.get("bodies", []).size() == 1, "Ctrl+Shift+Z is a redo, not an undo")


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


func test_the_editors_test_flight_is_a_plain_test_that_returns_to_the_editor() -> void:
	Community.platform = FakePlatform.new()
	var e := editor()
	await frames(1)
	e._test()
	await frames(2)
	var lvl := tree.current_scene as Level
	check(lvl != null and lvl.testing and lvl.level_id == e.level_id, "Test must start this draft's test flight: %s" % lvl)
	if lvl == null:
		return
	lvl.finish(true)
	await frames(2)
	var shown: Array = lvl.hud.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)
	check("Edit" in shown and not "Publish" in shown, "a plain test win offers Edit, not Publish: %s" % [shown])
	check(MyLevels.is_completed(e.level_id), "a won test still completes the level")
	lvl.hud.menu_requested.emit()
	await frames(2)
	var back := tree.current_scene
	check(back is LevelEditor and back.level_id == e.level_id, "Edit must return to the editor: %s" % back)
	if back != null:
		back.free()
		tree.current_scene = null


func _button_named(e: LevelEditor, text: String) -> Button:
	for b: Button in e.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func closed_square_in(e: LevelEditor) -> void:
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000), Vector2(0, 1000)]:
		e.doc.add_wall_point(p)
	e.doc.add_wall_point(Vector2(10, 10))  # closes the square


func test_erasing_a_point_of_a_closed_wall_asks_first() -> void:
	var e := editor()
	await frames(1)
	closed_square_in(e)
	e.select_tool("erase")
	e.press(Vector2(1000, 0))
	e.release(Vector2(1000, 0), false)
	check(e.find_children("*", "Overlay", true, false).size() == 1, "erasing a point of a closed 4-point wall opens one sheet")
	check(e.doc.data.walls[0].get("closed", false) and e.doc.data.walls[0].points.size() == 4, "the wall is untouched until a button is pressed: %s" % [e.doc.data.walls])
	var open_here := _button_named(e, "Open here")
	check(open_here != null, "the sheet has an 'Open here' button")
	if open_here:
		open_here.pressed.emit()
	await frames(2)
	var wall: Dictionary = e.doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[1000, 1000], [0, 1000], [0, 0]], "Open here opens the wall at the gap: %s" % [wall])
	check(e.find_children("*", "Overlay", true, false).is_empty(), "the sheet closes after a choice")


func test_keep_closed_removes_the_point_and_stays_closed() -> void:
	var e := editor()
	await frames(1)
	closed_square_in(e)
	e.select_tool("erase")
	e.press(Vector2(1000, 0))
	e.release(Vector2(1000, 0), false)
	var keep := _button_named(e, "Keep closed")
	check(keep != null, "the sheet has a 'Keep closed' button")
	if keep:
		keep.pressed.emit()
	await frames(2)
	var wall: Dictionary = e.doc.data.walls[0]
	check(wall.get("closed", false) and wall.points == [[0, 0], [1000, 1000], [0, 1000]], "Keep closed leaves A-C-D closed: %s" % [wall])


func test_erasing_a_point_of_a_closed_triangle_acts_at_once() -> void:
	var e := editor()
	await frames(1)
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000)]:
		e.doc.add_wall_point(p)
	e.doc.add_wall_point(Vector2(10, 10))  # closes the triangle
	e.select_tool("erase")
	e.press(Vector2(1000, 0))
	e.release(Vector2(1000, 0), false)
	check(e.find_children("*", "Overlay", true, false).is_empty(), "a closed triangle opens no sheet")
	var wall: Dictionary = e.doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[1000, 1000], [0, 0]], "the triangle opens at once: %s" % [wall])


func test_select_moves_a_ship_beside_a_planet_not_the_planet() -> void:
	var e := editor()
	await frames(1)
	e.doc.place("planet", Vector2(1200, 0))
	var radius := LevelFormat.body_value(e.doc.data.bodies[0], "radius")
	var spot := Vector2(1200 - radius - 20, 0)  # just outside the surface, inside radius + slop
	e.doc.move({"type": "ship", "index": 0}, spot)
	e.select_tool("select")
	e.press(spot)
	e.drag(spot + Vector2(0, 500))
	e.release(spot + Vector2(0, 500), true)
	check(LevelDoc._v(e.doc.data.ship.position).distance_to(spot) > 400, "the ship must move: %s" % [e.doc.data.ship])
	check(LevelDoc._v(e.doc.data.bodies[0].position) == Vector2(1200, 0), "the planet must stay: %s" % [e.doc.data.bodies])


func test_pickup_reselecting_keeps_its_kind_and_the_picker_sets_the_next_one() -> void:
	var e := editor()
	await frames(1)
	var pickup: Button = e._tool_buttons.pickup
	pickup.pressed.emit()  # the first tap selects the tool
	pickup.pressed.emit()  # a second tap must not change the kind
	check(e.tool == "pickup" and e.pickup_kind == "thrust_up", "selecting Pickup keeps its kind: %s %s" % [e.tool, e.pickup_kind])
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	var kind_picker: OptionButton = e._pickup_bar.find_children("*", "OptionButton", true, false)[0]
	kind_picker.select(2)
	kind_picker.item_selected.emit(2)
	check(e.pickup_kind == "boost", "the kind picker sets the next kind: %s" % e.pickup_kind)
	check(e.doc.data.pickups.size() == 1 and e.doc.data.pickups[0].kind == "thrust_up", "the picker changes no placed pickup: %s" % [e.doc.data.get("pickups")])
	e.press(Vector2(3000, 2000))
	e.release(Vector2(3000, 2000), false)
	check(e.doc.data.pickups.size() == 2 and e.doc.data.pickups[1].kind == "boost", "the next placement uses the picked kind: %s" % [e.doc.data.get("pickups")])


func test_saved_state_follows_the_file_and_undo_returns_to_it() -> void:
	var id := MyLevels.new_id()
	var e := LevelEditor.create(id)  # a new draft: nothing in the file yet
	world.add_child(e)
	await frames(1)
	check(e._dirty and e._undo_button.disabled, "a new draft is unsaved, with nothing to undo")
	e.select_tool("planet")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	check(e._dirty and not e._undo_button.disabled, "an edit is unsaved and can be undone")
	e.save()
	check(not e._dirty and MyLevels.load_level(id).bodies.size() == 1, "saving makes the draft saved, and the file holds the edit")
	e.select_tool("select")
	e.press(Vector2(3000, 0))  # grab the planet and drop it where it was
	e.drag(Vector2(3000, 0))
	e.release(Vector2(3000, 0), true)
	check(not e._dirty, "a move that changes nothing stays saved")
	e.select_tool("planet")
	e.press(Vector2(3000, 2000))
	e.release(Vector2(3000, 2000), false)
	check(e._dirty, "an edit after saving is unsaved")
	e._unhandled_input(_key(KEY_Z, true))
	check(not e._dirty, "undoing back to the saved level is saved, even with history left")
	check(not e._undo_button.disabled, "undo stays available while there is history")
	world.remove_child(e)
	e.free()
	var reopened := LevelEditor.create(id)
	world.add_child(reopened)
	await frames(1)
	check(not reopened._dirty and reopened._undo_button.disabled, "a saved draft reopens saved, with nothing to undo")
