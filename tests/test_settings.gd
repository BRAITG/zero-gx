extends "res://tests/test_case.gd"


func test_volume_sets_the_master_bus_and_persists() -> void:
	Settings.volume = 0.5
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)) and not AudioServer.is_bus_mute(0), "half volume: %f dB" % AudioServer.get_bus_volume_db(0))
	Settings.volume = 0.0
	check(AudioServer.is_bus_mute(0), "zero volume must mute")
	Settings.volume = 0.3
	Settings.load_file()
	check(is_equal_approx(Settings.volume, 0.3), "volume must survive a reload: %f" % Settings.volume)
	Settings.volume = 0.8


func test_bindings_survive_a_reload_on_any_device() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.device = 0  # as captured from the first controller
	Settings.set_events(&"fire", [pad])
	Settings.load_file()
	var events := InputMap.action_get_events(&"fire")
	check(events.size() == 1 and events[0] is InputEventJoypadButton and events[0].button_index == JOY_BUTTON_X, "fire after reload: %s" % [events])
	var second := InputEventJoypadButton.new()
	second.button_index = JOY_BUTTON_X
	second.device = 1
	check(InputMap.event_is_action(second, &"fire"), "a binding must match every controller")
	Settings.reset_controls()

func test_preset_b_keeps_keyboard_and_moves_the_pad() -> void:
	Settings.apply_pad_preset("b")
	var fire := InputMap.action_get_events(&"fire")
	check(fire.any(func(e): return e is InputEventKey and e.physical_keycode == KEY_SPACE), "keyboard fire lost")
	check(fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_UP), "D-pad up must fire in preset B")
	check(not fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A), "A must not fire in preset B")
	var left := InputMap.action_get_events(&"steer_left")
	check(left.any(func(e): return e is InputEventJoypadMotion and e.axis == JOY_AXIS_RIGHT_X and e.axis_value < 0), "right stick must steer in preset B")
	Settings.reset_controls()

func test_corrupt_input_section_keeps_defaults() -> void:
	var file := ConfigFile.new()
	file.set_value("input", "fire", "not events")
	file.set_value("input", "touch_scheme", "stick")
	file.save(Settings.path)
	Settings.load_file()
	check(Settings.touch_scheme == "stick", "valid keys still load")
	check(InputMap.action_get_events(&"fire").size() == 3, "a corrupt binding must fall back to the defaults")
	Settings.reset_controls()


func open_controls() -> ControlsScreen:
	return ControlsScreen.open(world).find_child("ControlsScreen", true, false)


func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func test_capture_replaces_only_the_same_device_type() -> void:
	var screen := open_controls()
	screen.capture(&"fire", true)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	Input.parse_input_event(pad)
	await frames(2)
	var fire := InputMap.action_get_events(&"fire")
	check(fire.size() == 3, "fire events: %s" % [fire])
	check(fire.any(func(e): return e is InputEventKey and e.physical_keycode == KEY_SPACE), "keyboard fire lost")
	check(fire.any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT), "mouse fire lost")
	check(fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X), "X must fire")
	check(not fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A), "A must be replaced")
	Settings.reset_controls()


func test_capture_escape_cancels() -> void:
	var screen := open_controls()
	screen.capture(&"fire", true)
	Input.parse_input_event(key(KEY_ESCAPE))
	await frames(2)
	var fire := InputMap.action_get_events(&"fire")
	check(fire.size() == 3 and fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A), "Esc must leave fire unchanged: %s" % [fire])


func test_reset_restores_defaults() -> void:
	var screen := open_controls()
	Settings.apply_pad_preset("b")
	var reset: Button = screen.find_children("*", "Button", true, false).filter(func(b): return b.text == "Reset to defaults")[0]
	reset.pressed.emit()
	check(Settings.pad_preset == "a", "preset after reset: %s" % Settings.pad_preset)
	check(InputMap.action_get_events(&"fire").size() == 3, "fire must be back to its 3 defaults")
	var fire := InputMap.action_get_events(&"fire")
	check(fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A), "A must fire again")
	check(not fire.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_DPAD_UP), "D-pad up must be gone")


func test_wheel_never_binds_during_capture() -> void:
	var screen := open_controls()
	screen.capture(&"fire", true)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await frames(2)
	var fire := InputMap.action_get_events(&"fire")
	check(fire.size() == 3 and fire.any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT), "the wheel must not replace left click: %s" % [fire])
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	Input.parse_input_event(pad)
	await frames(2)
	check(InputMap.action_get_events(&"fire").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X), "capture must still be active after the wheel")
	Settings.reset_controls()


func test_escape_cancelling_capture_keeps_the_overlay() -> void:
	var overlay := ControlsScreen.open(world)
	var screen: ControlsScreen = overlay.find_child("ControlsScreen", true, false)
	screen.capture(&"fire", true)
	var event := key(KEY_ESCAPE)
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)
	check(is_instance_valid(overlay) and not overlay.is_queued_for_deletion(), "the Esc that cancelled the capture also closed the overlay")
	var close: Button = overlay.find_children("*", "Button", true, false).filter(func(b): return b.text == "Close")[0]
	check(close.is_visible_in_tree(), "control: the overlay must still show")
	overlay.close()
