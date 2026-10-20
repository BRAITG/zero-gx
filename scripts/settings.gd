extends Node
## Player settings, saved on the device. Autoloaded as `Settings`.

signal changed

const ACTIONS: Array[StringName] = [&"steer_left", &"steer_right", &"steer_up", &"steer_down", &"fire", &"pause"]

var path := "user://settings.cfg"
var _loading := false  # the setters save; load_file saves once, after the bindings are read
## Draw the ship's velocity arrow in levels (tutorials always show it).
var show_velocity := false:
	set(value):
		show_velocity = value
		_save()
## Draw the gravity field discs around planets, black holes and stars.
var show_gravity := true:
	set(value):
		show_gravity = value
		_save()
## Sound volume, 0 (silent) to 1, applied to the master bus.
var volume := 0.8:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		AudioServer.set_bus_mute(0, volume <= 0.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
		_save()
## Touch layout: "finger" (one-finger aim and fire) or "stick" (virtual stick).
var touch_scheme := "finger":
	set(value):
		touch_scheme = value
		_save()
## Side of the screen the fire button sits on: "left" or "right".
var fire_side := "right":
	set(value):
		fire_side = value
		_save()
## Whether the mouse aims the ship.
var mouse_aims := true:
	set(value):
		mouse_aims = value
		_save()
## Pad layout: "a" (left stick steers, A fires) or "b" (right stick steers, D-pad up fires).
var pad_preset := "a":
	set(value):
		pad_preset = value
		_save()


func _ready() -> void:
	load_file()


func load_file() -> void:
	var file := ConfigFile.new()
	file.load(path)  # a missing or unreadable file keeps the defaults
	_loading = true
	show_velocity = _value(file, "display", "show_velocity", false)
	show_gravity = _value(file, "display", "show_gravity", true)
	volume = _value(file, "audio", "volume", 0.8)
	touch_scheme = _value(file, "input", "touch_scheme", "finger", ["finger", "stick", "finger_button"])
	fire_side = _value(file, "input", "fire_side", "right", ["left", "right"])
	mouse_aims = _value(file, "input", "mouse_aims", true)
	pad_preset = _value(file, "input", "pad_preset", "a", ["a", "b"])
	for action in ACTIONS:
		var saved = file.get_value("input", action) if file.has_section_key("input", action) else null
		if saved is Array and saved.all(func(e): return e is InputEvent):
			_apply_events(action, saved)
		else:
			_apply_events(action, _default_events(action))
	_loading = false
	_save()


## The stored value of `key`, or `default` when it is missing, of another type or not in `allowed`.
func _value(file: ConfigFile, section: String, key: String, default: Variant, allowed := []) -> Variant:
	var value = file.get_value(section, key, default)
	return value if typeof(value) == typeof(default) and (allowed.is_empty() or value in allowed) else default


## Replace the bindings of `action` with `events`, for every controller, and save.
func set_events(action: StringName, events: Array[InputEvent]) -> void:
	_apply_events(action, events)
	_save()


## Replace the pad bindings of every action with `preset`'s, keeping keyboard and mouse.
func apply_pad_preset(preset: String) -> void:
	var pad := _pad_events(preset)
	for action in ACTIONS:
		var events := InputMap.action_get_events(action).filter(func(e): return not (e is InputEventJoypadButton or e is InputEventJoypadMotion))
		events.append_array(pad[action])
		_apply_events(action, events)
	pad_preset = preset


## Restore the four control fields and every binding to the project defaults, and save.
func reset_controls() -> void:
	touch_scheme = "finger"
	fire_side = "right"
	mouse_aims = true
	pad_preset = "a"
	for action in ACTIONS:
		_apply_events(action, _default_events(action))
	_save()


func _apply_events(action: StringName, events: Array) -> void:
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		var copy: InputEvent = event.duplicate()
		copy.device = -1  # a binding must match every controller, not the one it was captured on
		InputMap.action_add_event(action, copy)


func _default_events(action: StringName) -> Array:
	return ProjectSettings.get_setting("input/%s" % action)["events"]


func _pad_events(preset: String) -> Dictionary:
	var b := preset == "b"
	var x := JOY_AXIS_RIGHT_X if b else JOY_AXIS_LEFT_X
	var y := JOY_AXIS_RIGHT_Y if b else JOY_AXIS_LEFT_Y
	var fire := JOY_BUTTON_DPAD_UP if b else JOY_BUTTON_A
	return {
		&"steer_left": [_pad_axis(x, -1.0)],
		&"steer_right": [_pad_axis(x, 1.0)],
		&"steer_up": [_pad_axis(y, -1.0)],
		&"steer_down": [_pad_axis(y, 1.0)],
		&"fire": [_pad_button(fire)],
		&"pause": [_pad_button(JOY_BUTTON_START)],
	}


func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _save() -> void:
	if _loading or not is_inside_tree():
		return
	var file := ConfigFile.new()
	file.set_value("display", "show_velocity", show_velocity)
	file.set_value("display", "show_gravity", show_gravity)
	file.set_value("audio", "volume", volume)
	file.set_value("input", "touch_scheme", touch_scheme)
	file.set_value("input", "fire_side", fire_side)
	file.set_value("input", "mouse_aims", mouse_aims)
	file.set_value("input", "pad_preset", pad_preset)
	for action in ACTIONS:  # only changed ones, so a new default in a later version still applies
		var events := InputMap.action_get_events(action)
		var defaults := _default_events(action)
		if events.size() != defaults.size() or not defaults.all(func(d: InputEvent) -> bool: return events.any(d.is_match)):
			file.set_value("input", action, events)
	file.save(path)
	changed.emit()
