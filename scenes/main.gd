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
var _signing_in := false

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
	var top := _button("Back" if training else ("Training · ✓ completed" if Progress.training_completed() else "Training"))
	top.pressed.connect(func(): get_tree().change_scene_to_node(menu(not training)))
	_column.add_child(top)
	_levels = GridContainer.new()
	_levels.columns = 3  # tutorials, then levels: six rows fit the 720 px screen
	_levels.add_theme_constant_override("h_separation", 12)
	_levels.add_theme_constant_override("v_separation", 12)
	_column.add_child(_levels)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_column.add_child(row)
	row.visible = not training
	var entries := [["My levels", func(): get_tree().change_scene_to_node(MyLevelsScreen.new())], ["Settings", _open_settings], ["Credits", func(): Credits.open(self)], ["Tune", func(): TuningPanel.open(self)]]
	if Community.available():
		entries.insert(1, ["Community", _open_community])
	for entry in entries:  # all share the grid's width
		var button := _button(entry[0])
		button.custom_minimum_size.x = 0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		row.add_child(button)
	Progress.changed.connect(_list_levels)
	_list_levels()


## The first tap signs in; if that fails, the reason shows and the menu stays.
func _open_community() -> void:
	if _signing_in:
		return
	if not Community.signed_in():
		_signing_in = true
		var error: String = await Community.sign_in()
		_signing_in = false
		if not is_inside_tree():  # the player went elsewhere meanwhile
			return
		if error != "":
			Overlay.open(self, "Cannot sign in").paragraph(error)
			return
	get_tree().change_scene_to_node(CommunityScreen.new())


func _open_settings() -> void:
	var o := Overlay.open(self, "Settings")
	_setting(o, "Show the velocity arrow in levels",
		"The arrow points where your ship is going; its length shows how fast. The training stages always show it.",
		Settings.show_velocity, func(on: bool): Settings.show_velocity = on)
	_setting(o, "Show gravity fields",
		"Faint discs show how far each planet, black hole and star pulls.",
		Settings.show_gravity, func(on: bool): Settings.show_gravity = on)
	var sound := o.card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	sound.add_child(row)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 26)
	label.custom_minimum_size.x = 260
	row.add_child(label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volume
	slider.custom_minimum_size = Vector2(520, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var show := func(v: float): label.text = "Sound: %d%%" % roundi(v * 100.0)
	show.call(slider.value)
	slider.value_changed.connect(show)
	slider.value_changed.connect(func(v: float): Settings.volume = v)
	slider.drag_ended.connect(func(_changed: bool): Sfx.play("tap"))
	var controls := _button("Controls")
	controls.pressed.connect(func(): ControlsScreen.open(self))
	o.body.add_child(controls)


## One panelled card: an enlarged toggle over a dim explanation of what it does.
func _setting(o: Overlay, title: String, description: String, on: bool, set_on: Callable) -> void:
	var box := o.card()
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.add_theme_font_size_override("font_size", 26)
	toggle.button_pressed = on
	toggle.toggled.connect(set_on)
	toggle.toggled.connect(func(_on: bool): Sfx.play("tap"))
	_big_switch(toggle)
	box.add_child(toggle)
	o.paragraph(description, 20, Style.INK_DIM, box)


const SWITCH_SCALE := 1.6
## The engine's default switch graphic is tiny next to 26 px text; redraw it larger.
func _big_switch(toggle: CheckButton) -> void:
	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored"]:
		var icon: Texture2D = toggle.get_theme_icon(icon_name)
		if icon == null:
			continue
		var image := icon.get_image()
		if image == null:
			continue
		image.resize(int(image.get_width() * SWITCH_SCALE), int(image.get_height() * SWITCH_SCALE), Image.INTERPOLATE_LANCZOS)
		toggle.add_theme_icon_override(icon_name, ImageTexture.create_from_image(image))


func _list_levels() -> void:
	for old in _levels.get_children():
		old.free()  # now, not queued: the new buttons replace them in the same frame
	for id in Progress.trainings() if training else Progress.levels():
		var best := Progress.best_points(id)
		var state := "locked" if not Progress.is_unlocked(id) else ("—" if best < 0 else str(best))
		var label := "Training %s" % id.get_slice("_", 1) if id.begins_with("tutorial_") else id.replace("_", " ").capitalize()
		var button := _button("%s · %s" % [label, state])
		button.disabled = not Progress.is_unlocked(id)
		button.pressed.connect(func(): Progress.open(id))
		_levels.add_child(button)
	_column.reset_size()
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if get_viewport().gui_get_focus_owner() == null:  # not while an overlay holds it
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
