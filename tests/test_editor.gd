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


func _button_named(e: LevelEditor, text: String) -> Button:
	for node: Node in e.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.text == text and button.is_visible_in_tree():
			return button
	return null


func _context_menu_open(e: LevelEditor) -> bool:
	if not e.find_children("*", "Overlay", true, false).is_empty():
		return false
	for text: String in ["Blue", "Orange", "Red", "Delete wall", "Remove point", "Delete", "Radius", "Mass", "Reach", "Destructible", "Health", "Orbit speed", "Kind", "Thrust up", "Start motion", "Keep closed", "Open here"]:
		if _button_named(e, text) != null:
			return true
	return false


func _open_context_menu(e: LevelEditor, screen: Vector2) -> void:
	_route(_mouse(MOUSE_BUTTON_RIGHT, true, screen))
	_route(_mouse(MOUSE_BUTTON_RIGHT, false, screen))
	await frames(1)


func _panel_spinboxes(e: LevelEditor) -> Array[SpinBox]:
	var boxes: Array[SpinBox] = []
	for node: Node in e.find_children("*", "SpinBox", true, false):
		var box: SpinBox = node as SpinBox
		if box != null and box.is_visible_in_tree():
			boxes.append(box)
	return boxes


func test_long_press_with_wall_erase_and_placing_tools_opens_menu_without_changes() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	var before: Dictionary = e.doc.data.duplicate(true)
	for name: String in ["wall", "erase", "planet"]:
		e.select_tool(name)
		_route(_touch(0, true, screen))
		await tree.create_timer(LevelEditor.LONG_PRESS + 0.1).timeout
		check(_context_menu_open(e), "%s long-press opens the context menu" % name)
		check(e.doc.data == before, "%s long-press changes nothing" % name)
		check(e.find_children("*", "Overlay", true, false).is_empty(), "%s long-press opens no full-screen sheet" % name)
		_route(_touch(0, false, screen))
		_route(_key(KEY_ESCAPE))
		await frames(1)
	check(e.doc.data == before, "releasing and closing the menus leaves the level unchanged")


func test_right_click_opens_wall_menu_with_spec_items() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var first: Vector2 = e._to_world(Vector2(500, 400))
	_store_wall(e, [first, first + Vector2(400, 0)])
	e.select_tool("select")
	await _open_context_menu(e, Vector2(600, 400))
	check(_button_named(e, "Delete wall") != null, "wall menu offers Delete wall")
	var colour := _button_named(e, "Colour")
	if colour != null:
		colour.pressed.emit()
		await frames(1)
	check(_button_named(e, "Blue") != null and _button_named(e, "Orange") != null and _button_named(e, "Red") != null, "wall menu offers all three colours")


func test_goal_and_empty_space_open_no_context_menu() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var goal_screen := Vector2(800, 400)
	e.doc.data.goal.position = LevelDoc._p(e._to_world(goal_screen))
	await _open_context_menu(e, goal_screen)
	check(not _context_menu_open(e), "right-clicking the goal opens no menu")
	var empty_screen := Vector2(1050, 650)
	await _open_context_menu(e, empty_screen)
	check(not _context_menu_open(e), "right-clicking empty space opens no menu")


func test_numeric_menu_item_opens_panel_and_open_close_records_nothing() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("select")
	var before: Dictionary = e.doc.data.duplicate(true)
	var can_undo_before: bool = e.doc.can_undo()
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	check(radius != null, "body menu offers Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	check(_panel_spinboxes(e).size() == 1, "Radius opens the numeric property panel")
	check(e.doc.data == before, "opening a property panel does not change the level")
	check(e.doc.can_undo() == can_undo_before, "opening a property panel records no undo step")
	_route(_key(KEY_ESCAPE))
	await frames(1)
	check(_panel_spinboxes(e).is_empty(), "Escape closes the property panel")
	check(e.doc.data == before and e.doc.can_undo() == can_undo_before, "closing the panel without edits records nothing")

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




func test_right_drag_pans_and_opens_no_context_menu() -> void:
	var e := editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var before: Vector2 = e._camera.position
	var start := Vector2(600, 300)
	var finish := Vector2(700, 300)
	_route(_mouse(MOUSE_BUTTON_RIGHT, true, start))
	var move := InputEventMouseMotion.new()
	move.device = 0
	move.position = finish
	move.button_mask = MOUSE_BUTTON_MASK_RIGHT
	_route(move)
	_route(_mouse(MOUSE_BUTTON_RIGHT, false, finish))
	check(e._camera.position.x < before.x, "dragging right moves the view left: %s -> %s" % [before, e._camera.position])
	check(not _context_menu_open(e), "right-drag opens no context menu")
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
	check(e.doc.data.get("bodies", []).size() == 1, "Ctrl+Z must not undo under the level settings overlay")
	check(MyLevels.load_level(e.level_id).is_empty(), "Ctrl+S must not save under the level settings overlay")
	e.find_children("*", "Overlay", true, false)[0].close()
	await frames(2)
	e._unhandled_input(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "Ctrl+Z works again once the settings overlay is closed")


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



func closed_square_in(e: LevelEditor) -> void:
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000), Vector2(0, 1000)]:
		e.doc.add_wall_point(p)
	e.doc.add_wall_point(Vector2(10, 10))  # closes the square


func test_erasing_a_point_of_a_closed_wall_opens_two_choice_menu() -> void:
	var e := editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	closed_square_in(e)
	e.select_tool("erase")
	var point_screen: Vector2 = _screen_at(e, Vector2(1000, 0))
	_route(_mouse(MOUSE_BUTTON_LEFT, true, point_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, point_screen))
	check(e.find_children("*", "Overlay", true, false).is_empty(), "point removal uses a context menu, not a full-screen overlay")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "the menu offers exactly Keep closed and Open here")
	check(_button_named(e, "Delete wall") == null and _button_named(e, "Remove point") == null, "the reclose menu contains only Keep closed and Open here")
	check(e.doc.data.walls[0].get("closed", false) and e.doc.data.walls[0].points.size() == 4, "the wall is untouched until a choice: %s" % [e.doc.data.walls])
	var open_here := _button_named(e, "Open here")
	if open_here != null:
		open_here.pressed.emit()
	await frames(2)
	var wall: Dictionary = e.doc.data.walls[0]
	check(not wall.has("closed") and wall.points == [[1000, 1000], [0, 1000], [0, 0]], "Open here opens the wall at the gap: %s" % [wall])


func test_keep_closed_removes_the_point_and_stays_closed() -> void:
	var e := editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	closed_square_in(e)
	e.select_tool("erase")
	var point_screen: Vector2 = _screen_at(e, Vector2(1000, 0))
	_route(_mouse(MOUSE_BUTTON_LEFT, true, point_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, point_screen))
	check(e.find_children("*", "Overlay", true, false).is_empty(), "closed-point removal is not a full-screen sheet")
	check(_button_named(e, "Open here") != null and _button_named(e, "Delete wall") == null and _button_named(e, "Remove point") == null, "the reclose menu contains only Keep closed and Open here")
	var keep := _button_named(e, "Keep closed")
	check(keep != null, "the point-removal menu has Keep closed")
	if keep != null:
		keep.pressed.emit()
	await frames(2)
	var wall: Dictionary = e.doc.data.walls[0]
	check(wall.get("closed", false) and wall.points == [[0, 0], [1000, 1000], [0, 1000]], "Keep closed leaves A-C-D closed: %s" % [wall])


func test_erasing_a_point_of_a_closed_triangle_acts_at_once() -> void:
	var e := editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	for p: Vector2 in [Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 1000)]:
		e.doc.add_wall_point(p)
	e.doc.add_wall_point(Vector2(10, 10))
	e.select_tool("erase")
	var point_screen: Vector2 = _screen_at(e, Vector2(1000, 0))
	_route(_mouse(MOUSE_BUTTON_LEFT, true, point_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, point_screen))
	check(not _context_menu_open(e), "a closed triangle opens no point-removal menu")
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


func test_select_tool_tap_selects_without_opening_menu() -> void:
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
	check(not _context_menu_open(e), "select tap opens no context menu")


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


func test_mouse_left_hold_does_not_open_context_menu() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	var screen: Vector2 = Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	await tree.create_timer(LevelEditor.LONG_PRESS + 0.1).timeout
	check(not _context_menu_open(e), "mouse left-hold opens no context menu")
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
	check(not _context_menu_open(e), "pinch cancels a pending context-menu long-press")
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
	await frames(2)
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e, 1)
	_route(_key(KEY_DELETE))
	check(e.find_children("*", "Overlay", true, false).is_empty(), "Delete uses the point-removal menu, not a full-screen overlay")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Delete offers both closed-wall choices")
	check(_button_named(e, "Delete wall") == null and _button_named(e, "Remove point") == null, "Delete opens only the two reclose choices")
	check(e.doc.data == before, "Delete leaves the wall unchanged until a choice")


func test_backspace_of_closed_wall_point_asks_keep_closed_or_open_here() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e, 2)
	_route(_key(KEY_BACKSPACE))
	check(e.find_children("*", "Overlay", true, false).is_empty(), "Backspace uses the point-removal menu, not a full-screen overlay")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Backspace offers both closed-wall choices")
	check(_button_named(e, "Delete wall") == null and _button_named(e, "Remove point") == null, "Backspace opens only the two reclose choices")
	check(e.doc.data == before, "Backspace leaves the wall unchanged until a choice")


func test_erase_tool_on_closed_wall_point_asks_keep_closed_or_open_here() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	var point: Vector2 = LevelDoc._v(e.doc.data.walls[0].points[1])
	var screen: Vector2 = _screen_at(e, point)
	e.select_tool("erase")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, screen))
	check(e.find_children("*", "Overlay", true, false).is_empty(), "Erase uses the point-removal menu, not a full-screen overlay")
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Erase offers both closed-wall choices")
	check(_button_named(e, "Delete wall") == null and _button_named(e, "Remove point") == null, "Erase opens only the two reclose choices")
	check(e.doc.data == before, "Erase leaves the wall unchanged until a choice")


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


func test_selecting_another_thing_ends_the_property_panel_session() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var first_screen := Vector2(350, 400)
	var second_screen := Vector2(1050, 400)
	var first: Dictionary = e.doc.place("planet", e._to_world(first_screen))
	var second: Dictionary = e.doc.place("planet", e._to_world(second_screen))
	e.select_tool("select")
	var initial_radius: float = LevelFormat.body_value(e.doc.data.bodies[first.index], "radius")
	await _open_context_menu(e, first_screen)
	var radius := _button_named(e, "Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 1, "the first body's Radius panel opens")
	if not boxes.is_empty():
		boxes[0].value = initial_radius + 10
	check(e.doc.editing(), "the property panel owns an edit session")
	_route(_mouse(MOUSE_BUTTON_LEFT, true, second_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, second_screen))
	await frames(1)
	check(e.selection == second, "the other body becomes selected")
	check(_panel_spinboxes(e).is_empty(), "selecting another thing closes the old panel")
	check(not e.doc.editing(), "selecting another thing ends the panel edit session")
	check(LevelFormat.body_value(e.doc.data.bodies[first.index], "radius") == initial_radius + 10, "the old panel's edit remains on its original target")
func _choose_menu_option(e: LevelEditor, group: String, option: String) -> bool:
	var choice: Button = _button_named(e, option)
	if choice == null:
		var category: Button = _button_named(e, group)
		if category == null:
			return false
		category.pressed.emit()
		await frames(1)
		choice = _button_named(e, option)
	if choice == null:
		return false
	choice.pressed.emit()
	await frames(1)
	return true


func _click_control(control: Control) -> void:
	var viewport_point: Vector2 = control.get_global_transform_with_canvas() * (control.size / 2.0)
	var at: Vector2 = control.get_viewport().get_screen_transform() * viewport_point
	tree.root.push_input(_mouse(MOUSE_BUTTON_LEFT, true, at))
	tree.root.push_input(_mouse(MOUSE_BUTTON_LEFT, false, at))
	await frames(1)


func test_body_context_menus_match_the_body_kind() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var index := 0
	for kind: String in ["planet", "star", "black_hole"]:
		var screen := Vector2(260 + index * 360, 200)
		e.doc.place(kind, e._to_world(screen))
		await _open_context_menu(e, screen)
		for item: String in ["Radius", "Mass", "Reach", "Delete"]:
			check(_button_named(e, item) != null, "%s menu includes %s" % [kind, item])
		if kind == "planet":
			check(_button_named(e, "Destructible") != null and _button_named(e, "Health") != null, "planet menu includes Destructible and Health")
		else:
			check(_button_named(e, "Destructible") == null and _button_named(e, "Health") == null, "%s menu omits planet-only properties" % kind)
		_route(_key(KEY_ESCAPE))
		await frames(1)
		index += 1


func test_pickup_asteroid_and_start_context_menu_items() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var pickup_screen := Vector2(250, 200)
	e.doc.place("thrust_up", e._to_world(pickup_screen))
	await _open_context_menu(e, pickup_screen)
	check(_button_named(e, "Kind") != null, "pickup menu includes Kind")
	var kind := _button_named(e, "Kind")
	if kind != null:
		kind.pressed.emit()
		await frames(1)
	check(_button_named(e, "Thrust up") != null and _button_named(e, "Thrust down") != null and _button_named(e, "Boost") != null, "pickup kind choices include all pickup kinds")
	_route(_key(KEY_ESCAPE))
	await frames(1)
	var body_screen := Vector2(600, 200)
	var body_ref: Dictionary = e.doc.place("planet", e._to_world(body_screen))
	var body: Dictionary = e.doc.data.bodies[body_ref.index]
	body["radius"] = 100.0
	body["reach"] = 3000.0
	var orbit_screen := Vector2(900, 200)
	var rock_ref: Dictionary = e.doc.place("asteroid", e._to_world(orbit_screen))
	if not e.doc.data.asteroids[rock_ref.index].has("orbit"):
		e.doc.data.asteroids[rock_ref.index]["orbit"] = {"body": body_ref.index, "radius": 600, "speed": 0.8, "angle": 0.0}
	await _open_context_menu(e, orbit_screen)
	check(_button_named(e, "Orbit speed") != null and _button_named(e, "Delete") != null, "orbiting asteroid menu includes Orbit speed and Delete")
	_route(_key(KEY_ESCAPE))
	await frames(1)
	var plain_screen := Vector2(1050, 500)
	var plain_ref: Dictionary = e.doc.place("asteroid", e._to_world(plain_screen))
	e.doc.data.asteroids[plain_ref.index].erase("orbit")
	await _open_context_menu(e, plain_screen)
	check(_button_named(e, "Orbit speed") == null and _button_named(e, "Delete") != null, "non-orbiting asteroid menu omits Orbit speed")
	_route(_key(KEY_ESCAPE))
	await frames(1)
	var ship_screen := Vector2(1050, 200)
	e.doc.data.ship.position = LevelDoc._p(e._to_world(ship_screen))
	await _open_context_menu(e, ship_screen)
	check(_button_named(e, "Start motion") != null, "ship menu includes Start motion")


func test_colour_menu_action_recolours_wall_immediately() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var first: Vector2 = e._to_world(Vector2(400, 400))
	_store_wall(e, [first, first + Vector2(500, 0)])
	var midpoint: Vector2 = _screen_at(e, first + Vector2(250, 0))
	await _open_context_menu(e, midpoint)
	var chosen: bool = await _choose_menu_option(e, "Colour", "Orange")
	check(chosen, "Orange is available from the wall Colour menu")
	check(e.doc.data.walls[0].kind == "orange", "choosing Orange recolours the wall immediately")


func test_pickup_kind_menu_action_changes_kind_immediately() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("thrust_up", e._to_world(screen))
	await _open_context_menu(e, screen)
	var chosen: bool = await _choose_menu_option(e, "Kind", "Boost")
	check(chosen, "Boost is available from the pickup Kind menu")
	check(e.doc.data.pickups[0].kind == "boost", "choosing Boost changes the pickup immediately")


func test_destructible_menu_toggle_acts_immediately() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	await _open_context_menu(e, screen)
	var item := _button_named(e, "Destructible")
	check(item != null, "planet menu offers Destructible")
	if item is CheckButton:
		var toggle: CheckButton = item as CheckButton
		toggle.button_pressed = true
	elif item != null:
		item.pressed.emit()
	check(e.doc.data.bodies[0].get("destructible", false), "enabling Destructible updates the planet immediately")


func test_delete_menu_action_deletes_body_immediately() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	await _open_context_menu(e, screen)
	var delete := _button_named(e, "Delete")
	check(delete != null, "body menu offers Delete")
	if delete != null:
		delete.pressed.emit()
	check(e.doc.data.bodies.is_empty(), "Delete removes the body immediately")


func test_delete_wall_menu_action_removes_wall_without_reclose_question() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var first: Vector2 = e._to_world(Vector2(400, 400))
	_store_wall(e, [first, first + Vector2(400, 0)], true)
	await _open_context_menu(e, Vector2(600, 400))
	var delete_wall := _button_named(e, "Delete wall")
	check(delete_wall != null, "wall menu offers Delete wall")
	if delete_wall != null:
		delete_wall.pressed.emit()
	check(e.doc.data.walls.is_empty(), "Delete wall removes the whole wall immediately")
	check(not _context_menu_open(e), "Delete wall does not open point-removal choices")


func test_radius_panel_session_is_one_undo_step_and_preserves_total_pull() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e._refresh()
	var before: Dictionary = e.doc.data.duplicate(true)
	var pull_before: float = LevelFormat.total_pull(e.doc.data.bodies[0])
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 1, "Radius opens one numeric control")
	if not boxes.is_empty():
		var initial: float = boxes[0].value
		boxes[0].value = initial + 10.0
		boxes[0].value = initial + 20.0
		var preview_bodies: Array[Node] = e._preview.find_children("*", "GravityBody", true, false)
		check(preview_bodies.size() == 1, "the preview contains the edited body")
		if not preview_bodies.is_empty():
			var preview_body: GravityBody = preview_bodies[0] as GravityBody
			check(is_equal_approx(preview_body.radius, LevelFormat.body_value(e.doc.data.bodies[0], "radius")), "the visible body updates during the panel edit")
	check(LevelFormat.body_value(e.doc.data.bodies[0], "radius") > LevelFormat.body_value(before.bodies[0], "radius"), "Radius edits are written")
	check(is_equal_approx(LevelFormat.total_pull(e.doc.data.bodies[0]), pull_before), "Radius edits preserve total pull")
	check(e.doc.editing(), "the panel keeps one edit session open")
	_route(_key(KEY_ESCAPE))
	check(not e.doc.editing(), "closing the panel ends its edit session")
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores the body before the whole panel session")


func test_orbit_speed_panel_session_is_one_undo_step() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var body_screen := Vector2(350, 400)
	var body_ref: Dictionary = e.doc.place("planet", e._to_world(body_screen))
	var body: Dictionary = e.doc.data.bodies[body_ref.index]
	body["radius"] = 100.0
	body["reach"] = 3000.0
	var rock_screen := Vector2(850, 400)
	var rock_ref: Dictionary = e.doc.place("asteroid", e._to_world(rock_screen))
	if not e.doc.data.asteroids[rock_ref.index].has("orbit"):
		e.doc.data.asteroids[rock_ref.index]["orbit"] = {"body": body_ref.index, "radius": 1000, "speed": 0.8, "angle": 0.0}
	var before: Dictionary = e.doc.data.duplicate(true)
	await _open_context_menu(e, rock_screen)
	var speed := _button_named(e, "Orbit speed")
	if speed != null:
		speed.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 1, "Orbit speed opens one numeric control")
	if not boxes.is_empty():
		boxes[0].value = 1.1
		boxes[0].value = 0.9
		boxes[0].value = 1.4
	check(is_equal_approx(e.doc.data.asteroids[rock_ref.index].orbit.speed, 1.4), "the Orbit speed panel writes the edited speed")
	_route(_key(KEY_ESCAPE))
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores all Orbit speed panel writes")


func test_start_motion_keeps_direction_at_zero_and_zero_speed_removes_velocity() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := _screen_at(e, e.doc.position_of({"type": "ship", "index": 0}))
	var before: Dictionary = e.doc.data.duplicate(true)
	await _open_context_menu(e, screen)
	var start_motion := _button_named(e, "Start motion")
	if start_motion != null:
		start_motion.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 2, "Start motion opens Direction and Speed controls")
	if boxes.size() == 2:
		boxes[0].value = 90.0
		check(not e.doc.data.ship.has("velocity"), "changing direction at speed zero keeps the zero velocity absent")
		boxes[1].value = 250.0
		check(LevelDoc._v(e.doc.data.ship.get("velocity", [0, 0])).distance_to(Vector2(0, 250)) < 1.0, "the saved direction is applied when speed becomes positive")
		boxes[1].value = 0.0
		check(not e.doc.data.ship.has("velocity"), "setting speed to zero removes velocity")
	_route(_key(KEY_ESCAPE))
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores all Start motion panel writes")


func test_invalid_number_text_is_not_written_by_the_property_panel() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	var before: Dictionary = e.doc.data.duplicate(true)
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 1, "Radius opens a number box")
	if not boxes.is_empty():
		var field: LineEdit = boxes[0].get_line_edit()
		field.text = "not a number"
		boxes[0].apply()
	check(e.doc.data == before, "invalid number text is not written to the level")


func test_opening_old_out_of_range_body_does_not_change_its_data() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("star", e._to_world(screen))
	var ref := {"type": "body", "index": 0}
	e.doc.set_property(ref, "radius", 300.0)
	e.doc.set_property(ref, "strength", 60000.0)
	check(not e.doc.errors().is_empty(), "the old star violates the current limits before opening")
	var before: Dictionary = e.doc.data.duplicate(true)
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	check(_panel_spinboxes(e).size() == 1, "opening Radius displays a numeric editor")
	check(e.doc.data == before, "opening the Radius panel does not clamp the old star")
	check(not e.doc.errors().is_empty(), "opening the panel does not make the old star valid by writing values")


func test_delete_is_ignored_and_escape_closes_context_menu_before_selection() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	var ref: Dictionary = e.doc.place("planet", e._to_world(screen))
	e.select(ref)
	var before: Dictionary = e.doc.data.duplicate(true)
	await _open_context_menu(e, screen)
	check(_context_menu_open(e), "the context menu opens before Delete is pressed")
	_route(_key(KEY_DELETE))
	check(e.doc.data == before, "Delete does not affect the level while the context menu is open")
	_route(_key(KEY_BACKSPACE))
	_route(_key(KEY_T))
	check(e.doc.data == before, "Backspace and T do not change the level while the menu is open")
	_route(_key(KEY_ESCAPE))
	check(not _context_menu_open(e), "Escape closes the context menu")
	check(e.selection == ref, "Escape closes the menu before clearing the selection")


func test_ctrl_z_closes_context_menu_then_undoes_one_step() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	var ref: Dictionary = e.doc.place("planet", e._to_world(screen))
	var before: Dictionary = e.doc.data.duplicate(true)
	var radius: float = LevelFormat.body_value(e.doc.data.bodies[ref.index], "radius")
	e.doc.set_property(ref, "radius", radius + 20.0)
	e.select(ref)
	await _open_context_menu(e, screen)
	check(_context_menu_open(e), "the context menu opens before Ctrl+Z is pressed")
	_route(_key(KEY_Z, true))
	check(not _context_menu_open(e), "Ctrl+Z closes the context menu")
	check(e.doc.data == before, "Ctrl+Z closes the menu and undoes the previous edit")


func test_menu_and_panel_presses_do_not_reach_the_canvas() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	e.select_tool("planet")
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	check(radius != null, "the menu exposes a Radius control")
	if radius != null:
		await _click_control(radius)
	check(e.doc.data.bodies.size() == 1, "pressing the menu does not place a second body")
	var close := _button_named(e, "Close")
	check(close != null, "the property panel exposes Close")
	if close != null:
		await _click_control(close)
	check(e.doc.data.bodies.size() == 1, "pressing the panel does not reach the canvas")


func test_android_back_closes_property_panel_before_leaving_editor() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(not boxes.is_empty(), "the property panel opens before Android Back")
	if not boxes.is_empty():
		e._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(_panel_spinboxes(e).is_empty(), "Android Back closes the property panel")
		check(not e.doc.editing(), "Android Back ends the panel session")
		check(MyLevels.load_level(e.level_id).is_empty(), "Android Back closes the panel without saving or leaving")


func test_remove_point_menu_opens_keep_closed_or_open_here_choices() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	var point_screen: Vector2 = _screen_at(e, LevelDoc._v(e.doc.data.walls[0].points[1]))
	await _open_context_menu(e, point_screen)
	check(_button_named(e, "Colour") != null and _button_named(e, "Delete wall") != null, "wall-point menu includes its wall Colour and Delete wall")
	var remove := _button_named(e, "Remove point")
	check(remove != null, "wall-point menu offers Remove point")
	if remove != null:
		remove.pressed.emit()
		await frames(1)
	check(_button_named(e, "Keep closed") != null and _button_named(e, "Open here") != null, "Remove point opens the two-item reclose menu")
	check(e.find_children("*", "Overlay", true, false).is_empty(), "Remove point uses a menu rather than a full-screen overlay")
	check(_button_named(e, "Delete wall") == null and _button_named(e, "Remove point") == null, "the reclose menu contains only Keep closed and Open here")
	check(e.doc.data == before, "the closed wall stays unchanged until choosing how to reclose")

func test_focused_number_field_keeps_delete_and_undo_off_level_but_escape_closes_panel() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	var before: Dictionary = e.doc.data.duplicate(true)
	await _open_context_menu(e, screen)
	var radius := _button_named(e, "Radius")
	if radius != null:
		radius.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 1, "the property panel has a focused number field")
	if boxes.is_empty():
		return
	var fields: Array[Node] = boxes[0].find_children("*", "LineEdit", true, false)
	check(not fields.is_empty(), "the property number box contains a text field")
	if fields.is_empty():
		return
	var field: LineEdit = fields[0] as LineEdit
	field.grab_focus()
	await frames(1)
	_route(_key(KEY_DELETE))
	_route(_key(KEY_BACKSPACE))
	_route(_key(KEY_Z, true))
	_route(_key(KEY_T))
	check(e.doc.data == before, "Delete, Backspace, Ctrl+Z and T in the number field do not edit the level")
	check(not _panel_spinboxes(e).is_empty(), "keyboard editing keeps the property panel open")
	tree.root.push_input(_key(KEY_ESCAPE))
	await frames(1)
	check(_panel_spinboxes(e).is_empty(), "Escape still closes the panel while its number field has focus")


func test_mass_panel_changes_pull_without_changing_radius() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	e.doc.place("planet", e._to_world(screen))
	var before: Dictionary = e.doc.data.duplicate(true)
	var radius_before: float = LevelFormat.body_value(e.doc.data.bodies[0], "radius")
	await _open_context_menu(e, screen)
	var mass := _button_named(e, "Mass")
	if mass != null:
		mass.pressed.emit()
		await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 1, "Mass opens one numeric control")
	if not boxes.is_empty():
		var wanted: float = boxes[0].max_value
		if is_equal_approx(wanted, boxes[0].value):
			wanted = boxes[0].min_value
		boxes[0].value = wanted
		check(is_equal_approx(LevelFormat.total_pull(e.doc.data.bodies[0]), wanted), "Mass writes the selected pull")
	check(is_equal_approx(LevelFormat.body_value(e.doc.data.bodies[0], "radius"), radius_before), "Mass editing leaves Radius unchanged")
	_route(_key(KEY_ESCAPE))
	_route(_key(KEY_Z, true))
	check(e.doc.data == before, "one undo restores the body before the Mass panel session")


func test_radius_knob_drag_at_constant_distance_records_nothing() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var center_screen := Vector2(800, 400)
	var center: Vector2 = e._to_world(center_screen)
	e.doc.place("planet", center)
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_body_at(e, center_screen)
	var direction: Vector2 = Vector2(1, -1).normalized()
	var knob: Vector2 = _screen_at(e, center + direction * 64.0)
	var tangent: Vector2 = _screen_at(e, center + direction.rotated(PI / 4.0) * 64.0)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, knob))
	_route(_mouse_motion(tangent))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, tangent))
	check(e.doc.data == before, "a constant-radius knob drag leaves the draft unchanged")
	_route(_key(KEY_Z, true))
	check(e.doc.data.get("bodies", []).is_empty(), "a no-op knob drag adds no undo step")


func test_plus_drag_onto_next_neighbor_cancels_without_history() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	e.fine_snap = true
	var first: Vector2 = e._to_world(Vector2(800, 400))
	var second: Vector2 = first + Vector2(400, 0)
	_store_wall(e, [first, second, second + Vector2(400, 0)])
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e)
	var previous_selection: Dictionary = e.selection.duplicate()
	var midpoint_screen: Vector2 = _screen_at(e, (first + second) / 2.0)
	var next_screen: Vector2 = _screen_at(e, second)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, midpoint_screen))
	_route(_mouse_motion(next_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, next_screen))
	check(e.doc.data == before, "dragging an inserted point onto its next endpoint restores the wall")
	check(e.selection == previous_selection, "cancelling next-endpoint insertion restores selection")
	check(not e.doc.can_undo(), "cancelling next-endpoint insertion records no history")


func test_plus_drag_onto_first_point_of_closed_closing_edge_wraps_as_next_neighbor() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	e.fine_snap = true
	_closed_square_at_screen(e, Vector2(800, 400))
	var before: Dictionary = e.doc.data.duplicate(true)
	e.select_tool("select")
	_select_wall_point(e, 0)
	var previous_selection: Dictionary = e.selection.duplicate()
	var points: Array = e.doc.data.walls[0].points
	var first: Vector2 = LevelDoc._v(points[0])
	var last: Vector2 = LevelDoc._v(points[-1])
	var midpoint_screen: Vector2 = _screen_at(e, (first + last) / 2.0)
	var first_screen: Vector2 = _screen_at(e, first)
	_route(_mouse(MOUSE_BUTTON_LEFT, true, midpoint_screen))
	_route(_mouse_motion(first_screen))
	_route(_mouse(MOUSE_BUTTON_LEFT, false, first_screen))
	check(e.doc.data == before, "closing-edge insertion onto the first point restores the closed wall")
	check(e.selection == previous_selection, "closing-edge cancellation restores the original point selection")
	check(not e.doc.can_undo(), "closing-edge wraparound cancellation records no history")
func _wall_colour_button(e: LevelEditor, text: String) -> Button:
	for node: Node in e._wall_bar.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.text == text:
			return button
	return null


func test_wall_colour_strip_visibility_and_done_lifecycle() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	check(not e._wall_bar.is_visible_in_tree(), "the colour strip is hidden with no wall tool or selection")
	e.select_tool("wall")
	check(e._wall_bar.is_visible_in_tree(), "the Wall tool shows the colour strip")
	for colour: String in ["Blue", "Orange", "Red"]:
		var button: Button = _wall_colour_button(e, colour)
		check(button != null, "%s has a labelled colour button" % colour)
		if button != null:
			check(button.custom_minimum_size.y >= e._dp_scale(48.0), "%s meets the 48 dp minimum height" % colour)
			var chip: ImageTexture = button.icon as ImageTexture
			check(chip != null, "%s button shows a colour chip" % colour)
			if chip != null:
				var expected: Color = {"Blue": Color("#3aa0ff"), "Orange": Color("#ff8a1f"), "Red": Color("#ff1028")}[colour]
				check(chip.get_image().get_pixel(0, 0).is_equal_approx(expected), "%s chip uses its wall colour" % colour)
	check(_button_named(e, "Done") == null, "Done is hidden until drawing starts")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	check(_button_named(e, "Done") != null, "Done appears while a wall is being drawn")
	var done := _button_named(e, "Done")
	if done != null:
		done.pressed.emit()
		await frames(1)
	check(e.doc.drawing == -1, "Done finishes the wall")
	check(_button_named(e, "Done") == null, "Done hides after finishing the wall")
	e.select_tool("select")
	check(not e._wall_bar.is_visible_in_tree(), "the strip hides after switching away with no selection")
	_store_wall(e, [Vector2(3000, 0), Vector2(4000, 0)])
	e.doc.data.walls[0].kind = "red"
	e.select({"type": "wall", "index": 0})
	check(e._wall_bar.is_visible_in_tree(), "a selected wall shows the strip")
	var red: Button = _wall_colour_button(e, "Red")
	check(red != null and red.button_pressed, "a selected wall's colour is pressed")
	e.select({"type": "wall_point", "index": 0, "point": 0})
	check(e._wall_bar.is_visible_in_tree(), "a selected wall point shows the strip")


func test_wall_colour_strip_recolours_selected_wall_or_point_in_one_undo() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	_store_wall(e, [Vector2(3000, 0), Vector2(4000, 0)])
	e.select({"type": "wall", "index": 0})
	await frames(1)
	var blue: Button = _wall_colour_button(e, "Blue")
	check(blue != null and blue.button_pressed, "the selected wall starts with Blue pressed")
	var orange: Button = _wall_colour_button(e, "Orange")
	check(orange != null, "the colour strip offers Orange")
	if orange != null:
		await _click_control(orange)
	check(e.doc.data.walls[0].kind == "orange", "choosing Orange recolours the selected wall")
	check(e.doc.can_undo(), "recolouring records an undo step")
	e.doc.undo()
	e._refresh()
	check(e.doc.data.walls[0].kind == "blue" and not e.doc.can_undo(), "one undo restores the wall's original colour")
	e.select({"type": "wall_point", "index": 0, "point": 0})
	await frames(1)
	var blue_point: Button = _wall_colour_button(e, "Blue")
	check(blue_point != null and blue_point.button_pressed, "the selected point reflects its wall's colour")
	var red: Button = _wall_colour_button(e, "Red")
	check(red != null, "the colour strip offers Red for a selected point")
	if red != null:
		await _click_control(red)
	check(e.doc.data.walls[0].kind == "red", "choosing Red from a selected point recolours its wall")
	check(e.doc.can_undo(), "recolouring from a selected point records one undo step")
	e.doc.undo()
	check(e.doc.data.walls[0].kind == "blue" and not e.doc.can_undo(), "one undo restores the point's wall colour")


func test_wall_colour_strip_sets_next_wall_and_owns_its_press() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e.select_tool("wall")
	await frames(1)
	var orange: Button = _wall_colour_button(e, "Orange")
	check(orange != null, "the colour strip offers Orange for a new wall")
	if orange != null:
		await _click_control(orange)
	check(e.wall_kind == "orange", "choosing Orange without a selection sets the next wall colour")
	var walls: Array = e.doc.data.get("walls", [])
	check(walls.is_empty(), "a colour-strip press never reaches the canvas")
	check(not e.doc.can_undo(), "choosing the next wall colour records no level edit")
	e.press(Vector2(3000, 0))
	e.release(Vector2(3000, 0), false)
	walls = e.doc.data.get("walls", [])
	check(walls.size() == 1 and walls[0].kind == "orange", "the next wall uses the chosen colour")


func test_out_of_range_radius_text_is_rejected_at_both_bounds() -> void:
	for text: String in ["999999", "-1"]:
		var e: LevelEditor = editor()
		await frames(1)
		var ref: Dictionary = e.doc.place("planet", e._to_world(Vector2(800, 400)))
		e._refresh()
		var before: Dictionary = e.doc.data.duplicate(true)
		e._open_property_panel(ref, "radius")
		await frames(1)
		var boxes := _panel_spinboxes(e)
		check(boxes.size() == 1, "Radius opens a number box for %s" % text)
		if not boxes.is_empty():
			boxes[0].get_line_edit().text = text
			boxes[0].apply()
		check(e.doc.data == before, "raw radius %s is rejected without SpinBox clamping" % text)


func test_tight_keyboard_reflow_keeps_close_and_focused_field_reachable() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	e._ui_scale = 1.75
	var ref: Dictionary = e.doc.place("planet", e._to_world(Vector2(700, 170)))
	e._refresh()
	e._open_property_panel(ref, "radius")
	await frames(2)
	var boxes := _panel_spinboxes(e)
	var scrolls: Array[Node] = e._property_panel.find_children("*", "ScrollContainer", true, false)
	check(boxes.size() == 1 and scrolls.size() == 1, "the panel has a numeric field in a scroll view")
	if boxes.is_empty() or scrolls.is_empty():
		return
	var scroll: ScrollContainer = scrolls[0] as ScrollContainer
	var compact_title := false
	var units_scrollable := false
	for node: Node in e._property_panel.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.text == "Planet radius":
			compact_title = true
		elif label.text == "px":
			units_scrollable = scroll.is_ancestor_of(label)
	check(compact_title and units_scrollable, "phone title and units occupy separate lines in the scroll region")
	var field: LineEdit = boxes[0].get_line_edit()
	field.grab_focus()
	await frames(1)
	var available := Rect2(0, 68, 1280, 210)
	e._position_property_panel(ref, available)
	await frames(4)
	var close: Button
	for node: Node in e._property_panel.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.text == "Close":
			close = button
	check(close != null, "Close remains available during keyboard reflow")
	check(available.encloses(e._property_panel.get_global_rect()), "the panel fits the keyboard-free area")
	check(available.encloses(field.get_global_rect()), "the focused number field fits keyboard clearance: field=%s scroll=%s offset=%s max=%s focus=%s" % [field.get_global_rect(), scroll.get_global_rect(), scroll.scroll_vertical, scroll.get_v_scroll_bar().max_value, e.get_viewport().gui_get_focus_owner()])
	if close != null:
		check(available.encloses(close.get_global_rect()), "Close fits the keyboard-free area")
	check(not scroll.get_v_scroll_bar().is_visible_in_tree(), "the number box has no stray vertical scrollbar")


func test_settings_fuel_and_hull_submissions_stay_in_range() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._open_settings()
	await frames(1)
	var boxes := _panel_spinboxes(e)
	check(boxes.size() == 2, "Settings exposes Fuel and Hull number boxes")
	var tanks: Array[String] = ["fuel", "hull"]
	for index: int in range(mini(boxes.size(), tanks.size())):
		var box: SpinBox = boxes[index]
		for raw: String in ["-1", "999999", "1e309"]:
			box.get_line_edit().text = raw
			box.apply()
			var value: Variant = e.doc.data.ship.get(tanks[index], LevelFormat.UNLIMITED)
			check(not LevelFormat.is_unlimited(value) and float(value) >= LevelFormat.TANK_RANGE.x and float(value) <= LevelFormat.TANK_RANGE.y, "%s submission %s stays bounded: %s" % [tanks[index], raw, value])
	var overlays: Array[Node] = e.find_children("*", "Overlay", true, false)
	if not overlays.is_empty():
		(overlays[0] as Overlay).close()
	await frames(1)


func test_emulated_mouse_press_and_release_do_not_edit_the_level() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	e.select_tool("planet")
	var before: Dictionary = e.doc.data.duplicate(true)
	var history_before: int = e.doc._history.size()
	var viewport_point := Vector2(800, 400)
	var at: Vector2 = tree.root.get_screen_transform() * viewport_point
	var down: InputEventMouseButton = _mouse(MOUSE_BUTTON_LEFT, true, at)
	down.device = InputEvent.DEVICE_ID_EMULATION
	var up: InputEventMouseButton = _mouse(MOUSE_BUTTON_LEFT, false, at)
	up.device = InputEvent.DEVICE_ID_EMULATION
	tree.root.push_input(down)
	tree.root.push_input(up)
	await frames(1)
	check(e.doc.data == before, "emulated mouse events do not place a body")
	check(e.doc._history.size() == history_before, "emulated mouse events do not record history")


func test_undo_clears_right_click_reference_before_release() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var ref: Dictionary = e.doc.place("planet", e._to_world(Vector2(800, 400)))
	e._refresh()
	var point: Vector2 = tree.root.get_screen_transform() * _screen_at(e, e.doc.position_of(ref))
	tree.root.push_input(_mouse(MOUSE_BUTTON_RIGHT, true, point))
	check(not e._right_press_ref.is_empty(), "right press records its menu candidate")
	tree.root.push_input(_key(KEY_Z, true))
	await frames(1)
	check(e.doc.data.get("bodies", []).is_empty(), "undo removes the pressed body")
	check(e._right_press_ref.is_empty() and e._pan_from.is_empty() and not e._right_dragged, "undo clears pending right-click state")
	tree.root.push_input(_mouse(MOUSE_BUTTON_RIGHT, false, point))
	await frames(1)
	check(e._menu_panel == null, "the stale right release opens no menu")


func test_cancelled_closing_edge_long_press_restores_selection_and_targets_wall() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	e.fine_snap = true
	_closed_square_at_screen(e, Vector2(800, 350))
	var wall_ref := {"type": "wall", "index": 0}
	e.select(wall_ref)
	var before: Dictionary = e.doc.data.duplicate(true)
	var points: Array = e.doc.data.walls[0].points
	var closing_midpoint: Vector2 = (LevelDoc._v(points[-1]) + LevelDoc._v(points[0])) / 2.0
	var at: Vector2 = _screen_at(e, closing_midpoint)
	_route(_touch(0, true, at))
	await tree.create_timer(LevelEditor.LONG_PRESS + 0.1).timeout
	check(e.doc.data == before, "long-press cancels the provisional closing-edge point")
	check(e.selection == wall_ref, "long-press restores the pre-insertion wall selection")
	check(e._menu_ref == wall_ref, "long-press targets the surviving wall, not the cancelled point")
	_route(_touch(0, false, at))
	_route(_key(KEY_ESCAPE))


func test_property_panel_sits_outside_body_bounds_and_knob_targets() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var ref: Dictionary = e.doc.place("planet", e._to_world(Vector2(700, 300)))
	e.doc.data.bodies[ref.index].radius = 240.0
	e.doc.data.bodies[ref.index].reach = 300.0
	e._refresh()
	e.select(ref)
	e._open_property_panel(ref, "radius")
	await frames(2)
	var panel_rect: Rect2 = e._property_panel.get_global_rect()
	var center: Vector2 = _screen_at(e, e.doc.position_of(ref))
	var nearest: Vector2 = center.clamp(panel_rect.position, panel_rect.end)
	var body_radius: float = LevelDoc.drawn_radius(e.doc.data.bodies[ref.index]) * e._camera.zoom.x
	check(center.distance_to(nearest) > body_radius + 8.0, "the panel stays outside the body's drawn bounds")
	var free: Rect2 = e._free_canvas_rect()
	for role: String in ["radius", "reach"]:
		var knob: Vector2 = _screen_at(e, e._body_handle_position(ref.index, role, LevelDoc.HIT_SLOP / e._camera.zoom.x))
		if free.has_point(knob):
			check(not panel_rect.grow(8.0).has_point(knob), "the panel stays clear of the %s knob target" % role)


func test_context_menu_rows_form_one_left_aligned_list() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	e._camera.zoom = Vector2.ONE * 0.5
	await frames(2)
	var screen := Vector2(800, 400)
	var ref: Dictionary = e.doc.place("planet", e._to_world(screen))
	e.doc.set_property(ref, "destructible", true)
	await _open_context_menu(e, screen)
	await frames(2)
	var scrolls: Array[Node] = e._menu_panel.find_children("*", "ScrollContainer", true, false)
	check(scrolls.size() == 1, "the menu has one scrollable list")
	if scrolls.is_empty():
		return
	var scroll: ScrollContainer = scrolls[0] as ScrollContainer
	var rows: VBoxContainer = scroll.get_child(0) as VBoxContainer
	var delete := _button_named(e, "Delete")
	check(delete != null, "the body menu has Delete")
	if delete != null:
		check(delete.alignment == HORIZONTAL_ALIGNMENT_LEFT, "Delete text is left aligned")
		check(delete.size.x >= scroll.size.x - 1.0, "Delete fills the menu row (%s/%s)" % [delete.size.x, scroll.size.x])
		check(delete.get_theme_color("font_color").is_equal_approx(Color("#ff8a6a")), "Delete uses the destructive colour")
		var index: int = rows.get_children().find(delete)
		check(index > 0 and rows.get_child(index - 1) is ColorRect, "a separator precedes Delete")
	var destructible := _button_named(e, "Destructible")
	check(destructible is CheckButton and (destructible as CheckButton).button_pressed, "Destructible is a checked toggle row")
	if destructible != null:
		check(destructible.alignment == HORIZONTAL_ALIGNMENT_LEFT, "Destructible is left aligned")
		check(destructible.size.x >= scroll.size.x - 1.0, "Destructible fills the menu row (%s/%s)" % [destructible.size.x, scroll.size.x])


func test_property_panel_title_names_thing_and_inlines_desktop_units() -> void:
	var e: LevelEditor = editor()
	await frames(1)
	var ref: Dictionary = e.doc.place("planet", e._to_world(Vector2(700, 300)))
	e._refresh()
	e._open_property_panel(ref, "radius")
	await frames(1)
	var titled := false
	for node: Node in e._property_panel.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.text == "Planet radius (px)":
			titled = true
	check(titled, "the desktop panel title names the thing, property and units")
