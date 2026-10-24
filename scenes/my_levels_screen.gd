class_name MyLevelsScreen
extends Control
## The player's own levels: make a new one, import or export one, edit, play or delete.

const MENU := "res://scenes/main.tscn"

## Set only by a won Publish test flight; opening the screen never submits it.
var confirm_publish_id := ""

var _column: VBoxContainer
var _list: VBoxContainer
var _statuses := {}  # community level id → {status, version, comment}
var _busy := false  # a submission is on its way


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
	scroll.follow_focus = true  # keys and pads reach the rows below the fold
	_column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	_fill()
	_refresh_statuses()
	Style.focus_first.call_deferred(_column)  # after layout
	if confirm_publish_id != "" and Community.available():
		_confirm_publish.call_deferred(confirm_publish_id)


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
		var card := VBoxContainer.new()  # the row, and under it the submission line
		card.add_theme_constant_override("separation", 4)
		_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
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
		var problems := LevelFormat.validate(data)
		var play := _button(row, "Play", func() -> void: Progress.open(id))
		play.disabled = not problems.is_empty()
		_button(row, "Export", _export.bind(id, str(data.get("title", "level"))))
		_button(row, "Delete", _confirm_delete.bind(id, str(data.get("title", "?"))))
		if not problems.is_empty():  # says what to fix, so a draft that cannot be played is not a mystery
			var reason := Label.new()
			reason.text = "⚠ Cannot play: " + problems[0] + ("  (+%d more)" % (problems.size() - 1) if problems.size() > 1 else "")
			reason.add_theme_font_size_override("font_size", 20)
			reason.add_theme_color_override("font_color", Color("#ff8a6a"))
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_child(reason)
		if Community.available():
			_submission_line(card, id)


## Under a row: review status and Publish for a draft not submitted as it is now.
func _submission_line(card: VBoxContainer, id: String) -> void:
	var submitted := MyLevels.is_submitted(id)
	var text := _status_text(Community.level_id_of(id))
	if text == "" and submitted:
		text = "Submitted"  # the server's word has not come yet, or cannot be reached
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Style.INK_DIM)
	label.custom_minimum_size.x = 300  # lines up with the title above
	line.add_child(label)
	if not submitted:
		_button(line, "Publish", _publish.bind(id))


func _status_text(community_id: String) -> String:
	var status: Dictionary = _statuses.get(community_id, {})
	match status.get("status"):
		"open":
			return "Pending"
		"approved":
			return "Approved v%d" % int(status.get("version", 1))
		"rejected":
			return "Rejected: " + status.comment if status.get("comment", "") != "" else "Rejected"
	return ""


## Refreshes the statuses from the server where the player is signed in; Community falls back to the last known ones.
func _refresh_statuses() -> void:
	if not Community.available():
		return
	var fresh: Dictionary = await Community.statuses()
	if not is_inside_tree() or fresh == _statuses:
		return
	_statuses = fresh
	_refill()


func _publish(id: String) -> void:
	if not Community.available() or not _validate_publish(id):
		return
	var o := Overlay.open(self, "Publish level")
	o.paragraph("A finishing recording proves this level can be completed.")
	if MyLevels.demo(id) != null:
		_button(o.body, "Use previous run", func() -> void:
			o.close()
			_confirm_publish(id))
		_button(o.body, "Play again", Progress.open.bind(id, true, true))
	else:
		_button(o.body, "Play to prove it", Progress.open.bind(id, true, true))


func _validate_publish(id: String) -> bool:
	var problems := LevelFormat.validate(MyLevels.load_level(id))
	if problems.is_empty():
		return true
	var o := Overlay.open(self, "Cannot publish")
	for problem in problems:
		o.paragraph(problem)
	return false


func _confirm_publish(id: String) -> void:
	var o := Overlay.open(self, "Publish level")
	o.paragraph("Submit this level and your finishing recording for moderator review. It will not be listed publicly until a moderator approves it.")
	var suggestion := o.card()
	o.paragraph("Suggested difficulty", 22, Style.INK, suggestion)
	var option := CommunityLevelDetails.difficulty_option()
	suggestion.add_child(option)
	o.paragraph("A moderator chooses the reviewed difficulty. Your suggestion is sent beside the level and does not change it.", 20, Style.INK_DIM, suggestion)
	var submit := _button(o.body, "Submit for review", _submit.bind(id, o, option), "Submitting…")
	submit.disabled = true  # until a difficulty is chosen
	option.item_selected.connect(func(_index: int) -> void: submit.disabled = CommunityLevelDetails.chosen(option) == "")


func _submit(id: String, confirmation: Overlay, option: OptionButton) -> void:
	var difficulty := CommunityLevelDetails.chosen(option) if is_instance_valid(option) else ""
	if _busy or difficulty == "" or not Community.available() or not _validate_publish(id):
		return
	_busy = true
	var error: String = await Community.submit(id, difficulty)
	_busy = false
	if not is_inside_tree():
		return
	if error != "":
		Overlay.open(self, "Cannot submit").paragraph(error)
		return
	_statuses[Community.level_id_of(id)] = {"status": "open"}  # until the server's own word at the next refresh
	if is_instance_valid(confirmation):
		confirmation.close()
	_refill.call_deferred()  # not from inside the confirmation button's own signal


## Rebuilds the rows after a change that is not theirs; focus goes to the first button when the rows that held it are gone.
func _refill() -> void:
	_fill()
	if get_viewport().gui_get_focus_owner() == null:
		Style.focus_first(_column)


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


## `busy`, if given, is what the button says (and it stays off) while `action`, a coroutine, runs.
func _button(parent: Control, text: String, action: Callable, busy := "") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action if busy == "" else Style.busy.bind(button, busy, action))
	parent.add_child(button)
	return button


## Back closes the top Publish sheet first; otherwise it returns to the menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var sheets := find_children("*", "Overlay", true, false)
		if sheets.is_empty():
			get_tree().change_scene_to_file(MENU)
		else:
			sheets.back().close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(MENU)
