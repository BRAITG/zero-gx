class_name Hud
extends CanvasLayer
## Fuel and health bars, always-visible Restart and Menu buttons, and the end-of-level panel.

signal retry_requested
signal menu_requested

var ship: Ship
var restart_button: Button
var _fuel: ProgressBar
var _health: ProgressBar
var _result: PanelContainer
var _result_label: Label


func _ready() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 16)
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	_fuel = _bar(top, "Fuel", Color("#ffcf4a"), Ship.MAX_FUEL)
	_health = _bar(top, "Hull", Color("#5be37d"), Ship.MAX_HEALTH)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	restart_button = _button(top, "Restart", retry_requested.emit)
	_button(top, "Menu", menu_requested.emit)

	_result = PanelContainer.new()
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.hide()
	add_child(_result)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_result.add_child(column)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 40)
	column.add_child(_result_label)
	_button(column, "Retry", retry_requested.emit)
	_button(column, "Menu", menu_requested.emit)


func _process(_delta: float) -> void:
	if ship:
		_fuel.value = ship.fuel
		_health.value = ship.health


func show_result(won: bool) -> void:
	_result_label.text = "Course clear" if won else "Lost"
	_result.reset_size()
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.show()


func _bar(parent: Control, title: String, color: Color, maximum: float) -> ProgressBar:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = maximum
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 24)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button
