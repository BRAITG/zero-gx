extends "res://tests/test_case.gd"
## An overlay sheet keeps its content centred in the central 16:9 frame, follows a resize, and its blank margins still block what lies beneath.

const FRAME := Rect2(200, 0, 1280, 720)  # the central 16:9 area of a 1680x720 window
const MARGIN_AT := Vector2(100, 360)  # left of the frame: blank overlay margin, over the button below


func test_overlay_sheet_stays_in_the_central_frame_and_blocks_its_margins() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1680, 720)
	world.add_child(viewport)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(host)
	var under := Button.new()
	under.position = MARGIN_AT - Vector2(60, 30)
	under.custom_minimum_size = Vector2(120, 60)
	host.add_child(under)
	var taps := []
	under.pressed.connect(func() -> void: taps.append(true))
	await frames(2)
	_tap(viewport, MARGIN_AT)
	check(taps.size() == 1, "control: a tap on the button without a sheet must reach it")
	taps.clear()

	var sheet := Overlay.open(host, "Settings")
	var body_text := sheet.paragraph("Wide text that fills the body.")
	var close_button := _button(sheet, "Close")
	await frames(2)
	check(FRAME.encloses(close_button.get_global_rect()), "Close must lie in the central frame: %s" % close_button.get_global_rect())
	check(is_equal_approx(body_text.get_global_rect().get_center().x, FRAME.get_center().x), "body text must be centred in the frame: %s" % body_text.get_global_rect())
	check(is_equal_approx(close_button.get_global_rect().position.x, body_text.get_global_rect().position.x), "the title row must share the body's column: %s vs %s" % [close_button.get_global_rect(), body_text.get_global_rect()])
	_tap(viewport, MARGIN_AT)
	check(taps.is_empty(), "a tap in the blank margin reached the button beneath the sheet")

	var nested := Overlay.open(sheet, "Developer options")
	await frames(2)
	var nested_close := _button(nested, "Close")
	check(FRAME.encloses(nested_close.get_global_rect()), "a nested sheet must lie in the same frame: %s" % nested_close.get_global_rect())
	check(is_equal_approx(nested_close.get_global_rect().position.x, close_button.get_global_rect().position.x), "a nested sheet must not inset again: %s vs %s" % [nested_close.get_global_rect(), close_button.get_global_rect()])

	viewport.size = Vector2i(1280, 720)
	await frames(2)
	check(is_equal_approx(body_text.get_global_rect().get_center().x, 640.0), "content must move with the resized frame: %s" % body_text.get_global_rect())
	check(Rect2(0, 0, 1280, 720).encloses(body_text.get_global_rect()), "body text must follow the resized frame: %s" % body_text.get_global_rect())


func test_a_drag_that_starts_on_a_listed_button_scrolls_and_a_tap_still_presses() -> void:
	var touchscreen := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true  # how headless reports a touchscreen; ScrollContainer only drag-scrolls on one
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	world.add_child(viewport)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(400, 300)
	viewport.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	var taps := []
	for i in 10:
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 60)
		button.pressed.connect(func() -> void: taps.append(i))
		rows.add_child(button)
	await frames(2)
	_finger(viewport, true, Vector2(150, 100))
	for step in 4:
		_slide(viewport, Vector2(150, 70 - 30 * step), Vector2(0, -30))
	_finger(viewport, false, Vector2(150, -20))
	check(scroll.scroll_vertical > 0, "a drag from a button must scroll the list")
	check(taps.is_empty(), "a drag must not press the button it started on: %s" % [taps])
	await frames(60)  # the fling settles
	_finger(viewport, true, Vector2(150, 100))
	_finger(viewport, false, Vector2(150, 100))
	check(taps.size() == 1, "a tap on a listed button must still press it: %s" % [taps])
	Input.emulate_touch_from_mouse = touchscreen


func _tap(viewport: SubViewport, at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event)


## A phone sends each touch, then the mouse event Godot emulates from it.
func _finger(viewport: SubViewport, pressed: bool, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = pressed
	touch.position = at
	viewport.push_input(touch)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = pressed
	mouse.position = at
	mouse.global_position = at
	viewport.push_input(mouse)


func _slide(viewport: SubViewport, at: Vector2, relative: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.position = at
	drag.relative = relative
	viewport.push_input(drag)
	var mouse := InputEventMouseMotion.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse.position = at
	mouse.global_position = at
	mouse.relative = relative
	viewport.push_input(mouse)


func _button(node: Node, text: String) -> Button:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())[0]
