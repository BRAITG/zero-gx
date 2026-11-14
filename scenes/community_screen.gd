class_name CommunityScreen
extends Control
## Levels other players shared: the Popular and New lists, 50 a page, filtered by difficulty. Each row opens its details; Play beside it downloads the level first. Account actions live in Community settings.

const MENU := "res://scenes/main.tscn"
const PAGE_SIZE := 50  # the server's page size: a shorter page is the last one
const ROW_HEIGHT := 100
const ROW_GAP := 8
const PLACEHOLDERS := 3

var _column: VBoxContainer
var _note: Label
var _rows: VBoxContainer
var _more: Button
var _show_all: Button
var _chips: Array[Button] = []
var _sort := "popular"
var _difficulty := ""  # "" is All
var _page := 0  # the last page that arrived
var _request := 0  # the newest list request; an older answer is dropped
var _busy := false  # a download or the account deletion is under way


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
	_button(top, "Back", _to_menu)
	var title := Label.new()
	title.text = "Community"
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 36)
	top.add_child(title)
	var segments := HBoxContainer.new()  # Popular | New
	segments.add_theme_constant_override("separation", 0)
	top.add_child(segments)
	var tabs := ButtonGroup.new()
	for sort: String in ["popular", "new"]:
		var tab := _button(segments, sort.capitalize(), func() -> void: _load(sort, 0, _difficulty))
		tab.custom_minimum_size.x = 130
		tab.toggle_mode = true
		tab.button_group = tabs
		tab.button_pressed = sort == _sort
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var gear := _button(top, "⚙", _open_settings)
	gear.tooltip_text = "Community settings"
	gear.custom_minimum_size.x = 56
	gear.add_theme_font_size_override("font_size", 32)  # the glyph reads small at the label size
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	_column.add_child(filters)
	var group := ButtonGroup.new()
	for label: String in ["All"] + DifficultyChip.LABELS.map(func(l: String) -> String: return l.capitalize()):
		var chip := _button(filters, label, func() -> void: _load(_sort, 0, "" if label == "All" else label.to_lower()))
		chip.custom_minimum_size.x = 110
		chip.toggle_mode = true
		chip.button_group = group
		chip.button_pressed = label == "All"
		_chips.append(chip)
	_note = Label.new()  # the offline banner, the empty state or the reason a page failed
	_note.add_theme_font_size_override("font_size", 24)
	_note.add_theme_color_override("font_color", Style.INK_DIM)
	_column.add_child(_note)
	_note.hide()
	_show_all = _button(_column, "Show all", func() -> void:
		_chips[0].button_pressed = true
		_chips[0].grab_focus()  # Show all hides itself, and the unfiltered list may come back empty too
		_load(_sort, 0, ""))
	_show_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_show_all.hide()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # keys and pads reach the rows below the fold
	_column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", ROW_GAP)
	scroll.add_child(content)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", ROW_GAP)
	content.add_child(_rows)
	_more = _button(content, "More", func() -> void: await _load(_sort, _page + 1, _difficulty), "Loading…")
	_more.hide()
	_load(_sort, 0, _difficulty)
	Style.focus_first.call_deferred(_column)  # after layout
	Monetization.set_surface(self, true)


func _exit_tree() -> void:
	Monetization.clear_surface(self)


## Shows page `page` of `sort`, only of `difficulty` ("" for all): page 0 replaces the rows once it arrives (placeholders stand in on a first load), a later page adds to them.
func _load(sort: String, page: int, difficulty: String) -> void:
	_request += 1
	var mine := _request
	if page == 0:
		_sort = sort
		_difficulty = difficulty
		_more.hide()
		_show_all.hide()
		_note.hide()
		if _rows.get_child_count() == 0:
			for i in PLACEHOLDERS:
				var placeholder := HBoxContainer.new()  # as wide as a row, with room where Play goes
				placeholder.add_theme_constant_override("separation", 12)
				placeholder.custom_minimum_size.y = ROW_HEIGHT
				var panel := PanelContainer.new()
				panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				placeholder.add_child(panel)
				var gap := Control.new()
				gap.custom_minimum_size.x = 160
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				placeholder.add_child(gap)
				_rows.add_child(placeholder)
	var reply: Dictionary = await Community.list(sort, page, difficulty)
	if mine != _request or not is_inside_tree():
		return
	if page == 0:
		for old in _rows.get_children():
			old.free()
	var rows: Array = reply.rows
	var first: Button
	for row: Variant in rows:
		if row is Dictionary and row.get("level_id") is String and row.get("sha256") is String:
			var play := _add_row(row)
			first = first if first else play
	if not reply.has("error"):
		_note.text = ""
		if _rows.get_child_count() == 0:
			_note.text = "No %s levels yet" % difficulty.capitalize() if difficulty != "" else "No levels yet"
			_show_all.visible = difficulty != ""
	elif reply.offline and not rows.is_empty():
		_note.text = "Offline: showing saved levels"
	else:
		_note.text = reply.error
	_note.visible = _note.text != ""
	if not (reply.has("error") and rows.is_empty()):  # a page that failed leaves the page and More as they were
		_page = page
		_more.visible = rows.size() >= PAGE_SIZE
	var focus := get_viewport().gui_get_focus_owner()
	if first and (focus == null or focus == _more):  # the button that had focus is gone or has been used
		first.grab_focus(true)


## A level row: the whole row button opens the details, and Play is its sibling so each is its own touch target. Returns Play.
func _add_row(row: Dictionary) -> Button:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	_rows.add_child(line)
	var button := Button.new()
	button.name = "Row"
	button.custom_minimum_size.y = ROW_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(_details.bind(row))
	line.add_child(button)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	content.add_theme_constant_override("separation", 16)
	button.add_child(content)
	var thumbnail := Thumbnail.of_sketch(row.get("sketch"))
	thumbnail.custom_minimum_size = Vector2(128, 72)
	thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(thumbnail)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	content.add_child(text)
	text.add_child(_label(row.get("title", "?"), 24, Style.INK, true))
	text.add_child(_label("by %s" % row.get("author", "?"), 18, Style.INK_DIM, true))
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_constant_override("separation", 12)
	text.add_child(meta)
	var chip := DifficultyChip.of(row)
	if chip:
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box: StyleBoxFlat = chip.get_theme_stylebox("panel")
		box.content_margin_top = 1  # three text lines must fit the 100 px row
		box.content_margin_bottom = 1
		meta.add_child(chip)
	meta.add_child(_label("♥ %d" % int(row.get("likes", 0)), 18, Style.INK_DIM))
	var starters := int(row.get("starters", 0))
	meta.add_child(_label("%d %s" % [starters, "player" if starters == 1 else "players"], 18, Style.INK_DIM))
	var own := HBoxContainer.new()  # the player's own status, from this device
	own.mouse_filter = Control.MOUSE_FILTER_IGNORE
	own.alignment = BoxContainer.ALIGNMENT_END
	own.custom_minimum_size.x = 100
	content.add_child(own)
	var medal := Progress.medal(Progress.best_points(Community.STAGE_PREFIX + row.sha256), Community.par_of(row))
	var mine := Community.play_progress(row.sha256)
	var tries := maxi(int(mine.local_attempts), int(mine.confirmed_attempts))
	if medal != Progress.Medal.NONE:
		var icon := ScoreIcon.new(ScoreIcon.Kind.MEDAL, medal)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		own.add_child(icon)
	elif mine.cleared:
		own.add_child(_label("Cleared", 18, Style.INK_DIM))
	elif tries > 0:
		own.add_child(_label("%d %s" % [tries, "try" if tries == 1 else "tries"], 18, Style.INK_DIM))
	var play := _button(line, "Play", _play.bind(row), "Loading…")
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play.add_theme_stylebox_override("normal", play.get_theme_stylebox("pressed"))  # the row's primary action
	return play


func _label(text: String, font_size: int, color: Color, ellipsis := false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if ellipsis:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## The details and rating sheet of this version, with the same Play as the row's.
func _details(row: Dictionary) -> void:
	CommunityLevelDetails.open(self, row, _play.bind(row))


func _play(row: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var error: String = await Community.download(row)
	_busy = false
	if not is_inside_tree():
		return
	if error == "" and not LevelFormat.validate(LevelFormat.read(Community.level_path(row.sha256))).is_empty():
		error = "This level cannot be played."
	if error != "":
		Overlay.open(self, "Cannot play").paragraph(error)
		return
	Progress.open(Community.STAGE_PREFIX + row.sha256)


func _open_settings() -> void:
	var o := Overlay.open(self, "Community settings")
	o.heading("Account")
	if Community.signed_in():
		var deletion := _button(o.body, "Delete my community account", _confirm_delete)
		deletion.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		o.paragraph("Sign in to manage your community account.")


func _confirm_delete() -> void:
	var o := Overlay.open(self, "Delete community account?")
	o.paragraph("This removes your scores, likes, reports, play history, difficulty ratings and your name from Zero-GX's servers. Levels you shared stay, shown as by Deleted player.")
	_button(o.body, "Delete account", _delete_account.bind(o), "Deleting…")


func _delete_account(o: Overlay) -> void:
	if _busy:
		return
	_busy = true
	var error: String = await Community.delete_account()
	_busy = false
	if not is_inside_tree():
		return
	if is_instance_valid(o):
		o.close()
	if error != "":
		Overlay.open(self, "Cannot delete account").paragraph(error)
		return
	_to_menu()


func _to_menu() -> void:
	get_tree().change_scene_to_file(MENU)


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


## Back closes the top account sheet first; without a sheet, it returns to the menu.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var sheets := find_children("*", "Overlay", true, false)
		if sheets.is_empty():
			_to_menu()
		else:
			sheets.back().close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_to_menu()
