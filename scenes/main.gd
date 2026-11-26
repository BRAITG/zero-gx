extends Control
## The main menu, on one of three pages. HOME is the hub: Official levels, Community levels (where
## `Community.available()`), Training, then a smaller row of My levels, Settings and Credits. OFFICIAL
## and TRAINING list their stages in a scrolling column of rows (thumbnail, title, best-score breakdown),
## each locked until the stage before it is finished, under a Back button that returns to HOME.

enum Page { HOME, OFFICIAL, TRAINING }

const SCENE := "res://scenes/main.tscn"
const MENU_DRIFT := Vector2(-40, -12)  # px/s
const HOME_WIDTH := 440.0  # px: the column of home buttons
const LIST_WIDTH := 900.0  # px: centered column for Official / Training header and rows
const ROW_HEIGHT := 108.0  # px: a stage row; its thumbnail fills the height less the margins
const ROW_MARGIN := 8.0

## Which page this scene shows; the main scene opens on HOME.
var page := Page.HOME

var _column: VBoxContainer
var _official: Button  # the home page's primary: it takes focus when HOME opens
var _official_progress: PanelContainer  # progress & medal pill inside _official when >= 1 level cleared
var _official_progress_row: HBoxContainer
var _training_button: Button
var _tally: HBoxContainer  # medal & clear tally in the list header
var _levels: VBoxContainer  # the stage rows of OFFICIAL or TRAINING

var _board_badges := {}  # current bundled hash → its existing row's button
## Set once per run: the menu scene is entered again on every return to it.
static var _sized := false
static var _board_attempts := {}  # owner|hash → monotonic milliseconds; survives list recreation, including failed reads


func _ready() -> void:
	_size_window()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stars := Starfield.new()
	stars.drift = MENU_DRIFT
	add_child(stars)
	var ui := CanvasLayer.new()  # above the bloom: menu text stays crisp while the stars glow
	add_child(ui)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 12)
	Style.menu_frame(ui).add_child(_column)  # the content lives in the safe 16:9 frame
	if page == Page.HOME:
		_build_home()
	else:
		_build_list()
	Progress.changed.connect(_refresh)
	_column.get_parent().resized.connect(_center_column)
	_refresh()
	if page == Page.OFFICIAL and Community.available():
		Community.board_updated.connect(_update_badge)
		Community.identity_changed.connect(_board_identity_changed)
		_refresh_boards()
	Monetization.set_surface(self, page == Page.HOME)
	if page == Page.HOME and get_viewport().gui_get_focus_owner() == null:  # not while an overlay holds it
		_official.grab_focus(true)


func _exit_tree() -> void:
	Monetization.clear_surface(self)

func _build_home() -> void:
	_column.add_child(_title("ZERO-GX"))
	_official = Style.primary(_button("Official levels", Vector2(HOME_WIDTH, 96), 30))
	_official.pressed.connect(_go_to.bind(Page.OFFICIAL))
	_official_progress = PanelContainer.new()
	_official_progress.name = "OfficialProgress"
	_official_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_box := Style.box(Color(0.02, 0.06, 0.14, 0.42), Color.TRANSPARENT, 12, 0, 0)
	pill_box.content_margin_left = 10
	pill_box.content_margin_right = 10
	pill_box.content_margin_top = 2
	pill_box.content_margin_bottom = 2
	_official_progress.add_theme_stylebox_override("panel", pill_box)
	_official_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 8)
	_official_progress.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_official_progress.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_official_progress_row = HBoxContainer.new()
	_official_progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_official_progress_row.add_theme_constant_override("separation", 10)
	_official_progress.add_child(_official_progress_row)
	_official.add_child(_official_progress)
	_column.add_child(_official)
	if Community.available():
		var community := _button("Community levels", Vector2(HOME_WIDTH, 64), 24)
		community.pressed.connect(Style.busy.bind(community, "Signing in…", _open_community))  # the label while the sign-in runs
		_column.add_child(community)
	_training_button = _button("Training", Vector2(HOME_WIDTH, 56), 22)
	_training_button.pressed.connect(_go_to.bind(Page.TRAINING))
	_column.add_child(_training_button)
	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", 12)
	utility.custom_minimum_size.x = HOME_WIDTH
	utility.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(utility)
	var entries := [["My levels", func(): get_tree().change_scene_to_node(MyLevelsScreen.new())], ["Settings", SettingsScreen.open.bind(self)], ["Credits", func(): Credits.open(self)]]
	for entry in entries:  # all share the row's width
		var button := Style.subtle(_button(entry[0], Vector2(0, 44), 18))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		utility.add_child(button)


func _build_list() -> void:
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	_column.add_theme_constant_override("separation", 16)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	top.custom_minimum_size.x = LIST_WIDTH
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(top)
	var back := Style.subtle(_button("Back", Vector2(160, 56), 22))
	back.pressed.connect(_go_to.bind(Page.HOME))
	top.add_child(back)
	var heading := Label.new()
	heading.text = "Official levels" if page == Page.OFFICIAL else "Training"
	heading.add_theme_font_override("font", Style.display_font)
	heading.add_theme_font_size_override("font_size", 36)
	top.add_child(heading)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_tally = HBoxContainer.new()
	_tally.add_theme_constant_override("separation", 12)
	_tally.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_tally)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = LIST_WIDTH
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # keyboard and gamepad navigation scrolls the focused row into view
	_column.add_child(scroll)
	_levels = VBoxContainer.new()
	_levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_levels.add_theme_constant_override("separation", 12)
	scroll.add_child(_levels)


## The first tap signs in, and so does a session saved before its player was stored, to learn who it belongs to. If that fails, the reason shows and the menu stays. Offline it opens anyway: the screen shows what is cached.
func _open_community() -> void:
	if not Community.signed_in() or Community.player_id() == "":
		var error: String = await Community.sign_in()
		if not is_inside_tree():  # the player went elsewhere meanwhile
			return
		if error != "" and error != Community.NO_CONNECTION:
			Overlay.open(self, "Cannot sign in").paragraph(error)
			return
	Community.activate_feedback()  # the explicit entry only: a launch alone never sends reports
	get_tree().change_scene_to_node(CommunityScreen.new())


## Brings the page up to date with the player's progress: the Home progress badges, or the stage buttons on a list.
func _refresh() -> void:
	if page == Page.HOME:
		var completed := Progress.training_completed()
		_training_button.text = "Training · ✓ completed" if completed else "Training"
		_refresh_official_progress()
	else:
		_list_levels()
	_center_column()


func _refresh_official_progress() -> void:
	if _official_progress == null:
		return
	for old in _official_progress_row.get_children():
		old.free()
	var ids := Progress.levels()
	var cleared := 0
	var medals := {Progress.Medal.GOLD: 0, Progress.Medal.SILVER: 0, Progress.Medal.BRONZE: 0}
	for id in ids:
		var best := Progress.best_points(id)
		if best < 0:
			continue
		cleared += 1
		var data := LevelFormat.read(Progress.LEVELS_DIR + id + LevelFormat.EXTENSION)
		var m := Progress.medal(best, int(data.get("par", 0)))
		if medals.has(m):
			medals[m] += 1
	_official_progress.visible = cleared > 0
	Style.set_padding_bottom(_official, 34.0 if cleared > 0 else 12.0)
	if cleared == 0:
		return
	_official_progress_row.add_child(_label("%d / %d cleared" % [cleared, ids.size()], 16, Color(Style.INK, 0.92)))
	_add_medal_pairs(_official_progress_row, medals, 16.0, 16, Color.WHITE, 3)


func _add_medal_pairs(target: HBoxContainer, medals: Dictionary, icon_size: float, font_size: int, color: Color, sep: int) -> void:
	for tier in [Progress.Medal.GOLD, Progress.Medal.SILVER, Progress.Medal.BRONZE]:
		if medals[tier] > 0:
			var pair := HBoxContainer.new()
			pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pair.add_theme_constant_override("separation", sep)
			var icon := ScoreIcon.new(ScoreIcon.Kind.MEDAL, tier, icon_size)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pair.add_child(icon)
			pair.add_child(_label(str(medals[tier]), font_size, color))
			target.add_child(pair)


func _list_levels() -> void:
	for old in _levels.get_children():
		old.free()  # now, not queued: the new rows replace them in the same frame
	_board_badges.clear()
	var training := page == Page.TRAINING
	var suggested: Button
	var ids := Progress.trainings() if training else Progress.levels()
	var cleared := 0
	var medals := {Progress.Medal.GOLD: 0, Progress.Medal.SILVER: 0, Progress.Medal.BRONZE: 0}
	for id in ids:
		var best := Progress.best_points(id)
		var unlocked := Progress.is_unlocked(id)
		var next := suggested == null and unlocked and best < 0
		var data := LevelFormat.read((Progress.TUTORIALS_DIR if training else Progress.LEVELS_DIR) + id + LevelFormat.EXTENSION)
		var par := int(data.get("par", 0))
		if best >= 0:
			cleared += 1
			var m := Progress.medal(best, par)
			if medals.has(m):
				medals[m] += 1
		var label := "Training %s" % id.get_slice("_", 1) if id.begins_with("tutorial_") else id.replace("_", " ").capitalize()
		var sha := LevelFormat.sha256(data) if not training and Community.available() and best >= 0 else ""
		var card := _row(id, "%s · %s" % [label, data.get("title", "")], unlocked, next, par, sha)
		if not unlocked:
			card.modulate = Color(1, 1, 1, 0.55)  # the thumbnail dims with the text
		if next:
			suggested = card.find_child("Play", true, false) as Button
		_levels.add_child(card)
	_update_tally(cleared, ids.size(), medals)
	if get_viewport().gui_get_focus_owner() == null:  # not while an overlay holds it
		if suggested:
			suggested.grab_focus(true)
		else:
			Style.focus_first(_levels)


func _update_tally(cleared: int, total_count: int, medals: Dictionary) -> void:
	if _tally == null:
		return
	for old in _tally.get_children():
		old.free()
	_add_medal_pairs(_tally, medals, 20.0, 20, Style.INK, 4)
	_tally.add_child(_label("%d / %d cleared" % [cleared, total_count], 20, Style.INK_DIM))


## A stage row: a framed card with the thumbnail on the left; the title over one line of the best run's fuel, hull and
## time points (each behind its score icon) in the middle; the medal, best total, optional rank badge, and a primary
## Play button on the right (omitted when locked). Only Play launches the stage.
## The title Label is named "Title" so tests and tools can read the row's name.
func _row(id: String, title: String, unlocked: bool, next: bool, par: int, sha: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Row"
	card.mouse_filter = Control.MOUSE_FILTER_PASS  # dragging anywhere on the card scrolls the list without launching
	card.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_box := Style.box(Color(0.06, 0.13, 0.25, 0.94), Style.ACCENT, 12, 12) if next else Style.box(Style.PANEL, Style.BORDER_SOFT, 12, 12)
	card_box.content_margin_top = ROW_MARGIN
	card_box.content_margin_bottom = ROW_MARGIN
	card.add_theme_stylebox_override("panel", card_box)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 20)
	card.add_child(content)
	var thumbnail := Thumbnail.new(id)
	thumbnail.custom_minimum_size = Vector2(Thumbnail.CANVAS.x / Thumbnail.CANVAS.y, 1.0) * (ROW_HEIGHT - 2 * ROW_MARGIN)
	content.add_child(thumbnail)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(text)
	var name_label := _label(title, 24)
	name_label.name = "Title"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_label)
	var parts := HBoxContainer.new()
	parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parts.add_theme_constant_override("separation", 8)
	text.add_child(parts)
	var best := Progress.best_points(id)
	if not unlocked:
		parts.add_child(_label("Locked", 18, Style.INK_DIM))
	elif best < 0:
		if next:
			parts.add_child(Style.pill("Next", Style.ACCENT, 16))
		parts.add_child(_label("Not played", 18, Style.INK_DIM))
	else:
		var fuel := Progress.best_fuel(id)
		var hull := Progress.best_hull(id)
		for part in [
			[ScoreIcon.Kind.FUEL, "—" if fuel < 0 else "+%d" % roundi(fuel * Tuning.points_fuel)],
			[ScoreIcon.Kind.HULL, "—" if hull < 0 else "+%d" % roundi(hull * Tuning.points_hull)],
			[ScoreIcon.Kind.TIME, "−%d" % roundi(Progress.best_time(id) * Tuning.points_per_second)],
		]:
			var sub_icon := ScoreIcon.new(part[0], Progress.Medal.NONE, 20.0)
			sub_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			parts.add_child(sub_icon)
			var value := _label(part[1], 18, Style.INK_DIM)
			value.custom_minimum_size.x = 70  # the icons line up across rows
			parts.add_child(value)
		var medal := Progress.medal(best, par)
		if medal != Progress.Medal.NONE:
			var icon := ScoreIcon.new(ScoreIcon.Kind.MEDAL, medal)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			content.add_child(icon)
		var total := _label(str(best), 36)
		total.add_theme_font_override("font", Style.display_font)
		total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		total.custom_minimum_size.x = 100  # four digits: the medals line up across rows
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var scores := VBoxContainer.new()
		scores.alignment = BoxContainer.ALIGNMENT_CENTER
		scores.add_theme_constant_override("separation", 0)
		content.add_child(scores)
		scores.add_child(total)
		if sha != "":
			var run := Progress.best_demo(id)
			var local_points := best if run != null and run.level_sha256 == sha else -1
			var badge := _button("", Vector2(100, 28), 16)
			badge.name = "BoardBadge"
			badge.add_theme_stylebox_override("normal", Style.box(Color(Style.ACCENT, 0.14), Color(Style.ACCENT, 0.45), 12, 4))
			badge.add_theme_color_override("font_color", Style.ACCENT.lightened(0.3))
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			badge.size_flags_horizontal = Control.SIZE_SHRINK_END
			badge.clip_text = true
			badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			badge.set_meta("local_points", local_points)
			badge.pressed.connect(func(): Leaderboard.open(self, sha, title, local_points))
			scores.add_child(badge)
			_board_badges[sha] = badge
			_update_badge(sha)
	if unlocked:
		var play := Style.primary(_button("Play", Vector2(110, 52), 20))
		play.name = "Play"
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(func(): Progress.open(id))
		content.add_child(play)
	return card

## Automatic reads never discover an identity; failures also consume this process's per-owner/hash hourly opportunity.
func _refresh_boards() -> void:
	var owner := Community.player_id()
	if owner == "":
		return
	var now := Time.get_ticks_msec()
	for sha: String in _board_badges:
		if Community.player_id() != owner:
			return
		var key := owner + "|" + sha
		if _board_attempts.has(key) and now - int(_board_attempts[key]) < Community.BOARD_CACHE_SECONDS * 1000:
			continue
		_board_attempts[key] = now  # before awaiting: another list can open while this request is held
		_read_automatic_board(sha, key)


## Let Community decide freshness (including private-owner age); a cache-only hit spends no network opportunity.
static func _read_automatic_board(sha: String, key: String) -> void:
	var board: Dictionary = await Community.board(sha)
	if board.get("cached", false) and not board.get("offline", false) and not board.has("error"):
		_board_attempts.erase(key)


func _board_identity_changed(_account: String) -> void:
	for sha: String in _board_badges:
		_update_badge(sha)


## Change only the badge, never the row/focus/scroll. An id-scoped historical best is not a score on this hash.
func _update_badge(sha: String) -> void:
	if not is_inside_tree() or not _board_badges.has(sha):
		return
	var badge: Button = _board_badges[sha]
	var board := Community.cached_board(sha)
	var standing := Leaderboard.standing(board, int(badge.get_meta("local_points"))) if not board.is_empty() else ""
	var text := ""
	if standing.begins_with("Your ranked best · Rank #"):
		text = standing.trim_prefix("Your ranked best · Rank ").get_slice(" ", 0)
	elif standing.begins_with("Estimate: about top "):
		text = "~top " + standing.trim_prefix("Estimate: about top ").get_slice(" · ", 0).trim_suffix(" (cached)")
	elif standing.begins_with("Estimate: would rank #"):
		text = "~≤" + standing.trim_prefix("Estimate: would rank #").get_slice(" ", 0)
	elif standing.begins_with("Estimate: would be in the top 20"):
		text = "~top 20"
	badge.text = text
	badge.tooltip_text = standing
	badge.visible = text != ""



func _label(text: String, font_size: int, color := Style.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Centres the column in the frame on HOME; list pages fill the frame directly.
func _center_column() -> void:
	if page != Page.HOME:
		return
	_column.reset_size()
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _title(text: String) -> Label:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(Style.ACCENT, 0.35))
	title.add_theme_constant_override("outline_size", 14)
	return title


func _button(text: String, min_size := Vector2(300, 52), font_size := 22) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(Sfx.play.bind("tap"))
	return button


## Replaces this page with `target`.
func _go_to(target: Page) -> void:
	get_tree().change_scene_to_node(menu(target))


## The main menu on `target`'s page.
static func menu(target: Page = Page.HOME) -> Control:
	var main: Control = load(SCENE).instantiate()
	main.page = target
	return main


## Desktop only. A 720p window is a quarter of a Retina screen, so it opens at the screen's scale.
func _size_window() -> void:
	if _sized or not OS.has_feature("pc") or DisplayServer.get_name() == "headless":
		return
	_sized = true
	var screen := DisplayServer.window_get_current_screen()
	var dpi_scale := DisplayServer.screen_get_scale(screen)
	if OS.get_name() == "Windows":
		dpi_scale = DisplayServer.screen_get_dpi(screen) / 96.0
	get_window().size = window_size(maxf(dpi_scale, 1.0), DisplayServer.screen_get_usable_rect(screen).size)
	get_window().move_to_center()


## The window size at `scale`: 1280x720 px times it, shrunk in 16:9 to fit 90% of `usable` if larger.
static func window_size(scale: float, usable: Vector2i) -> Vector2i:
	var fitted := Vector2(1280, 720) * scale
	fitted *= minf(1.0, minf(usable.x * 0.9 / fitted.x, usable.y * 0.9 / fitted.y))
	return Vector2i(roundi(fitted.x), roundi(fitted.y))


## project.godot turns off quit_on_go_back so levels can return here: a list goes back to HOME, and HOME quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var sheets := find_children("*", "Overlay", true, false)
		if not sheets.is_empty():
			sheets.back().close()
			return
		if page == Page.HOME:
			get_tree().quit()
		else:
			_go_to(Page.HOME)


## Esc and B go back from a list to HOME; on HOME they do nothing (Esc must not quit).
func _unhandled_input(event: InputEvent) -> void:
	if page != Page.HOME and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_to(Page.HOME)
