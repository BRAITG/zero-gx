class_name MyLevelsScreen
extends Control
## The player's own levels: make a new one, import or export one, edit, play or delete.

const MENU := "res://scenes/main.tscn"

var _column: VBoxContainer
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	var ui := CanvasLayer.new()
	add_child(ui)
	_column = VBoxContainer.new()
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	_column.add_theme_constant_override("separation", 16)
	ui.add_child(_column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	_column.add_child(top)
	_button(top, "Back", func() -> void: get_tree().change_scene_to_file(MENU))
	var title := Label.new()
	title.text = "My levels"
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 36)
	top.add_child(title)
	_button(top, "New level", func() -> void: _edit(MyLevels.new_id()))
	_button(top, "Import", _import)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	_fill()
	Style.focus_first.call_deferred(_column)  # after layout


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
		label.custom_minimum_size.x = 300  # room for Watch, Edit, Play, Export and Delete
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		_button(row, "Edit", _edit.bind(id))
		if MyLevels.has_demo(id):
			_button(row, "Watch", _watch.bind(id, data))
		var play := _button(row, "Play", func() -> void: Progress.open(id))
		play.disabled = data.is_empty() or not LevelFormat.validate(data).is_empty()
		_button(row, "Export", _export.bind(id, str(data.get("title", "level"))))
		_button(row, "Delete", _confirm_delete.bind(id, str(data.get("title", "?"))))


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
		_fill()
		Style.focus_first(_column))  # the Delete button that had focus is gone


func _import() -> void:
	_file_dialog(false, PackedStringArray(["*.json, *.json.gz ; Zero-GX levels"]), "", func(path: String) -> void:
		var errors := MyLevels.import_file(path)
		if errors.is_empty():
			_fill()
			return
		var o := Overlay.open(self, "Cannot import")
		for error in errors:
			o.paragraph(error))


func _export(id: String, title: String) -> void:
	_file_dialog(true, PackedStringArray(["*.json ; Zero-GX level"]), title.validate_filename() + ".json", func(path: String) -> void:
		if MyLevels.export_file(id, path) != OK:
			Overlay.open(self, "Cannot export").paragraph("The file could not be written."))


## A file dialog; `on_pick` gets the chosen path (a `content://` URI on Android). The system's own dialog where there is one, which Android needs; a Godot FileDialog otherwise.
func _file_dialog(save: bool, filters: PackedStringArray, current: String, on_pick: Callable) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var mode := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if save else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		DisplayServer.file_dialog_show("Export level" if save else "Import level", "", current, false, mode, filters, func(status: bool, paths: PackedStringArray, _filter: int) -> void:
			if status and not paths.is_empty():
				on_pick.call(paths[0]))
		return
	var dialog := FileDialog.new()  # Linux without a desktop portal
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = filters
	dialog.current_file = current
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		on_pick.call(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_file_dialog()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Android's back gesture, Esc and B return to the menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().change_scene_to_file(MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU)
