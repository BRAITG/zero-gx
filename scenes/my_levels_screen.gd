class_name MyLevelsScreen
extends Control
## The player's own levels: one status row each. A row opens the level's sheet (edit, play, publish, export, delete); New level and Import are in the header.

const MENU := "res://scenes/main.tscn"
const ROW_HEIGHT := 100
const FIX_COLOR := Color("#ff8a6a")

## Set only by a won Publish test flight; opening the screen never submits it.
var confirm_publish_id := ""

var _column: VBoxContainer
var _list: VBoxContainer
var _statuses := {}  # community level id → Community.statuses()
var _busy := false  # a submission is on its way


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Starfield.new())
	var ui := CanvasLayer.new()
	add_child(ui)
	var frame := Style.menu_frame(ui)
	_column = VBoxContainer.new()
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	_column.add_theme_constant_override("separation", 16)
	frame.add_child(_column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	_column.add_child(top)
	_button(top, "Back", func() -> void: get_tree().change_scene_to_file(MENU))
	var title := Label.new()
	title.text = "My levels"
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 36)
	top.add_child(title)
	_primary(_button(top, "New level", func() -> void: _edit(MyLevels.new_id())))
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
		_publish.call_deferred(confirm_publish_id, true)


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
		_add_row(id)


## A level's row: the whole row is one button that opens the level's sheet.
func _add_row(id: String) -> void:
	var data := MyLevels.load_level(id)
	var button := Button.new()
	button.name = "Row"
	button.custom_minimum_size.y = ROW_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(_open_sheet.bind(id))
	_list.add_child(button)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	content.add_theme_constant_override("separation", 16)
	button.add_child(content)
	var thumbnail := Thumbnail.of_sketch(LevelFormat.sketch(data))
	thumbnail.custom_minimum_size = Vector2(128, 72)
	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(thumbnail)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2)
	content.add_child(text)
	text.add_child(_label(str(data.get("title", "?")), 24, Style.INK))
	var status := _status_line(id, data)
	text.add_child(_label(status[0], 20, status[1]))


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## [text, colour] of a level's one status line. Desktop builds (no Community) know only the first three states.
func _status_line(id: String, data: Dictionary) -> Array:
	var problems := LevelFormat.validate(data)
	if not problems.is_empty():
		return ["Needs fixes: " + problems[0], FIX_COLOR]
	if Community.available():
		var status: Dictionary = _statuses.get(Community.level_id_of(id), {})
		match status.get("status"):
			"open":
				return ["In review", Style.INK_DIM]
			"rejected":
				return ["Rejected: " + status.comment if status.get("comment", "") != "" else "Rejected", FIX_COLOR]
			"approved":
				return [_published_line(data, status), Style.INK_DIM]
		if MyLevels.is_submitted(id):
			return ["Submitted", Style.INK_DIM]  # the server's word has not come yet, or cannot be reached
	if MyLevels.is_completed(id):
		return ["Ready to publish", Hud.GOAL_GREEN]
	return ["Not tested yet", Style.INK_DIM]


## "Published v2 · Hard · 64 players · ♥ 42"; a part the status lacks (offline, no stats) is left out, and an edited draft says so instead of the numbers.
func _published_line(data: Dictionary, status: Dictionary) -> String:
	var parts := ["Published v%d" % int(status.get("version", 1))]
	if status.has("sha256") and LevelFormat.sha256(data) != status.sha256:
		return parts[0] + " · edited since"
	var chip := DifficultyChip.text_of(status)  # "Rated Hard": the source word is the chip's, the line keeps the label
	if chip != "":
		parts.append(chip.get_slice(" ", 1))
	if status.has("starters"):
		parts.append("%d %s" % [status.starters, "player" if status.starters == 1 else "players"])
	if status.has("likes"):
		parts.append("♥ %d" % status.likes)
	return " · ".join(parts)


## Refreshes the statuses from the server where the player is signed in; Community falls back to the last known ones.
func _refresh_statuses() -> void:
	if not Community.available():
		return
	var fresh: Dictionary = await Community.statuses()
	if not is_inside_tree() or fresh == _statuses:
		return
	_statuses = fresh
	_refill()


## The sheet of one level: Edit first, Delete last.
func _open_sheet(id: String) -> void:
	var data := MyLevels.load_level(id)
	var o := Overlay.open(self, str(data.get("title", "?")))
	_primary(_sheet_button(o, "Edit", _edit.bind(id)))
	var play := _sheet_button(o, "Play", func() -> void: Progress.open(id))
	play.disabled = not LevelFormat.validate(data).is_empty()
	if MyLevels.has_demo(id):
		_sheet_button(o, "Watch", _watch.bind(id, data))
	if Community.available() and not MyLevels.is_submitted(id):
		_sheet_button(o, "Publish", _publish.bind(id))
	_sheet_button(o, "Export", _export.bind(id, str(data.get("title", "level"))))
	var delete := _sheet_button(o, "Delete", _confirm_delete.bind(id, str(data.get("title", "?"))))
	for color in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		delete.add_theme_color_override(color, Hud.WARNING)  # danger: still behind its confirmation


## A full-width button of a level sheet; the sheet closes before `action` runs.
func _sheet_button(o: Overlay, text: String, action: Callable) -> Button:
	var button := _button(o.body, text, func() -> void:
		o.close()
		action.call())
	button.custom_minimum_size.x = Overlay.WIDTH
	return button


## The row's primary action, styled as the pressed button.
func _primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button.get_theme_stylebox("pressed"))


## The Publish sheet: 1. prove it, 2. suggest a difficulty, 3. submit. `proven` when a won proof flight just ended. Nothing uploads before Submit.
func _publish(id: String, proven := false) -> void:
	if not Community.available() or not _validate_publish(id):
		return
	var o := Overlay.open(self, "Publish")
	o.paragraph("“%s”" % MyLevels.load_level(id).get("title", "?"), 28, Style.ACCENT)
	var proof := o.card()
	var suggestion := o.card()
	var send := o.card()
	var state := {"proven": proven, "submit": null}  # a lambda copies a bool, so the flags live in a Dictionary
	var option := CommunityLevelDetails.difficulty_option()
	var update := func() -> void:
		state.submit.disabled = not state.proven or CommunityLevelDetails.chosen(option) == ""
	o.paragraph("2. Suggest a difficulty", 24, Style.INK, suggestion)
	suggestion.add_child(option)
	o.paragraph("A moderator chooses the reviewed difficulty. Your suggestion is sent beside the level and does not change it.", 20, Style.INK_DIM, suggestion)
	o.paragraph("3. Submit for review", 24, Style.INK, send)
	o.paragraph("Submit this level and your finishing recording for moderator review. It will not be listed publicly until a moderator approves it.", 20, Style.INK_DIM, send)
	state.submit = _button(send, "Submit for review", _submit.bind(id, o, option), "Submitting…")
	option.item_selected.connect(func(_index: int) -> void: update.call())
	_proof_step(o, proof, id, state, update)
	update.call()


## Step 1 of the Publish sheet: the saved run, or what proves one. Rebuilt when the player takes the previous run.
func _proof_step(o: Overlay, proof: VBoxContainer, id: String, state: Dictionary, update: Callable) -> void:
	for old in proof.get_children():
		proof.remove_child(old)
		old.queue_free()
	o.paragraph("1. Prove it can be finished", 24, Style.INK, proof)
	var fly := Progress.open.bind(id, true, true)
	if state.proven:
		o.paragraph("✓ Saved run", 22, Hud.GOAL_GREEN, proof)
		_button(proof, "Play again", fly)
	elif MyLevels.demo(id) != null:
		_button(proof, "Use previous run", func() -> void:
			state.proven = true
			_proof_step(o, proof, id, state, update)
			update.call())
		_button(proof, "Play again", fly)
	else:
		_button(proof, "Play to prove it", fly)


func _validate_publish(id: String) -> bool:
	var problems := LevelFormat.validate(MyLevels.load_level(id))
	if problems.is_empty():
		return true
	var o := Overlay.open(self, "Cannot publish")
	for problem in problems:
		o.paragraph(problem)
	return false


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


## Back closes the top sheet first; otherwise it returns to the menu.
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
