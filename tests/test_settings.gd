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


func test_bad_values_keep_defaults_and_bindings() -> void:
	Settings.mouse_aims = false
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	var file := ConfigFile.new()
	file.set_value("input", "fire", [pad])
	file.set_value("input", "mouse_aims", "yes")
	file.set_value("input", "touch_scheme", "bogus")
	file.set_value("input", "fire_side", 3)
	file.save(Settings.path)
	Settings.load_file()
	var fire := InputMap.action_get_events(&"fire")
	check(fire.size() == 1 and fire[0] is InputEventJoypadButton and fire[0].button_index == JOY_BUTTON_X, "the custom fire binding was lost: %s" % [fire])
	check(Settings.mouse_aims == true, "a wrong-typed mouse_aims must load as the default, not %s" % Settings.mouse_aims)
	check(Settings.touch_scheme == "finger", "an unknown touch_scheme must load as the default, not %s" % Settings.touch_scheme)
	check(Settings.fire_side == "right", "a wrong-typed fire_side must load as the default, not %s" % Settings.fire_side)
	file.load(Settings.path)
	var saved = file.get_value("input", "fire", [])
	check(saved is Array and saved.size() == 1 and saved[0] is InputEventJoypadButton, "the file lost the custom fire binding: %s" % [saved])
	Settings.reset_controls()


## Saving the defaults would freeze them: a later version's new default would never reach the player.
func test_only_changed_bindings_are_saved() -> void:
	Settings.reset_controls()
	var file := ConfigFile.new()
	file.load(Settings.path)
	check(not file.has_section_key("input", "fire"), "default fire bindings were written")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	Settings.set_events(&"fire", [key])
	file = ConfigFile.new()
	file.load(Settings.path)
	check(file.has_section_key("input", "fire"), "a changed fire binding must be saved")
	check(not file.has_section_key("input", "pause"), "unchanged pause bindings were written")
	Settings.reset_controls()


## Keys and the D-pad reach every row, scrolling it into view, down to Reset.
func test_keys_reach_reset_on_the_controls_screen() -> void:
	var overlay := ControlsScreen.open(world)
	var reset: Button = overlay.find_children("*", "Button", true, false).filter(func(b): return b.text == "Reset to defaults")[0]
	var scroll: ScrollContainer = overlay.find_children("*", "ScrollContainer", true, false)[0]
	await frames(2)
	for i in 40:
		if tree.root.gui_get_focus_owner() == reset:
			break
		for down in [true, false]:
			var event := InputEventAction.new()
			event.action = &"ui_down"
			event.pressed = down
			Input.parse_input_event(event)
			Input.flush_buffered_events()
		await frames(1)
	await frames(2)
	check(tree.root.gui_get_focus_owner() == reset, "ui_down stopped at %s, never reaching Reset" % tree.root.gui_get_focus_owner())
	check(scroll.get_global_rect().encloses(reset.get_global_rect()), "Reset %s is outside the scroll's view %s" % [reset.get_global_rect(), scroll.get_global_rect()])
	check(reset.has_focus(true), "navigating with keys must show the focus ring")
	overlay.close()


func controls_screen(touch: bool) -> ControlsScreen:
	var screen := ControlsScreen.new()
	screen.touch_available = touch
	world.add_child(screen)
	return screen


func texts(screen: Node, type: String) -> Array:
	return screen.find_children("*", type, true, false).map(func(node): return node.text)


func test_controls_screen_hides_touch_options_without_a_touchscreen() -> void:
	check(ControlsScreen.new().touch_available == DisplayServer.is_touchscreen_available(), "the screen must ask the display for a touchscreen")
	var screen := controls_screen(false)
	var buttons := texts(screen, "Button")
	for touch_only in ["One finger", "Stick + button", "Finger + button", "Left side", "Right side", "Fire on the left", "Fire on the right"]:
		check(not touch_only in buttons, "'%s' is a touch option and must not show without a touchscreen" % touch_only)
	var labels := texts(screen, "Label")
	check(not "Touch" in labels and not "On-screen fire button" in labels and not "Fire button" in labels, "the touch rows' labels showed: %s" % [labels])
	check("Left stick + A" in buttons and screen._mouse != null, "the other controls must stay")


func test_controls_screen_offers_the_touch_options_with_a_touchscreen() -> void:
	var screen := controls_screen(true)
	var buttons := texts(screen, "Button")
	for wanted in ["One finger", "Stick + button", "Finger + button", "Left side", "Right side"]:
		check(wanted in buttons, "'%s' must show with a touchscreen: %s" % [wanted, buttons])
	check(not "Fire on the right" in buttons and not "Fire on the left" in buttons, "the fire button's sides are now 'Left side' and 'Right side'")
	check("On-screen fire button" in texts(screen, "Label"), "the fire button row needs its new label")
	var left: Button = screen.find_children("*", "Button", true, false).filter(func(b): return b.text == "Left side")[0]
	left.pressed.emit()
	check(Settings.fire_side == "left", "'Left side' must set fire_side, got %s" % Settings.fire_side)


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


const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"


func joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func test_every_joy_button_has_its_own_readable_name() -> void:
	var seen := {}
	for button in range(JOY_BUTTON_MAX):
		var label := ShipInput.binding_name(joy_button(button))
		check(label != "" and not "Joypad" in label, "button %d reads as '%s'" % [button, label])
		check(not seen.has(label), "button %d shares the name '%s'" % [button, label])
		seen[label] = true
	check("99" in ShipInput.binding_name(joy_button(99)), "an unnamed button must keep its number")


func test_stick_names_split_by_direction_and_triggers_are_named() -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		var low := ShipInput.binding_name(joy_axis(axis, -1.0))
		var high := ShipInput.binding_name(joy_axis(axis, 1.0))
		check(low != high and not ("Joypad" in (low + high)), "axis %d: '%s' and '%s' must name opposite directions" % [axis, low, high])
	check("trigger" in ShipInput.binding_name(joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)).to_lower(), "a trigger must be named as one")
	var unnamed := ShipInput.binding_name(joy_axis(9, -1.0))
	check("9" in unnamed and not "Motion" in unnamed, "an unnamed axis must keep its number: '%s'" % unnamed)


## The intro `scheme` shows, from a ShipInput outside the tree: it reads only the scheme and the bindings.
func intro_for(scheme: String) -> String:
	var input := ShipInput.new(null)
	input.scheme = scheme
	var hint := input.intro_hint()
	input.free()
	return hint


func test_introduction_names_the_rebound_fire_button() -> void:
	Settings.set_events(&"fire", [joy_button(JOY_BUTTON_X)])
	var hint := intro_for("mouse_aim")
	check("X / Square" in hint and not "Space" in hint, "the intro must name only the rebound fire: '%s'" % hint)
	Settings.reset_controls()


## A real Level (its HUD pauses and shows the intro) with a ship at the origin and a distant goal; `props` are set before it enters the tree.
func level_with(props: Dictionary) -> Level:
	var lvl := Node2D.new()
	lvl.set_script(load("res://scenes/level.gd"))
	for prop in props:
		lvl.set(prop, props[prop])
	lvl.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(3000, 0)
	lvl.add_child(goal)
	world.add_child(lvl)
	return lvl


func mouse_move() -> void:
	var move := InputEventMouseMotion.new()
	move.position = Vector2(400, 300)
	tree.root.push_input(move, true)


func touch_at(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	tree.root.push_input(event, true)


func test_level_one_introduction_follows_the_controls_in_use() -> void:
	Settings.mouse_aims = true
	var lvl := level_with({"level_id": "level_01", "title": "Drift"})
	await frames(1)
	mouse_move()
	await frames(1)
	check("mouse" in lvl.hud.intro_text().to_lower(), "the desktop intro must describe mouse aim: '%s'" % lvl.hud.intro_text())
	check(not "Touch" in lvl.hud.intro_text(), "the desktop intro must not describe touch: '%s'" % lvl.hud.intro_text())
	Settings.mouse_aims = false
	check("click" in lvl.hud.intro_text().to_lower(), "a mouse setting changed under the open intro must reach it: '%s'" % lvl.hud.intro_text())
	Settings.reset_controls()


func test_a_custom_levels_hint_is_shown_as_written() -> void:
	var lvl := level_with({"level_id": MyLevels.PREFIX + "draft", "title": "Mine", "hint": "Touch and hold the ring."})
	await frames(1)
	mouse_move()
	await frames(1)
	check("Touch and hold the ring." in lvl.hud.intro_text(), "a player's own hint must show unchanged: '%s'" % lvl.hud.intro_text())


func test_velocity_arrow_setting_reaches_the_ship_at_once() -> void:
	Settings.show_velocity = false
	var lvl := level_with({})
	await frames(1)
	Settings.show_velocity = true
	check(lvl.ship.show_velocity, "turning the velocity arrow on must reach the ship")
	Settings.show_velocity = false
	check(not lvl.ship.show_velocity, "turning the velocity arrow off must reach the ship")


func test_tutorial_velocity_arrow_stays_on_whatever_the_setting() -> void:
	Settings.show_velocity = false
	var lvl := level_with({"show_velocity": true})
	await frames(1)
	Settings.show_velocity = true
	Settings.show_velocity = false
	check(lvl.ship.show_velocity, "a level that always shows its arrow must keep it when the setting is off")


func test_mouse_setting_changed_in_the_pause_takes_effect_on_resume() -> void:
	Settings.mouse_aims = true
	var lvl := level_with({})
	await frames(1)
	mouse_move()
	await frames(1)
	check(lvl.input.scheme == "mouse_aim", "scheme %s after a mouse move, expected mouse_aim" % lvl.input.scheme)
	lvl.hud.toggle_pause()
	Settings.mouse_aims = false
	lvl.hud.toggle_pause()
	await frames(1)
	check(lvl.input.scheme == "mouse_click", "the scheme must follow the setting on resume, not the next click: %s" % lvl.input.scheme)
	Settings.reset_controls()


func test_touch_setting_changed_in_the_pause_shows_its_overlay_on_resume() -> void:
	Settings.touch_scheme = "finger"
	var lvl := level_with({})
	await frames(1)
	var centre := tree.root.get_visible_rect().size / 2.0
	touch_at(0, centre, true)
	touch_at(0, centre, false)
	await frames(1)
	check(lvl.input.scheme == "finger" and not lvl.input.touch.visible, "one finger must show no overlay (scheme %s, overlay %s)" % [lvl.input.scheme, lvl.input.touch.visible])
	lvl.hud.toggle_pause()
	Settings.touch_scheme = "stick"
	lvl.hud.toggle_pause()
	await frames(1)
	check(lvl.input.scheme == "stick" and lvl.input.touch.visible, "the stick's overlay must show on resume (scheme %s, overlay %s)" % [lvl.input.scheme, lvl.input.touch.visible])
	Settings.reset_controls()
