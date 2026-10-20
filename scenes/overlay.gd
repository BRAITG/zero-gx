class_name Overlay
extends Control
## A full-screen panel over the menu: a title, a scrolling body and a Close button.
## Touches never pass through it.

const WIDTH := 1000.0

## Add rows to this.
var body: VBoxContainer

var _close: Button
var _prior_focus: Control  # what had focus before the overlay opened


## Shows a new overlay titled `title` on its own top layer under `parent`, with focus on Close.
static func open(parent: Node, title: String) -> Overlay:
	var layer := CanvasLayer.new()
	layer.layer = 10
	var overlay := Overlay.new()
	overlay._prior_focus = parent.get_viewport().gui_get_focus_owner()
	overlay._build(title)
	layer.add_child(overlay)
	parent.add_child(layer)
	overlay._close.grab_focus(true)
	return overlay


## Closes, handing focus back to what had it before.
func close() -> void:
	if is_instance_valid(_prior_focus) and _prior_focus.is_visible_in_tree():
		_prior_focus.grab_focus(true)
	get_parent().queue_free()


## Esc and B close it. `_unhandled_input`: events a control already used (a key capture) never get here.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("tap")
		close()


## A wrapped paragraph in the body.
func paragraph(text: String, size := 22, color := Style.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	body.add_child(label)
	return label


func heading(text: String) -> Label:
	var label := paragraph(text, 28, Style.ACCENT)
	label.add_theme_font_override("font", Style.display_font)
	return label


func _build(title: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.025, 0.05, 0.96)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	column.add_child(top)
	_close = Button.new()
	_close.text = "Close"
	_close.custom_minimum_size = Vector2(160, 56)
	_close.pressed.connect(Sfx.play.bind("tap"))
	_close.pressed.connect(close)
	top.add_child(_close)
	var heading_label := Label.new()
	heading_label.text = title
	heading_label.add_theme_font_override("font", Style.display_font)
	heading_label.add_theme_font_size_override("font_size", 36)
	top.add_child(heading_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # keys and pads reach the rows below the fold
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
