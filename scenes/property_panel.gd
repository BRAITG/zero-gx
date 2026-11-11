class_name EditorPropertyPanel
extends PanelContainer

signal value_changed(field: String, value: float)
signal close_requested

var _scroll: ScrollContainer
var _content: VBoxContainer
var _rows: VBoxContainer


func build(title: String, help: String, width: float, row_height: float, font_size: int, small_font_size: int) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = width
	add_theme_stylebox_override("panel", _panel_style())
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	column.add_child(heading)
	var name := Label.new()
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_override("font", Style.display_font)
	name.add_theme_font_size_override("font_size", font_size)
	heading.add_child(name)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(row_height * 1.4, row_height)
	close.add_theme_font_size_override("font_size", font_size)
	close.pressed.connect(Sfx.play.bind("tap"))
	close.pressed.connect(func() -> void: close_requested.emit())
	heading.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	column.add_child(scroll)
	_scroll = scroll
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)
	if not help.is_empty():
		var description := Label.new()
		description.text = help
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_color_override("font_color", Style.INK_DIM)
		description.add_theme_font_size_override("font_size", small_font_size)
		_content.add_child(description)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_content.add_child(_rows)


func preferred_height() -> float:
	return get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y + _content.get_combined_minimum_size().y


func reveal_focused_control() -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus) or not is_ancestor_of(focus):
		return
	var target: Control = focus
	while not _scroll.is_ancestor_of(target):
		var parent: Node = target.get_parent()
		if not parent is Control:
			return
		target = parent as Control
	_scroll.ensure_control_visible(target)
	var visible: Rect2 = _scroll.get_global_rect()
	var focused: Rect2 = focus.get_global_rect()
	if focused.position.y < visible.position.y:
		_scroll.scroll_vertical -= ceili(visible.position.y - focused.position.y)
	elif focused.end.y > visible.end.y:
		_scroll.scroll_vertical += ceili(focused.end.y - visible.end.y)




func add_numeric(field: String, label: String, bounds: Vector2, step: float, value: float, row_height: float, font_size: int, number_box_factory: Callable) -> void:
	if not label.is_empty():
		var caption := Label.new()
		caption.text = label
		caption.add_theme_font_size_override("font_size", font_size)
		_rows.add_child(caption)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	_rows.add_child(row)
	var slider := HSlider.new()
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = step
	slider.value = clampf(value, bounds.x, bounds.y)
	slider.custom_minimum_size = Vector2(maxf(140.0, row_height * 1.75), row_height)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.add_theme_font_size_override("font_size", font_size)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#33445D")
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.set_corner_radius_all(4)
	slider.add_theme_stylebox_override("slider", track)
	var filled := StyleBoxFlat.new()
	filled.bg_color = Style.ACCENT
	filled.set_corner_radius_all(4)
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", filled)
	row.add_child(slider)
	var box: SpinBox = number_box_factory.call(slider) as SpinBox
	row.add_child(box)
	slider.value_changed.connect(func(changed: float) -> void: value_changed.emit(field, changed))




func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#080E1D")
	style.border_color = Style.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	return style
