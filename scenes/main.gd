extends Control
## The main menu, on one of three pages. HOME is the hub: Official levels, Community levels (where
## `Community.available()`), Training, then a smaller row of My levels, Settings and Credits. OFFICIAL
## and TRAINING list their stages in a grid, each locked until the stage before it is finished, under a
## Back button that returns to HOME.

enum Page { HOME, OFFICIAL, TRAINING }

const SCENE := "res://scenes/main.tscn"
const MENU_DRIFT := Vector2(-40, -12)  # px/s
const HOME_WIDTH := 440.0  # px: the column of home buttons

## Which page this scene shows; the main scene opens on HOME.
var page := Page.HOME

var _column: VBoxContainer
var _official: Button  # the home page's primary: it takes focus when HOME opens
var _training_button: Button
var _levels: GridContainer  # the stage buttons of OFFICIAL or TRAINING

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
	_levels = GridContainer.new()
	_levels.columns = 3
	_levels.add_theme_constant_override("h_separation", 12)
	_levels.add_theme_constant_override("v_separation", 12)
	_column.add_child(_levels)


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
		old.free()  # now, not queued: the new buttons replace them in the same frame
	var training := page == Page.TRAINING
	var suggested: Button
	for id in Progress.trainings() if training else Progress.levels():
		var best := Progress.best_points(id)
		var unlocked := Progress.is_unlocked(id)
		var next := suggested == null and unlocked and best < 0
		var state := "locked" if not unlocked else ("Not played" if best < 0 else "Best: %d" % best)
		var label := "Training %s" % id.get_slice("_", 1) if id.begins_with("tutorial_") else id.replace("_", " ").capitalize()
		var data := LevelFormat.read((Progress.TUTORIALS_DIR if training else Progress.LEVELS_DIR) + id + LevelFormat.EXTENSION)
		var button := _button("%s · %s\n%s%s" % [label, data.get("title", ""), "Next · " if next else "", state])
		button.disabled = not unlocked
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
