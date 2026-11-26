class_name MyLevelsScreen
extends Control
## The player's own levels: one status card each, with More (sheet), Edit and Play buttons; New level and Import are in the header.

const MENU := "res://scenes/main.tscn"
const LIST_WIDTH := 900.0
const ROW_HEIGHT := 100
const ROW_MARGIN := 8
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
	top.custom_minimum_size.x = LIST_WIDTH
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(top)
	Style.subtle(_button(top, "Back", func() -> void: get_tree().change_scene_to_file(MENU)))
	var title := Label.new()
	title.text = "My levels"
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 36)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	Style.subtle(_button(top, "Import", _import))
	Style.primary(_button(top, "New level", func() -> void: _edit(MyLevels.new_id())))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = LIST_WIDTH
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


## A level's row card: thumbnail, title + status pill, and explicit More / Edit / Play buttons.
func _add_row(id: String) -> void:
	var data := MyLevels.load_level(id)
	var card := PanelContainer.new()
	card.name = "Row"
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.custom_minimum_size.y = ROW_HEIGHT
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	var card_box := Style.box(Style.PANEL, Style.BORDER_SOFT, 12, 12)
	card_box.content_margin_top = ROW_MARGIN
	card_box.content_margin_bottom = ROW_MARGIN
	card.add_theme_stylebox_override("panel", card_box)
	_list.add_child(card)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 16)
	card.add_child(content)
	var thumbnail := Thumbnail.of_sketch(LevelFormat.sketch(data))
	thumbnail.custom_minimum_size = Vector2(128, 72)
	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(thumbnail)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	content.add_child(text)
	text.add_child(_label(str(data.get("title", "?")), 24, Style.INK))
	text.add_child(_status_badges(id, data))
	var actions := HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var more := Style.subtle(_button(actions, "More", _open_sheet.bind(id)))
	more.name = "More"
	more.custom_minimum_size = Vector2(88, 52)
	var edit := Style.subtle(_button(actions, "Edit", _edit.bind(id)))
	edit.name = "Edit"
	edit.custom_minimum_size = Vector2(80, 52)
	var play := Style.primary(_button(actions, "Play", func() -> void: Progress.open(id)))
	play.name = "Play"
	play.custom_minimum_size = Vector2(92, 52)
	play.disabled = not LevelFormat.validate(data).is_empty()


## Color-coded status pill (with optional detail text beside it) for a My Levels row.
func _status_badges(id: String, data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	var parts := _status_parts(id, data)
	row.add_child(Style.pill(parts.pill, parts.color, 18))
	if parts.detail != "":
		var extra := _label(parts.detail, 18, parts.detail_color)
		extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(extra)
	return row


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## Structured status for a level: {pill, detail, separator, color, detail_color, sheet_color}.
func _status_parts(id: String, data: Dictionary) -> Dictionary:
	var problems := LevelFormat.validate(data)
	if not problems.is_empty():
		return {"pill": "Needs fixes", "detail": problems[0], "separator": ": ", "color": FIX_COLOR, "detail_color": FIX_COLOR, "sheet_color": FIX_COLOR}
	if Community.available():
		var status: Dictionary = _statuses.get(Community.level_id_of(id), {})
		match status.get("status"):
			"open":
				return {"pill": "In review", "detail": "", "separator": "", "color": Style.AMBER, "detail_color": Style.INK_DIM, "sheet_color": Style.INK_DIM}
			"rejected":
				var raw_comment: Variant = status.get("comment")
				var comment: String = raw_comment if raw_comment is String else ""
				return {"pill": "Rejected", "detail": comment, "separator": ": ", "color": FIX_COLOR, "detail_color": FIX_COLOR, "sheet_color": FIX_COLOR}
			"approved":
				var version := "Published v%d" % int(status.get("version", 1))
				var detail := _published_detail(data, status)
				return {"pill": version, "detail": detail, "separator": " · ", "color": Hud.GOAL_GREEN, "detail_color": Style.INK_DIM, "sheet_color": Style.INK_DIM}
		if MyLevels.is_submitted(id):
			return {"pill": "Submitted", "detail": "", "separator": "", "color": Style.AMBER, "detail_color": Style.INK_DIM, "sheet_color": Style.INK_DIM}
	if MyLevels.is_completed(id):
		return {"pill": "Ready to publish", "detail": "", "separator": "", "color": Hud.GOAL_GREEN, "detail_color": Style.INK_DIM, "sheet_color": Hud.GOAL_GREEN}
	return {"pill": "Not tested yet", "detail": "", "separator": "", "color": Style.INK_DIM, "detail_color": Style.INK_DIM, "sheet_color": Style.INK_DIM}


## [text, colour] of a level's one status line for the detail sheet.
func _status_line(id: String, data: Dictionary) -> Array:
	var parts := _status_parts(id, data)
	var text: String = parts.pill + (parts.separator + parts.detail if parts.detail != "" else "")
	return [text, parts.sheet_color]


## "Hard · 64 players · ♥ 42" or "edited since" after Published vN.
func _published_detail(data: Dictionary, status: Dictionary) -> String:
	if status.has("sha256") and LevelFormat.sha256(data) != status.sha256:
		return "edited since"
	var parts: Array[String] = []
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
	var o := Overlay.open(self, str(data.get("title", "?")), false, true)
	var status := _status_line(id, data)
	o.paragraph(status[0], 22, status[1])  # the row cuts a long moderator comment; here it is whole
	Style.primary(_sheet_button(o, "Edit", _edit.bind(id)))
	var play := _sheet_button(o, "Play", func() -> void: Progress.open(id))
	play.disabled = not LevelFormat.validate(data).is_empty()
	if MyLevels.has_demo(id):
		Style.subtle(_sheet_button(o, "Watch", _watch.bind(id, data)))
	if Community.available() and not MyLevels.is_submitted(id):
		_sheet_button(o, "Publish", _publish.bind(id)).disabled = play.disabled  # an invalid draft cannot be published
	Style.subtle(_sheet_button(o, "Export", _export.bind(id, str(data.get("title", "level")))))
	var spacer := Control.new()  # sets the destructive action apart
	spacer.custom_minimum_size.y = 24
	o.body.add_child(spacer)
	Style.danger(_sheet_button(o, "Delete", _confirm_delete.bind(id, str(data.get("title", "?")))))


## A problem as a sentence: the validator's start in lower case.
static func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


## A full-width button of a level sheet; the sheet closes before `action` runs.
func _sheet_button(o: Overlay, text: String, action: Callable) -> Button:
	var button := _button(o.body, text, func() -> void:
		o.close()
		action.call())
	button.custom_minimum_size.x = Overlay.WIDTH
	return button


## The Publish sheet: 1. prove it, 2. suggest a difficulty, 3. submit. `proven` when a won proof flight just ended. Nothing uploads before Submit.
func _publish(id: String, proven := false) -> void:
	if not Community.available() or not _validate_publish(id):
		return
	var o := Overlay.open(self, "Publish", false, true)
	o.paragraph("“%s”" % MyLevels.load_level(id).get("title", "?"), 28, Style.ACCENT)
	var proof := o.card()
	var suggestion := o.card()
	var send := o.card()
	var state := {"proven": proven, "difficulty": "", "submit": null}  # a lambda copies values, so flags live in a Dictionary
	var update := func() -> void:
		state.submit.disabled = _busy or not state.proven or state.difficulty == ""
	o.paragraph("2. Suggest a difficulty", 24, Style.INK, suggestion)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 12)
	suggestion.add_child(pills)
	var group := ButtonGroup.new()
	for difficulty: String in CommunityLevelDetails.DIFFICULTIES:
		var pick := Style.toggle_tint(_button(pills, difficulty.capitalize(), func() -> void:
			state.difficulty = difficulty
			update.call()), DifficultyChip.COLORS[difficulty])
		pick.toggle_mode = true
		pick.button_group = group
	o.paragraph("A moderator chooses the reviewed difficulty. Your suggestion is sent beside the level and does not change it.", 20, Style.INK_DIM, suggestion)
	o.paragraph("3. Submit for review", 24, Style.INK, send)
	o.paragraph("Submit this level and your finishing recording for moderator review. It will not be listed publicly until a moderator approves it.", 20, Style.INK_DIM, send)
	state.submit = Style.primary(_button(send, "Submit for review", func() -> void: await _submit(id, o, state.difficulty), "Submitting…"))
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
			update.call()
			proof.find_children("*", "Button", false, false)[0].grab_focus(true))  # the pressed button is gone
		_button(proof, "Play again", fly)
	else:
		_button(proof, "Play to prove it", fly)


func _validate_publish(id: String) -> bool:
	var problems := LevelFormat.validate(MyLevels.load_level(id))
	if problems.is_empty():
		return true
	var o := Overlay.open(self, "Cannot publish", false, true)
	for problem in problems:
		o.paragraph(_sentence(problem))
	return false


func _submit(id: String, confirmation: Overlay, difficulty: String) -> void:
	if _busy or difficulty == "" or not Community.available() or not _validate_publish(id):
		return
	_busy = true
	var error: String = await Community.submit(id, difficulty)
	_busy = false
	if not is_inside_tree():
		return
	if error != "":
		Overlay.open(self, "Cannot submit", false, true).paragraph(error)
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
	var o := Overlay.open(self, "Delete level?", false, true)
	o.paragraph("“%s” will be gone for good." % title)
	var delete := _button(o.body, "Delete", func() -> void:
		MyLevels.delete(id)
		o.close()
		_fill()
		Style.focus_first(_column))  # the Delete button that had focus is gone
	delete.custom_minimum_size.x = Overlay.WIDTH
	Style.danger(delete)


func _import() -> void:
	_file_dialog(false, PackedStringArray(["*.json, *.json.gz ; Zero-GX levels"]), "", func(path: String) -> void:
		var errors := MyLevels.import_file(path)
		if errors.is_empty():
			_fill()
			return
		var o := Overlay.open(self, "Cannot import", false, true)
		for error in errors:
			o.paragraph(_sentence(error)))


func _export(id: String, title: String) -> void:
	_file_dialog(true, PackedStringArray(["*.json ; Zero-GX level"]), title.validate_filename() + ".json", func(path: String) -> void:
		if MyLevels.export_file(id, path) != OK:
			Overlay.open(self, "Cannot export", false, true).paragraph("The file could not be written."))


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
