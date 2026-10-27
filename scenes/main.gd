extends Control
## The main menu, on one of three pages. HOME is the hub: Official levels, Community levels (where
## `Community.available()`), Training, then a smaller row of My levels, Settings and Credits. OFFICIAL
## and TRAINING list their stages in a scrolling column of rows (thumbnail, title, best-score breakdown),
## each locked until the stage before it is finished, under a Back button that returns to HOME.

enum Page { HOME, OFFICIAL, TRAINING }

const SCENE := "res://scenes/main.tscn"
const MENU_DRIFT := Vector2(-40, -12)  # px/s
const HOME_WIDTH := 440.0  # px: the column of home buttons
const LIST_SIZE := Vector2(760, 520)  # px: the scrolling stage list
const ROW_HEIGHT := 108.0  # px: a stage row; its thumbnail fills the height less the margins
const ROW_MARGIN := 8.0

## Which page this scene shows; the main scene opens on HOME.
var page := Page.HOME

var _column: VBoxContainer
var _official: Button  # the home page's primary: it takes focus when HOME opens
var _training_button: Button
var _levels: VBoxContainer  # the stage rows of OFFICIAL or TRAINING

## Set once per run: the menu scene is entered again on every return to it.
static var _sized := false


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
	_refresh()
	if page == Page.HOME and get_viewport().gui_get_focus_owner() == null:  # not while an overlay holds it
		_official.grab_focus(true)


func _build_home() -> void:
	_column.add_child(_title("ZERO-GX"))
	_official = _button("Official levels", Vector2(HOME_WIDTH, 96), 30)
	_official.add_theme_stylebox_override("normal", _official.get_theme_stylebox("pressed"))  # the strongest look, at rest
	_official.pressed.connect(_go_to.bind(Page.OFFICIAL))
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
		var button := _button(entry[0], Vector2(0, 44), 18)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		utility.add_child(button)


func _build_list() -> void:
	_column.add_child(_title("OFFICIAL LEVELS" if page == Page.OFFICIAL else "TRAINING"))
	var back := _button("Back")
	back.pressed.connect(_go_to.bind(Page.HOME))
	_column.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = LIST_SIZE
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


## Brings the page up to date with the player's progress: the Training label on HOME, the stage buttons on a list.
func _refresh() -> void:
	if page == Page.HOME:
		var completed := Progress.training_completed()
		_training_button.text = "Training · ✓ completed" if completed else "Training"
	else:
		_list_levels()
	_center_column()


func _list_levels() -> void:
	for old in _levels.get_children():
		old.free()  # now, not queued: the new rows replace them in the same frame
	var training := page == Page.TRAINING
	var suggested: Button
	for id in Progress.trainings() if training else Progress.levels():
		var best := Progress.best_points(id)
		var unlocked := Progress.is_unlocked(id)
		var next := suggested == null and unlocked and best < 0
		var data := LevelFormat.read((Progress.TUTORIALS_DIR if training else Progress.LEVELS_DIR) + id + LevelFormat.EXTENSION)
		var label := "Training %s" % id.get_slice("_", 1) if id.begins_with("tutorial_") else id.replace("_", " ").capitalize()
		var button := _row(id, "%s · %s" % [label, data.get("title", "")], unlocked, next)
		button.disabled = not unlocked
		if not unlocked:
			button.modulate = Color(1, 1, 1, 0.55)  # the thumbnail dims with the text
		button.pressed.connect(func(): Progress.open(id))
		if next:
			suggested = button
			button.add_theme_stylebox_override("normal", button.get_theme_stylebox("pressed"))
		_levels.add_child(button)
	if get_viewport().gui_get_focus_owner() == null:  # not while an overlay holds it
		if suggested:
			suggested.grab_focus(true)
		else:
			Style.focus_first(_levels)


## A stage row: the thumbnail on the left; the title over one line of the best run's fuel, hull and
## time points (each behind its score icon) in the middle; the best total, large, on the right.
## A best saved before fuel and hull were kept shows "—" for them rather than an invented value.
## The title Label is named "Title" so tests and tools can read the row's name.
func _row(id: String, title: String, unlocked: bool, next: bool) -> Button:
	var button := _button("", Vector2(LIST_SIZE.x - 24, ROW_HEIGHT))  # less the scrollbar
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, ROW_MARGIN)
	content.add_theme_constant_override("separation", 20)
	button.add_child(content)
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
	text.add_child(name_label)
	var parts := HBoxContainer.new()
	parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parts.add_theme_constant_override("separation", 8)
	text.add_child(parts)
	var best := Progress.best_points(id)
	if not unlocked:
		parts.add_child(_label("Locked", 18, Style.INK_DIM))
	elif best < 0:
		parts.add_child(_label("Next · Not played" if next else "Not played", 18, Style.INK_DIM))
	else:
		var fuel := Progress.best_fuel(id)
		var hull := Progress.best_hull(id)
		for part in [
			[ScoreIcon.Kind.FUEL, "—" if fuel < 0 else "+%d" % roundi(fuel * Tuning.points_fuel)],
			[ScoreIcon.Kind.HULL, "—" if hull < 0 else "+%d" % roundi(hull * Tuning.points_hull)],
			[ScoreIcon.Kind.TIME, "−%d" % roundi(Progress.best_time(id) * Tuning.points_per_second)],
		]:
			parts.add_child(ScoreIcon.new(part[0]))
			var value := _label(part[1], 18, Style.INK_DIM)
			value.custom_minimum_size.x = 70  # the icons line up across rows
			parts.add_child(value)
		var total := _label(str(best), 36)
		total.add_theme_font_override("font", Style.display_font)
		total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(total)
	return button


func _label(text: String, font_size: int, color := Style.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Centres the column in the frame. Anchored to the frame's centre, it stays centred when the viewport changes.
func _center_column() -> void:
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
		if page == Page.HOME:
			get_tree().quit()
		else:
			_go_to(Page.HOME)


## Esc and B go back from a list to HOME; on HOME they do nothing (Esc must not quit).
func _unhandled_input(event: InputEvent) -> void:
	if page != Page.HOME and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_to(Page.HOME)
