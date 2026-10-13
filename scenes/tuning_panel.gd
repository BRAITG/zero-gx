class_name TuningPanel
extends Control
## Full-screen slider panel over `Tuning`. Pauses the game while open and swallows every touch.

const FONT_SIZE := 22
const SLIDER_WIDTH := 520.0

var _labels := {}
var _sliders := {}
var _overlays: CheckButton


## Shows the panel on its own top canvas layer under `parent` and pauses the tree.
static func open(parent: Node) -> TuningPanel:
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := TuningPanel.new()
	layer.add_child(panel)
	parent.add_child(layer)
	parent.get_tree().paused = true
	return panel


func close() -> void:
	get_tree().paused = false
	get_parent().queue_free()


## A scene change (Android back) can free an open panel; never leave the next scene paused.
func _exit_tree() -> void:
	get_tree().paused = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.025, 0.05, 0.94)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	rows.add_child(buttons)
	_button(buttons, "Close", close)
	_button(buttons, "Reset", _reset)
	_overlays = CheckButton.new()
	_overlays.text = "Debug overlays"
	_overlays.add_theme_font_size_override("font_size", 24)
	_overlays.button_pressed = Tuning.show_overlays
	_overlays.toggled.connect(func(on: bool): Tuning.set_value("show_overlays", on))
	buttons.add_child(_overlays)
	for key: String in Tuning.RANGES:
		var bounds: Array = Tuning.RANGES[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		rows.add_child(row)
		var slider := HSlider.new()
		slider.name = key
		slider.min_value = bounds[0]
		slider.max_value = bounds[1]
		slider.step = bounds[2]
		slider.value = Tuning.get(key)
		slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 48)
		slider.value_changed.connect(_on_slider.bind(key))
		row.add_child(slider)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		row.add_child(label)
		_sliders[key] = slider
		_labels[key] = label
		_show(key)


func _on_slider(value: float, key: String) -> void:
	Tuning.set_value(key, value)
	_show(key)


func _show(key: String) -> void:
	_labels[key].text = "%s: %s" % [key.replace("_", " "), snappedf(Tuning.get(key), 0.0001)]


func _reset() -> void:
	Tuning.reset()
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(Tuning.get(key))
		_show(key)
	_overlays.set_pressed_no_signal(Tuning.show_overlays)


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
