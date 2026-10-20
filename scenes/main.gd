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


func _ready() -> void:
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
	for entry in [["My levels", func(): get_tree().change_scene_to_node(MyLevelsScreen.new())], ["Settings", _open_settings], ["Credits", func(): Credits.open(self)], ["Tune", func(): TuningPanel.open(self)]]:
		var button := _button(entry[0])
		button.custom_minimum_size.x = 0  # four share the grid's width
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		row.add_child(button)
	Progress.changed.connect(_list_levels)
	_list_levels()


func _open_settings() -> void:
	var o := Overlay.open(self, "Settings")
	var arrow := CheckButton.new()
	arrow.text = "Show the velocity arrow in levels"
	arrow.add_theme_font_size_override("font_size", 26)
	arrow.button_pressed = Settings.show_velocity
	arrow.toggled.connect(func(on: bool): Settings.show_velocity = on)
	arrow.toggled.connect(func(_on: bool): Sfx.play("tap"))
	o.body.add_child(arrow)
	o.paragraph("The arrow points where your ship is going; its length shows how fast. The training stages always show it.", 20, Style.INK_DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	o.body.add_child(row)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 26)
	label.custom_minimum_size.x = 260
	row.add_child(label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volume
	slider.custom_minimum_size = Vector2(520, 48)
	row.add_child(slider)
	var show := func(v: float): label.text = "Sound: %d%%" % roundi(v * 100.0)
	show.call(slider.value)
	slider.value_changed.connect(show)
	slider.value_changed.connect(func(v: float): Settings.volume = v)
	slider.drag_ended.connect(func(_changed: bool): Sfx.play("tap"))
	var controls := _button("Controls")
	controls.pressed.connect(func(): ControlsScreen.open(self))
	o.body.add_child(controls)


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
