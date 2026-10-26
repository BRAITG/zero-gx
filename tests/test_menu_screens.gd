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


func _tap(viewport: SubViewport, at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event)


func _button(node: Node, text: String) -> Button:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())[0]
