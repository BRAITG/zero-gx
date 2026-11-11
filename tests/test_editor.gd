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


func test_long_press_opens_the_sheet_for_touch() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(500, 300)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("wall")
	_route(_touch(0, true, screen))
	await tree.create_timer(LevelEditor.LONG_PRESS + 0.1).timeout
	check(e.find_children("*", "Overlay", true, false).size() == 1, "touch hold on the planet opens its sheet")
	if not e.find_children("*", "Overlay", true, false).is_empty():
		await _close_sheet(e)
	_route(_touch(0, false, screen))
	check(e.doc.data.get("walls", []).is_empty(), "the release after a long press adds no wall point")




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
	await frames(2)
	var ship: Dictionary = MyLevels.load_level(e.level_id).ship
	check(LevelDoc._v(ship.get("velocity", [0, 0])) == Vector2(0, 250), "velocity saved and loaded back: %s" % [ship])
	check(e.find_children("*", "Overlay", true, false).is_empty(), "save closes the per-thing sheet")
	check(not e.doc.editing(), "save ends the sheet edit session")



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
	ev.device = 0
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


func _touch(index: int, pressed: bool, at: Vector2) -> InputEventScreenTouch:
	var ev: InputEventScreenTouch = InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = at
	return ev


func _route(event: InputEvent) -> void:
	for child: Node in world.get_children():
		if child is LevelEditor:
			var level_editor: LevelEditor = child as LevelEditor
			level_editor._unhandled_input(event)

func _selection(e: LevelEditor) -> Dictionary:
	return e.selection




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


func test_mouse_and_touch_use_device_pick_slop_at_zoom_half() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	var point: Vector2 = e._to_world(screen)
	e.doc.add_wall_point(point)
	e.doc.add_wall_point(point + Vector2(1000, 0))
	e.doc.finish_wall()
	e.select_tool("select")
	var near_point: Vector2 = screen + Vector2(0, 20)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, near_point))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, near_point))
	await frames(1)
	check(_selection(e) == {}, "mouse 20 viewport units from a point does not pick it")
	_route(_touch(0, true, near_point))
	_route(_touch(0, false, near_point))
	await frames(1)
	check(_selection(e) == {"type": "wall_point", "index": 0, "point": 0}, "touch 20 viewport units from a point picks it")


func test_select_tool_tap_selects_without_opening_sheet() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))
	await frames(1)
	check(_selection(e) == {"type": "body", "index": 0}, "tap selects the body")
	check(e.find_children("*", "Overlay", true, false).is_empty(), "select tap opens no sheet")


func test_dragging_wall_from_its_middle_preserves_press_offset() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	e.fine_snap = true
	var screen: Vector2 = Vector2(800, 400)
	var middle: Vector2 = e._to_world(screen)
	var first: Vector2 = middle - Vector2(500, 0)
	e.doc.add_wall_point(first)
	e.doc.add_wall_point(middle + Vector2(500, 0))
	e.doc.finish_wall()
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.device = 0
	motion.position = screen + Vector2(25, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_route(motion)
	_route(_mouse(MOUSE_BUTTON_LEFT, false, motion.position))
	var moved_first: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[0])
	check(moved_first == first + Vector2(50, 0), "wall moves by pointer displacement, not to the grabbed midpoint: %s" % moved_first)


func test_dragging_body_from_its_edge_preserves_press_offset() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	var center: Vector2 = e._to_world(screen)
	var ref: Dictionary = e.doc.place("planet", center)
	var body: Dictionary = e.doc.data.bodies[0]
	var edge: Vector2 = screen + Vector2((LevelDoc.drawn_radius(body) - 20.0) * 0.5, 0)
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, edge))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.device = 0
	motion.position = edge + Vector2(25, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_route(motion)
	_route(_mouse(MOUSE_BUTTON_LEFT, false, motion.position))
	check(e.doc.position_of(ref) == center + Vector2(50, 0), "body follows pointer displacement from edge press: %s" % e.doc.position_of(ref))

func _planet_at(e: LevelEditor, screen: Vector2, radius: float, reach: float) -> Vector2:
	var center: Vector2 = e._to_world(screen)
	e.doc.place("planet", center)
	var body: Dictionary = e.doc.data.bodies[0]
	body["radius"] = radius
	body["strength"] = 3200.0
	body["reach"] = reach
	return LevelDoc._v(body.position)


func _select_body_at(e: LevelEditor, screen: Vector2) -> void:
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))


func _mouse_motion(at: Vector2) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	return motion


func test_radius_knob_drag_preserves_total_pull_without_jumping_and_clamps() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(1)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = e._to_world(center_screen)
	e.doc.place("black_hole", center)
	var body: Dictionary = e.doc.data.bodies[0]
	body["radius"] = 40.0
	body["strength"] = 40000.0
	body["reach"] = 400.0
	center = LevelDoc._v(body.position)
	var total_pull: float = LevelFormat.total_pull(body)
	e.select_tool("select")
	_select_body_at(e, center_screen)
	var direction: Vector2 = Vector2(1, -1).normalized()
	var knob: Vector2 = _screen_at(e, center + direction * 40)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, knob))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 40) and e.doc.position_of({"type": "body", "index": 0}) == center, "pressing Radius changes neither its value nor the body position")
	var first_move: Vector2 = knob + direction.rotated(PI / 2.0) * 13
	_route(_mouse_motion(first_move))
	var expected_radius: float = roundf((direction * 40 + direction.rotated(PI / 2.0) * 26).length())
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), expected_radius), "the first move changes Radius by the radial distance, without jumping: %s" % LevelFormat.body_value(body, "radius"))
	check(is_equal_approx(LevelFormat.total_pull(body), total_pull), "resizing Radius keeps total pull constant")
	_route(_mouse_motion(knob + direction * 100))
	var radius_limits: Vector2 = LevelFormat.KIND_LIMITS["black_hole"]["radius"]
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), radius_limits.y), "Radius clamps to the black hole maximum: %s" % LevelFormat.body_value(body, "radius"))
	_route(_mouse_motion(center_screen))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), radius_limits.x), "Radius clamps to the black hole minimum: %s" % LevelFormat.body_value(body, "radius"))
	check(is_equal_approx(LevelFormat.total_pull(body), total_pull), "the clamped Radius still preserves total pull")
	_route(_mouse(MOUSE_BUTTON_LEFT, false, center_screen))


func test_reach_knob_drag_keeps_radius_without_jumping_and_clamps() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(1)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = e._to_world(center_screen)
	e.doc.place("star", center)
	var body: Dictionary = e.doc.data.bodies[0]
	body["radius"] = 600.0
	body["strength"] = 3000.0
	body["reach"] = 1000.0
	center = LevelDoc._v(body.position)
	e.select_tool("select")
	_select_body_at(e, center_screen)
	var direction: Vector2 = Vector2(1, 1).normalized()
	var knob: Vector2 = _screen_at(e, center + direction * 1000)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, knob))
	check(is_equal_approx(LevelFormat.body_value(body, "reach"), 1000) and e.doc.position_of({"type": "body", "index": 0}) == center, "pressing Reach changes neither its value nor the body position")
	_route(_mouse_motion(knob + direction * 20))
	check(is_equal_approx(LevelFormat.body_value(body, "reach"), 1040), "the first move changes Reach only by the pointer displacement: %s" % LevelFormat.body_value(body, "reach"))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 600), "resizing Reach leaves Radius unchanged")
	_route(_mouse_motion(knob + direction * 4000))
	var reach_limits: Vector2 = LevelFormat.KIND_LIMITS["star"]["reach"]
	check(is_equal_approx(LevelFormat.body_value(body, "reach"), reach_limits.y), "Reach clamps to the star maximum: %s" % LevelFormat.body_value(body, "reach"))
	_route(_mouse_motion(center_screen))
	check(is_equal_approx(LevelFormat.body_value(body, "reach"), reach_limits.x), "Reach clamps to the star minimum: %s" % LevelFormat.body_value(body, "reach"))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 600), "clamping Reach leaves Radius unchanged")
	_route(_mouse(MOUSE_BUTTON_LEFT, false, center_screen))


func test_equal_body_rings_keep_radius_and_reach_targets_distinct() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(1)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = _planet_at(e, center_screen, 64, 64)
	var body: Dictionary = e.doc.data.bodies[0]
	e.select_tool("select")
	_select_body_at(e, center_screen)
	var radius_direction: Vector2 = Vector2(1, -1).normalized()
	var radius_knob: Vector2 = _screen_at(e, center + radius_direction * 64)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, radius_knob))
	_route(_mouse_motion(radius_knob + radius_direction * 20))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, radius_knob + radius_direction * 20))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 104) and is_equal_approx(LevelFormat.body_value(body, "reach"), 64), "the Radius target changes only Radius when both rings have the same value: %s" % body)
	var reach_direction: Vector2 = Vector2(1, 1).normalized()
	var reach_knob: Vector2 = _screen_at(e, center + reach_direction * 64)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, reach_knob))
	_route(_mouse_motion(reach_knob + reach_direction * 20))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, reach_knob + reach_direction * 20))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 104) and is_equal_approx(LevelFormat.body_value(body, "reach"), 104), "the Reach target changes only Reach when both rings started at the same value: %s" % body)


func test_minimum_planet_at_zoom_point_one_keeps_knobs_clear_of_center() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.1
	await frames(3)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = _planet_at(e, center_screen, 32, 0)
	var body: Dictionary = e.doc.data.bodies[0]
	e.select_tool("select")
	_select_body_at(e, center_screen)
	check(e.selection == {"type": "body", "index": 0}, "the minimum planet is selected before the centre drag")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, center_screen))
	var moved_screen: Vector2 = center_screen + Vector2(20, 0)
	_route(_mouse_motion(moved_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, moved_screen))
	var moved_center: Vector2 = center + Vector2(200, 0)
	check(e.doc.position_of({"type": "body", "index": 0}) == moved_center, "a press on the exact centre moves the minimum planet to %s, got %s" % [moved_center, e.doc.position_of({"type": "body", "index": 0})])
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 32) and is_equal_approx(LevelFormat.body_value(body, "reach"), 0), "moving from the centre changes neither knob value")
	var radius_direction: Vector2 = Vector2(1, -1).normalized()
	var radius_knob: Vector2 = _screen_at(e, moved_center + radius_direction * 220)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, radius_knob))
	var radius_move: Vector2 = radius_knob + radius_direction * 13
	_route(_mouse_motion(radius_move))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, radius_move))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 162) and is_equal_approx(LevelFormat.body_value(body, "reach"), 0), "the leader-line Radius target remains distinct from the zero Reach target: %s" % body)
	var reach_direction: Vector2 = Vector2(1, 1).normalized()
	var reach_knob: Vector2 = _screen_at(e, moved_center + reach_direction * 220)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, reach_knob))
	var reach_move: Vector2 = reach_knob + reach_direction * 13
	_route(_mouse_motion(reach_move))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, reach_move))
	check(is_equal_approx(LevelFormat.body_value(body, "radius"), 162) and is_equal_approx(LevelFormat.body_value(body, "reach"), 130), "the zero Reach leader target remains distinct from Radius and the centre: %s" % body)


func test_each_body_knob_drag_is_one_undo_step() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(1)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = _planet_at(e, center_screen, 100, 300)
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_body_at(e, center_screen)
	var radius_direction: Vector2 = Vector2(1, -1).normalized()
	var radius_knob: Vector2 = _screen_at(e, center + radius_direction * 100)
	var radius_move: Vector2 = radius_knob + radius_direction * 20
	_route(_mouse(MOUSE_BUTTON_LEFT, true, radius_knob))
	_route(_mouse_motion(radius_move))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, radius_move))
	check(is_equal_approx(LevelFormat.body_value(e.doc.data.bodies[0], "radius"), 140), "Radius drag changed the body before undo")
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores all changes from the Radius drag")
	_select_body_at(e, center_screen)
	var reach_direction: Vector2 = Vector2(1, 1).normalized()
	var reach_knob: Vector2 = _screen_at(e, center + reach_direction * 300)
	var reach_move: Vector2 = reach_knob + reach_direction * 20
	_route(_mouse(MOUSE_BUTTON_LEFT, true, reach_knob))
	_route(_mouse_motion(reach_move))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, reach_move))
	check(is_equal_approx(LevelFormat.body_value(e.doc.data.bodies[0], "reach"), 340), "Reach drag changed the body before undo")
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores all changes from the Reach drag")


func test_second_finger_cancels_a_body_knob_drag_without_history() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(1)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = _planet_at(e, center_screen, 100, 300)
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_body_at(e, center_screen)
	var direction: Vector2 = Vector2(1, -1).normalized()
	var knob: Vector2 = _screen_at(e, center + direction * 100)
	_route(_touch(0, true, knob))
	var moved: Vector2 = knob + direction * 20
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = moved
	drag.relative = moved - knob
	_route(drag)
	check(is_equal_approx(LevelFormat.body_value(e.doc.data.bodies[0], "radius"), 140), "the first finger changes Radius before the second finger arrives")
	_route(_touch(1, true, knob + Vector2(100, 100)))
	check(e.doc.data == before, "the second finger cancels and restores the knob edit")
	_route(_touch(0, false, moved))
	_route(_touch(1, false, knob + Vector2(100, 100)))
	_route(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "cancelling the knob drag adds no undo entry")


func test_selected_body_shows_resize_hint() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(1)
	var center_screen := Vector2(800, 400)
	_planet_at(e, center_screen, 100, 300)
	e.select_tool("select")
	_select_body_at(e, center_screen)
	check(e._hint_label.text.begins_with("Drag Radius or Reach to resize"), "selected body hint explains ring resizing: %s" % e._hint_label.text)




func test_delete_and_backspace_delete_selection() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first: Vector2 = Vector2(800, 400)
	var second: Vector2 = Vector2(1000, 400)
	e.doc.place("planet", e._to_world(first))
	e.doc.place("planet", e._to_world(second))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, first))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, first))
	_route(_key(KEY_DELETE))
	await frames(1)
	check(e.doc.data.bodies.size() == 1, "Delete removes selected body")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, second))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, second))
	_route(_key(KEY_BACKSPACE))
	await frames(1)
	check(e.doc.data.bodies.is_empty(), "Backspace removes selected body")


func test_escape_ends_wall_then_clears_selection() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.select_tool("wall")
	for at: Vector2 in [screen, screen + Vector2(100, 0)]:
		_route(_mouse(MOUSE_BUTTON_LEFT, true, at))
		_route(_mouse(MOUSE_BUTTON_LEFT, false, at))
	_route(_key(KEY_ESCAPE))
	await frames(1)
	check(e.doc.drawing == -1, "Escape ends the wall")
	var body_screen: Vector2 = screen + Vector2(200, 100)
	e.doc.place("planet", e._to_world(body_screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, body_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, body_screen))
	check(_selection(e) == {"type": "body", "index": 0}, "body is selected before Escape clears it")
	_route(_key(KEY_ESCAPE))
	await frames(1)
	check(_selection(e) == {}, "Escape clears selection when no wall is being drawn")


func test_enter_ends_wall() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.select_tool("wall")
	for at: Vector2 in [screen, screen + Vector2(100, 0)]:
		_route(_mouse(MOUSE_BUTTON_LEFT, true, at))
		_route(_mouse(MOUSE_BUTTON_LEFT, false, at))
	_route(_key(KEY_ENTER))
	await frames(1)
	check(e.doc.drawing == -1, "Enter ends the wall")


func test_focused_text_field_keeps_delete_backspace_and_undo_from_changing_level() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen := Vector2(800, 400)
	var ref: Dictionary = e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))
	check(e.selection == ref, "the planet is selected before focusing the field")
	var before: Dictionary = e.doc.data.duplicate(true)
	var field: LineEdit = LineEdit.new()
	e.add_child(field)
	field.grab_focus()
	await frames(1)
	_route(_key(KEY_DELETE))
	check(e.doc.data == before, "Delete in a focused field leaves the selected planet unchanged")
	_route(_key(KEY_BACKSPACE))
	check(e.doc.data == before, "Backspace in a focused field leaves the selected planet unchanged")
	_route(_key(KEY_Z, true))
	await frames(1)
	check(e.doc.data == before, "Ctrl+Z in a focused field leaves the selected planet unchanged")
	field.free()


func test_mouse_left_hold_does_not_open_sheet() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	await tree.create_timer(LevelEditor.LONG_PRESS + 0.1).timeout
	check(e.find_children("*", "Overlay", true, false).is_empty(), "mouse left-hold opens no sheet")
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))


func test_second_finger_cancels_move_without_history() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	var start: Vector2 = e._to_world(screen)
	var ref: Dictionary = e.doc.place("planet", start)
	e.select_tool("select")
	_route(_touch(0, true, screen))
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = screen + Vector2(20, 0)
	drag.relative = Vector2(20, 0)
	_route(drag)
	_route(_touch(1, true, screen + Vector2(100, 100)))
	_route(_touch(0, false, drag.position))
	check(e.doc.position_of(ref) == start, "second finger restores the body before the move")
	_route(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "cancelled move leaves no history entry")


func test_second_finger_cancels_placement_without_history() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.select_tool("planet")
	_route(_touch(0, true, screen))
	_route(_touch(1, true, screen + Vector2(100, 100)))
	check(e.doc.data.get("bodies", []).is_empty(), "second finger cancels placement from this press")
	check(not e.doc.can_undo(), "cancelled placement leaves no history entry")


func test_second_finger_swallows_wall_tap_release() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.select_tool("wall")
	_route(_touch(0, true, screen))
	_route(_touch(1, true, screen + Vector2(100, 100)))
	_route(_touch(0, false, screen))
	check(e.doc.data.get("walls", []).is_empty(), "first finger release after pinch adds no wall point")


func test_selection_clears_after_undo() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))
	check(_selection(e) == {"type": "body", "index": 0}, "body is selected before undo")
	_route(_key(KEY_Z, true))
	await frames(1)
	check(e.doc.data.get("bodies", []).is_empty(), "undo removes placed body")
	check(_selection(e) == {}, "undo clears selection")


func test_selection_clears_after_tool_switch() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))
	check(_selection(e) == {"type": "body", "index": 0}, "body is selected before tool switch")
	e.select_tool("wall")
	check(_selection(e) == {}, "tool switch clears selection")


func test_second_finger_cancels_pending_long_press() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	_route(_touch(0, true, screen))
	_route(_touch(1, true, screen + Vector2(100, 100)))
	await tree.create_timer(LevelEditor.LONG_PRESS + 0.1).timeout
	check(e.find_children("*", "Overlay", true, false).is_empty(), "pinch cancels pending long-press sheet")
	_route(_touch(0, false, screen))
	_route(_touch(1, false, screen + Vector2(100, 100)))


func test_delete_removes_only_selected_wall_point() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	var first: Vector2 = e._to_world(screen)
	for point: Vector2 in [first, first + Vector2(200, 0), first + Vector2(400, 0)]:
		e.doc.add_wall_point(point)
	e.doc.finish_wall()
	e.select_tool("select")
	var selected_point: Vector2 = screen + Vector2(100, 0)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, selected_point))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, selected_point))
	_route(_key(KEY_DELETE))
	await frames(1)
	var points: Array = e.doc.data.walls[0].points
	check(points == [LevelDoc._p(first), LevelDoc._p(first + Vector2(400, 0))], "Delete removes only selected point: %s" % [points])

func _screen_at(e: LevelEditor, world_at: Vector2) -> Vector2:
	return e.get_viewport().canvas_transform * world_at


func _store_wall(e: LevelEditor, points: Array, closed := false) -> void:
	var stored: Array = []
	for point: Vector2 in points:
		stored.append(LevelDoc._p(point))
	var wall := {"kind": "blue", "points": stored}
	if closed:
		wall["closed"] = true
	e.doc.data["walls"] = [wall]


func _closed_square_at_screen(e: LevelEditor, top_left: Vector2) -> void:
	var first: Vector2 = e._to_world(top_left)
	_store_wall(e, [first, first + Vector2(400, 0), first + Vector2(400, 400), first + Vector2(0, 400)], true)


func _select_wall_point(e: LevelEditor, point_index := 0) -> void:
	var point: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[point_index])
	var screen: Vector2 = _screen_at(e, point)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))


func test_plus_press_inserts_rounded_midpoint_and_selects_it() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first_world: Vector2 = e._to_world(Vector2(800, 400))
	var last_world: Vector2 = first_world + Vector2(401, 203)
	_store_wall(e, [first_world, last_world])
	var first: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[0])
	var last: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[1])
	var midpoint: Vector2 = (first + last) / 2.0
	var midpoint_screen: Vector2 = _screen_at(e, midpoint)
	var expected := Vector2(roundi(midpoint.x), roundi(midpoint.y))
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, midpoint_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, midpoint_screen))
	check(e.doc.data.walls[0].points == [LevelDoc._p(first), LevelDoc._p(expected), LevelDoc._p(last)], "plus press inserts the exact rounded midpoint: %s" % [e.doc.data.walls[0].points])
	check(e.selection == {"type": "wall_point", "index": 0, "point": 1}, "the inserted midpoint becomes the selection: %s" % [e.selection])
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo removes the midpoint insertion")


func test_plus_drag_inserts_a_snapped_point_in_one_undo_step() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	e.fine_snap = true
	var first_world: Vector2 = e._to_world(Vector2(800, 400))
	var last_world: Vector2 = first_world + Vector2(400, 0)
	_store_wall(e, [first_world, last_world])
	var before: Dictionary = e.doc.data.duplicate(true)
	var first: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[0])
	var last: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[1])
	var midpoint_screen: Vector2 = _screen_at(e, (first + last) / 2.0)
	var moved_screen: Vector2 = midpoint_screen + Vector2(25, 20)
	var expected := LevelDoc.snap(e._to_world(moved_screen), true)
	e.select_tool("select")
	_select_wall_point(e)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, midpoint_screen))
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = moved_screen
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_route(motion)
	_route(_mouse(MOUSE_BUTTON_LEFT, false, moved_screen))
	check(e.doc.data.walls[0].points == [LevelDoc._p(first), LevelDoc._p(expected), LevelDoc._p(last)], "drag inserts and moves one snapped point: %s" % [e.doc.data.walls[0].points])
	check(e.selection == {"type": "wall_point", "index": 0, "point": 1}, "the dragged insertion remains selected: %s" % [e.selection])
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores the wall before the insertion drag")

func test_plus_drag_onto_neighbor_cancels_insertion_and_restores_selection() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	e.fine_snap = true
	var first: Vector2 = e._to_world(Vector2(800, 400))
	var neighbor: Vector2 = first + Vector2(400, 0)
	_store_wall(e, [first, neighbor, neighbor + Vector2(400, 0)])
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e)
	var previous_selection: Dictionary = e.selection.duplicate()
	var press_screen: Vector2 = _screen_at(e, (first + neighbor) / 2.0)
	var first_screen: Vector2 = _screen_at(e, first)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, press_screen))
	_route(_mouse_motion(first_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, first_screen))
	check(e.doc.data == before, "dragging the inserted point onto its neighbour restores the wall")
	check(e.selection == previous_selection, "cancelling insertion restores the previous selection: %s" % e.selection)
	check(not e.doc.can_undo(), "cancelling insertion records no undo history")




func test_plus_handle_on_closed_wall_closing_edge_inserts_after_last_point() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	_closed_square_at_screen(e, Vector2(800, 400))
	var points: Array = e.doc.data.walls[0].points
	var first: Vector2 = LevelDoc._v(points[0])
	var last: Vector2 = LevelDoc._v(points[-1])
	var midpoint: Vector2 = (first + last) / 2.0
	var midpoint_screen: Vector2 = _screen_at(e, midpoint)
	e.select_tool("select")
	_select_wall_point(e)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, midpoint_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, midpoint_screen))
	var inserted: Vector2 = (first + last) / 2.0
	var expected := Vector2(roundi(inserted.x), roundi(inserted.y))
	check(e.doc.data.walls[0].points[-1] == LevelDoc._p(expected), "closing-edge handle inserts after the old last point: %s" % [e.doc.data.walls[0].points])
	check(e.selection == {"type": "wall_point", "index": 0, "point": 4}, "the closing-edge insertion becomes selected: %s" % [e.selection])


func test_double_click_on_a_segment_inserts_at_the_snapped_pointer() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first_world: Vector2 = e._to_world(Vector2(800, 400))
	_store_wall(e, [first_world, first_world + Vector2(400, 0)])
	var click_screen := Vector2(853.5, 400)
	var expected := LevelDoc.snap(e._to_world(click_screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, click_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, click_screen))
	var double_click := _mouse(MOUSE_BUTTON_LEFT, true, click_screen)
	double_click.double_click = true
	_route(double_click)
	_route(_mouse(MOUSE_BUTTON_LEFT, false, click_screen))
	check(e.doc.data.walls[0].points == [LevelDoc._p(first_world), LevelDoc._p(expected), LevelDoc._p(first_world + Vector2(400, 0))], "double-click inserts at the snapped pointer: %s" % [e.doc.data.walls[0].points])
	check(e.selection == {"type": "wall_point", "index": 0, "point": 1}, "the double-click insertion becomes selected: %s" % [e.selection])


func test_selected_wall_point_shows_wall_hint() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first_world: Vector2 = e._to_world(Vector2(800, 400))
	_store_wall(e, [first_world, first_world + Vector2(400, 0)])
	e.select_tool("select")
	_select_wall_point(e)
	check(e._hint_label.text.begins_with("+ adds a point"), "selected wall hint explains midpoint insertion: %s" % e._hint_label.text)


func test_delete_of_closed_wall_point_asks_keep_closed_or_open_here() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e, 1)
	_route(_key(KEY_DELETE))
	check(e.find_children("*", "Overlay", true, false).size() == 1, "Delete opens the closed-wall point choice")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Delete offers both closed-wall choices")
	check(e.doc.data == before, "Delete leaves the wall unchanged until a choice")
	if not e.find_children("*", "Overlay", true, false).is_empty():
		await _close_sheet(e)


func test_backspace_of_closed_wall_point_asks_keep_closed_or_open_here() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e, 2)
	_route(_key(KEY_BACKSPACE))
	check(e.find_children("*", "Overlay", true, false).size() == 1, "Backspace opens the closed-wall point choice")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Backspace offers both closed-wall choices")
	check(e.doc.data == before, "Backspace leaves the wall unchanged until a choice")
	if not e.find_children("*", "Overlay", true, false).is_empty():
		await _close_sheet(e)


func test_erase_tool_on_closed_wall_point_asks_keep_closed_or_open_here() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	var point: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[1])
	var screen: Vector2 = _screen_at(e, point)
	e.select_tool("erase")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))
	check(e.find_children("*", "Overlay", true, false).size() == 1, "Erase opens the closed-wall point choice")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Erase offers both closed-wall choices")
	check(e.doc.data == before, "Erase leaves the wall unchanged until a choice")
	if not e.find_children("*", "Overlay", true, false).is_empty():
		await _close_sheet(e)


func test_erase_tool_on_a_segment_removes_the_wall_without_asking() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first_world: Vector2 = e._to_world(Vector2(800, 400))
	_store_wall(e, [first_world, first_world + Vector2(400, 0)])
	e.select_tool("erase")
	var middle: Vector2 = _screen_at(e, first_world + Vector2(200, 0))
	_route(_mouse(MOUSE_BUTTON_LEFT, true, middle))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, middle))
	check(e.doc.data.walls.is_empty(), "erasing a segment removes the whole wall")
	check(e.find_children("*", "Overlay", true, false).is_empty(), "erasing a segment opens no point-removal choice")


func test_closer_foreign_point_wins_over_selected_wall_plus_handle() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first: Vector2 = e._to_world(Vector2(800, 400))
	var last: Vector2 = first + Vector2(400, 0)
	var midpoint: Vector2 = (first + last) / 2.0
	var foreign: Vector2 = midpoint + Vector2(30, 0)
	e.doc.data["walls"] = [
		{"kind": "blue", "points": [LevelDoc._p(first), LevelDoc._p(last)]},
		{"kind": "red", "points": [LevelDoc._p(foreign), LevelDoc._p(foreign + Vector2(400, 0))]},
	]
	e.select_tool("select")
	_select_wall_point(e)
	var press_screen: Vector2 = _screen_at(e, midpoint) + Vector2(13, 0)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, press_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, press_screen))
	check(e.selection == {"type": "wall_point", "index": 1, "point": 0}, "the point 2 viewport units away wins over the plus 13 away: %s" % [e.selection])
	check(e.doc.data.walls[0].points.size() == 2 and e.doc.data.walls[1].points.size() == 2, "the losing plus handle inserts nothing")


func test_second_finger_cancels_plus_drag_without_history() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var first_world: Vector2 = e._to_world(Vector2(800, 400))
	_store_wall(e, [first_world, first_world + Vector2(400, 0)])
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	var first_screen: Vector2 = _screen_at(e, LevelDoc._v(e.doc.data.walls[0].points[0]))
	_route(_touch(0, true, first_screen))
	_route(_touch(0, false, first_screen))
	var points: Array = e.doc.data.walls[0].points
	var midpoint_screen: Vector2 = _screen_at(e, (LevelDoc._v(points[0]) + LevelDoc._v(points[1])) / 2.0)
	var moved_screen: Vector2 = midpoint_screen + Vector2(25, 20)
	_route(_touch(0, true, midpoint_screen))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = moved_screen
	drag.relative = moved_screen - midpoint_screen
	_route(drag)
	var expected := LevelDoc._p(LevelDoc.snap(e._to_world(moved_screen)))
	check(e.doc.data.walls[0].points.size() == 3 and e.doc.data.walls[0].points[1] == expected, "the plus drag inserts and moves its point before pinch cancellation")
	_route(_touch(1, true, moved_screen + Vector2(100, 100)))
	_route(_touch(0, false, moved_screen))
	_route(_touch(1, false, moved_screen + Vector2(100, 100)))
	check(e.doc.data == before, "second finger restores the wall before the plus drag")
	check(not e.doc.can_undo(), "cancelled plus drag leaves no undo entry")

func test_undo_invalidates_a_pressed_body_before_a_later_drag() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_key(KEY_Z, true))
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = screen + Vector2(20, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_route(motion)
	_route(_mouse(MOUSE_BUTTON_LEFT, false, motion.position))
	check(e.doc.data.get("bodies", []).is_empty(), "drag after undo cannot move the removed body")
	check(e.selection.is_empty() and not e.doc.editing(), "undo invalidates the pressed reference and its edit session")


func test_delete_invalidates_a_pressed_body_before_a_later_drag() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_key(KEY_DELETE))
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.position = screen + Vector2(20, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_route(motion)
	_route(_mouse(MOUSE_BUTTON_LEFT, false, motion.position))
	check(e.doc.data.get("bodies", []).is_empty(), "drag after Delete cannot restore or move the removed body")
	check(e.selection.is_empty() and not e.doc.editing(), "Delete invalidates the pressed reference and its edit session")


func test_tool_and_selection_changes_close_per_thing_sheets() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	var ref: Dictionary = e.doc.place("planet", Vector2(5000, 3000))
	e._open_sheet(ref)
	var sliders := _sheet_sliders(e)
	sliders[0].value += 1
	check(e.doc.editing(), "the body sheet owns an edit session")
	e.select_tool("erase")
	await frames(2)
	check(e.find_children("*", "Overlay", true, false).is_empty(), "tool switch closes the per-thing sheet")
	check(not e.doc.editing(), "tool switch ends the sheet session")
	e._open_sheet(ref)
	e.select({"type": "ship", "index": 0})
	await frames(2)
	check(e.find_children("*", "Overlay", true, false).is_empty(), "selection change closes the per-thing sheet")
	check(not e.doc.editing(), "selection change ends the sheet session")
