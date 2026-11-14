class_name Overlay
extends Control
## A full-screen panel over the menu: a title, a scrolling body and a Close button, centred in the
## 16:9 frame like the main menu's column. Touches never pass through it.

const WIDTH := 1000.0

## Add rows to this.
var body: VBoxContainer
## The scrolling area around `body`.
var scroll: ScrollContainer

var _close: Button
var _prior_focus: Control  # what had focus before the overlay opened
var _focus_fallback: Node


## Shows a new overlay titled `title` on its own top layer under `parent`, with focus on Close. An `opaque` overlay hides what is behind it completely.
static func open(parent: Node, title: String, allow_monetization: bool = false, opaque: bool = false) -> Overlay:
	var layer := CanvasLayer.new()
	layer.layer = 10
	var overlay := Overlay.new()
	overlay._prior_focus = parent.get_viewport().gui_get_focus_owner()
	overlay._focus_fallback = parent
	overlay._build(title, opaque)
	layer.add_child(overlay)
	parent.add_child(layer)
	Monetization.set_surface(overlay, allow_monetization)
	MonetizationChrome.ensure_touch_target(overlay._close)
	overlay._close.grab_focus(true)
	return overlay


## Closes, handing focus back to what had it before.
func close() -> void:
	var layer := get_parent()
	if layer == null:
		return
	if is_instance_valid(_prior_focus) and _can_restore_focus(_prior_focus):
		_prior_focus.grab_focus(true)
	else:
		layer.tree_exited.connect(Overlay._restore_focus_after_exit.bind(_prior_focus, _focus_fallback), CONNECT_ONE_SHOT)
	layer.queue_free()


static func _can_restore_focus(control: Control) -> bool:
	return is_instance_valid(control) and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled)


static func _restore_focus_after_exit(prior: Control, fallback: Node) -> void:
	if _can_restore_focus(prior):
		prior.grab_focus(true)
	elif is_instance_valid(fallback):
		Style.focus_first(fallback)


## Esc and B close it. `_unhandled_input`: events a control already used (a key capture) never get here.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("tap")
		close()


## A wrapped paragraph in the body, or inside a card when `parent` is given.
func paragraph(text: String, size := 22, color := Style.INK, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	(parent if parent != null else body).add_child(label)
	return label


## A panelled card in the body that groups one setting with its explanation.
func card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS  # a drag that starts on the card scrolls the sheet
	panel.custom_minimum_size.x = WIDTH
	body.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func heading(text: String) -> Label:
	var label := paragraph(text, 28, Style.ACCENT)
	label.add_theme_font_override("font", Style.display_font)
	return label


func _build(title: String, opaque: bool) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.025, 0.05, 1.0 if opaque else 0.96)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var frame := Style.menu_frame(self)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	column.add_theme_constant_override("separation", 16)
	frame.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	top.custom_minimum_size.x = WIDTH  # the title row and the body share one centred column
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long level title must not push past the column
	top.add_child(heading_label)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # keys and pads reach the rows below the fold
	column.add_child(scroll)
	var centre := CenterContainer.new()  # a ScrollContainer ignores its child's shrink flags
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	centre.add_child(body)
