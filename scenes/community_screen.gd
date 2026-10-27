class_name CommunityScreen
extends Control
## Levels other players shared: the Top and New lists, 50 a page, each with Play, which downloads the level first. Account actions live in Community settings.

const MENU := "res://scenes/main.tscn"
const PAGE_SIZE := 50  # the server's page size: a shorter page is the last one

var _column: VBoxContainer
var _note: Label
var _rows: VBoxContainer
var _more: Button
var _sort := "top"
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
	var tabs := ButtonGroup.new()
	for sort: String in ["top", "new"]:
		var tab := _button(top, sort.capitalize(), _load.bind(sort, 0))
		tab.toggle_mode = true
		tab.button_group = tabs
		tab.button_pressed = sort == _sort
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_button(top, "Settings", _open_settings)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 24)
	_note.add_theme_color_override("font_color", Style.INK_DIM)
	_column.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # keys and pads reach the rows below the fold
	_column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	content.add_child(_rows)
	_more = _button(content, "More", func() -> void: await _load(_sort, _page + 1), "Loading…")
	_more.hide()
	_load(_sort, 0)
	Style.focus_first.call_deferred(_column)  # after layout


## Shows page `page` of `sort`: page 0 replaces the rows, a later page adds to them.
func _load(sort: String, page: int) -> void:
	_request += 1
	var mine := _request
	if page == 0:
		_sort = sort
		for old in _rows.get_children():
			old.free()
		_more.hide()
	_note.text = "Loading…"
	var reply: Dictionary = await Community.list(sort, page)
	if mine != _request or not is_inside_tree():
		return
	var rows: Array = reply.rows
	var first: Button
	for row: Variant in rows:
		if row is Dictionary and row.get("level_id") is String and row.get("sha256") is String:
			var play := _add_row(row)
			first = first if first else play
	if not reply.has("error"):
		_note.text = "" if _rows.get_child_count() > 0 else "No levels yet."
	elif reply.offline and not rows.is_empty():
		_note.text = "You are offline"
	else:
		_note.text = reply.error
	if not (reply.has("error") and rows.is_empty()):  # a page that failed leaves the page and More as they were
		_page = page
		_more.visible = rows.size() >= PAGE_SIZE
	var focus := get_viewport().gui_get_focus_owner()
	if first and (focus == null or focus == _more):  # the button that had focus is gone or has been used
		first.grab_focus(true)


func _add_row(row: Dictionary) -> Button:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	_rows.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var thumbnail := Thumbnail.of_sketch(row.get("sketch"))
	thumbnail.custom_minimum_size = Vector2(164, 92)  # 16:9 at an official row's thumbnail height
	line.add_child(thumbnail)
	var label := Label.new()
	label.text = "%s · v%d · by %s · ♥ %d" % [row.get("title", "?"), int(row.get("latest", 1)), row.get("author", "?"), int(row.get("likes", 0))]
	label.add_theme_font_size_override("font_size", 24)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	var medal := Progress.medal(Progress.best_points(Community.STAGE_PREFIX + row.sha256), Community.par_of(row))
	if medal != Progress.Medal.NONE:
		var icon := ScoreIcon.new(ScoreIcon.Kind.MEDAL, medal)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(icon)
	var details := _button(line, "Details", _details.bind(row))
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var play := _button(line, "Play", _play.bind(row), "Loading…")
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ratings := Label.new()  # Reviewed and Community side by side, each its own value
	ratings.text = CommunityLevelDetails.summary(row)
	ratings.add_theme_font_size_override("font_size", 20)
	ratings.add_theme_color_override("font_color", Style.INK_DIM)
	ratings.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(ratings)
	return play


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
	o.paragraph("This removes your scores, likes, reports and your name from Zero-GX's servers. Levels you shared stay, shown as by Deleted player.")
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
