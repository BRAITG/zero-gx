class_name MyLevelsScreen
extends Control
## The player's own levels: make a new one, edit, play or delete.

const MENU := "res://scenes/main.tscn"

var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	var ui := CanvasLayer.new()
	add_child(ui)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	column.add_theme_constant_override("separation", 16)
	ui.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	column.add_child(top)
	_button(top, "Back", func() -> void: get_tree().change_scene_to_file(MENU))
	var title := Label.new()
	title.text = "My levels"
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 36)
	top.add_child(title)
	_button(top, "New level", func() -> void: _edit(MyLevels.new_id()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	_fill()


func _fill() -> void:
	for old in _list.get_children():
		old.free()
	var ids := MyLevels.ids()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "No levels yet. Tap New level to build one."
		empty.add_theme_color_override("font_color", Style.INK_DIM)
		empty.add_theme_font_size_override("font_size", 24)
		_list.add_child(empty)
	for id in ids:
		var data := MyLevels.load_level(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_list.add_child(row)
		var label := Label.new()
		var best := Progress.best_points(id)
		label.text = "%s%s · %s" % ["✓ " if MyLevels.is_completed(id) else "", data.get("title", "?"), "—" if best < 0 else str(best)]
		label.add_theme_font_size_override("font_size", 24)
		label.custom_minimum_size.x = 460  # room for Watch beside Edit, Play and Delete
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		_button(row, "Edit", _edit.bind(id))
		if MyLevels.has_demo(id):
			_button(row, "Watch", _watch.bind(id, data))
		var play := _button(row, "Play", func() -> void: Progress.open(id))
		play.disabled = data.is_empty() or not LevelFormat.validate(data).is_empty()
		_button(row, "Delete", _confirm_delete.bind(id, data.get("title", "?")))


func _edit(id: String) -> void:
	get_tree().change_scene_to_node(LevelEditor.create(id))


func _watch(id: String, data: Dictionary) -> void:
	var demo := MyLevels.demo(id)
	if demo == null:  # a file that passed the header check but does not decode
		_fill()
		return
	var tree := get_tree()
	tree.change_scene_to_node(DemoViewer.create(data, demo, func() -> void: tree.change_scene_to_node(MyLevelsScreen.new())))


func _confirm_delete(id: String, title: String) -> void:
	var o := Overlay.open(self, "Delete level?")
	o.paragraph("“%s” will be gone for good." % title)
	_button(o.body, "Delete", func() -> void:
		MyLevels.delete(id)
		o.close()
		_fill())


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Android's back gesture returns to the menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().change_scene_to_file(MENU)
