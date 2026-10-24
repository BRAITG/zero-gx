extends Control
## The main menu: a Training button, then one button per level in `Progress.levels()` with its
## best points, locked until the level before it is finished. With `training` set it lists the
## training stages the same way instead, under a Back button.

const SCENE := "res://scenes/main.tscn"
const MENU_DRIFT := Vector2(-40, -12)  # px/s

## Show the training stages instead of the levels.
var training := false

var _levels: GridContainer
var _column: VBoxContainer
var _training_button: Button

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
	ui.add_child(_column)
	var title := Label.new()
	title.text = "TRAINING" if training else "ZERO-GX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(Style.ACCENT, 0.35))
	title.add_theme_constant_override("outline_size", 14)
	_column.add_child(title)
	_training_button = _button("Back" if training else "Training")
	_training_button.pressed.connect(func(): get_tree().change_scene_to_node(menu(not training)))
	_column.add_child(_training_button)
	_levels = GridContainer.new()
	_levels.columns = 3  # tutorials, then levels: six rows fit the 720 px screen
	_levels.add_theme_constant_override("h_separation", 12)
	_levels.add_theme_constant_override("v_separation", 12)
	_column.add_child(_levels)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_column.add_child(row)
	row.visible = not training
	var entries := [["My levels", func(): get_tree().change_scene_to_node(MyLevelsScreen.new())], ["Settings", SettingsScreen.open.bind(self)], ["Credits", func(): Credits.open(self)]]
	if Community.available():
		entries.insert(1, ["Community", _open_community, "Signing in…"])  # the third item is what the button says while it runs
	for entry in entries:  # all share the grid's width
		var button := _button(entry[0])
		button.custom_minimum_size.x = 0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1] if entry.size() == 2 else Style.busy.bind(button, entry[2], entry[1]))
		row.add_child(button)
	Progress.changed.connect(_list_levels)
	_list_levels()


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


func _list_levels() -> void:
	for old in _levels.get_children():
		old.free()  # now, not queued: the new buttons replace them in the same frame
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
	if not training:
		var completed := Progress.training_completed()
		_training_button.text = "Training · ✓ completed" if completed else "Training"
		_training_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if completed else Control.SIZE_FILL
		_column.move_child(_training_button, 2 if completed else 1)
	_column.reset_size()
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if get_viewport().gui_get_focus_owner() == null:  # not while an overlay holds it
		if suggested:
			suggested.grab_focus(true)
		else:
			Style.focus_first(_levels)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 52)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	return button


## The main menu, or the training list.
static func menu(show_training: bool) -> Control:
	var main: Control = load(SCENE).instantiate()
	main.training = show_training
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


## project.godot turns off quit_on_go_back so levels can return here; the training list goes
## back to the menu, and the menu quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if training:
			_to_menu()
		else:
			get_tree().quit()


## Esc and B go back from the training list; on the menu they do nothing (Esc must not quit).
func _unhandled_input(event: InputEvent) -> void:
	if training and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_to_menu()


func _to_menu() -> void:
	get_tree().change_scene_to_node(menu(false))
