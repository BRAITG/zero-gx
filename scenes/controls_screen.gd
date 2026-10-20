class_name ControlsScreen
extends VBoxContainer
## The Controls overlay: touch layout, mouse mode, pad preset, and a row per action to rebind.

const PROMPT := "Press a key or button… (Esc cancels)"
const FONT := 22

## Whether to offer the touch layouts; tests set it before the screen enters the tree.
var touch_available := DisplayServer.is_touchscreen_available()
var _choices: Array[Dictionary] = []  # {button, field, value}, kept in step with Settings
var _mouse: CheckButton
var _diagram: Diagram
var _values := {}  # action -> Label
var _capturing: StringName = &""
var _replace := false


## Shows the Controls overlay under `parent`.
static func open(parent: Node) -> Overlay:
	var o := Overlay.open(parent, "Controls")
	var screen := ControlsScreen.new()
	screen.name = "ControlsScreen"
	o.body.add_child(screen)
	return o


func _init() -> void:
	custom_minimum_size.x = Overlay.WIDTH
	add_theme_constant_override("separation", 14)


func _ready() -> void:
	if touch_available:
		var touch := _row("Touch")
		_choice(touch, "touch_scheme", [["One finger", "finger"], ["Stick + button", "stick"], ["Finger + button", "finger_button"]])
		_diagram = Diagram.new()
		touch.add_child(_diagram)
		_choice(_row("On-screen fire button"), "fire_side", [["Left side", "left"], ["Right side", "right"]])
	_mouse = CheckButton.new()
	_mouse.text = "Mouse cursor aims; a button fires"
	_mouse.add_theme_font_size_override("font_size", 26)
	_mouse.toggled.connect(func(on: bool): Settings.mouse_aims = on)
	_mouse.toggled.connect(func(_on: bool): Sfx.play("tap"))
	add_child(_mouse)
	_choice(_row("Gamepad"), "pad_preset", [["Left stick + A", "a"], ["Right stick + D-pad up", "b"]], Settings.apply_pad_preset)
	for action in Settings.ACTIONS:
		var row := _row(String(action).replace("_", " ").capitalize(), 190)
		var value := Label.new()
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size.x = 420
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.add_theme_font_size_override("font_size", 20)
		row.add_child(value)
		_values[action] = value
		row.add_child(_button("Change", capture.bind(action, true)))
		row.add_child(_button("Add", capture.bind(action, false)))
	add_child(_button("Reset to defaults", _reset))
	Settings.changed.connect(_refresh)
	_refresh()


## The next key, mouse button or gamepad button press binds to `action`: with `replace`, in
## place of its bindings of that kind; otherwise as one more. Esc cancels.
func capture(action: StringName, replace: bool) -> void:
	_capturing = action
	_replace = replace
	_refresh()


func _input(event: InputEvent) -> void:
	if _capturing == &"" or not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return  # the wheel scrolls the list; it never binds
	get_viewport().set_input_as_handled()
	var action := _capturing
	_capturing = &""
	if event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		_refresh()
		return
	var binding := _binding(event)
	var events: Array[InputEvent] = []
	for old in InputMap.action_get_events(action):
		if not (_replace and old.get_class() == binding.get_class()):
			events.append(old)
	events.append(binding)
	Settings.set_events(action, events)
	Sfx.play("tap")


## A clean binding for `event`: nothing of the press itself (position, pressed) is stored.
func _binding(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := InputEventKey.new()
		key.physical_keycode = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return key
	if event is InputEventMouseButton:
		var button := InputEventMouseButton.new()
		button.button_index = event.button_index
		return button
	var pad := InputEventJoypadButton.new()
	pad.button_index = event.button_index
	return pad


func _refresh() -> void:
	for choice in _choices:
		choice.button.set_pressed_no_signal(Settings.get(choice.field) == choice.value)
	_mouse.set_pressed_no_signal(Settings.mouse_aims)
	if _diagram:
		_diagram.queue_redraw()
	for action in _values:
		_values[action].text = PROMPT if action == _capturing else ", ".join(InputMap.action_get_events(action).map(_name))


func _name(event: InputEvent) -> String:
	return event.as_text_physical_keycode() if event is InputEventKey and event.physical_keycode != KEY_NONE else event.as_text()


func _row(title: String, label_width := 150) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = label_width
	label.add_theme_font_size_override("font_size", 26)
	row.add_child(label)
	add_child(row)
	return row


func _reset() -> void:
	_capturing = &""
	Settings.reset_controls()


## Toggle buttons in a group, one per `[text, value]`; `set_value` defaults to assigning `field`.
func _choice(row: Control, field: String, options: Array, set_value := Callable()) -> void:
	var group := ButtonGroup.new()
	for option in options:
		var button := Button.new()
		button.text = option[0]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 52
		button.add_theme_font_size_override("font_size", FONT)
		button.pressed.connect(Sfx.play.bind("tap"))
		button.pressed.connect(set_value.bind(option[1]) if set_value.is_valid() else Settings.set.bind(field, option[1]))
		row.add_child(button)
		_choices.append({button = button, field = field, value = option[1]})


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 52)
	button.add_theme_font_size_override("font_size", FONT)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(on_press)
	return button


## A 240×120 sketch of a phone held sideways, showing the chosen touch layout.
class Diagram extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(240, 120)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Style.INK_DIM, false, 2.0)
		var fire_x := 40.0 if Settings.fire_side == "left" else 200.0
		var other_x := 240.0 - fire_x
		var fire := Color(Style.ACCENT, 0.6)
		match Settings.touch_scheme:
			"stick":
				draw_line(Vector2(120, 0), Vector2(120, 120), Style.INK_DIM, 1.0)
				draw_arc(Vector2(other_x, 60), 36.0, 0.0, TAU, 32, Style.INK, 2.0)
				draw_circle(Vector2(other_x, 60), 14.0, Color(Style.INK, 0.5))
				draw_circle(Vector2(fire_x, 60), 28.0, fire)
			"finger_button":
				draw_circle(Vector2(fire_x, 82), 28.0, fire)
				draw_circle(Vector2(other_x, 40), 14.0, Color(Style.INK, 0.5))
			_:
				draw_circle(Vector2(120, 60), 14.0, Color(Style.INK, 0.5))
