extends Control
## Level list: one button per level in `Progress.levels()`, with its best points, locked until
## the level before it is finished.

const MENU_DRIFT := Vector2(-40, -12)  # px/s

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
	title.text = "ZERO-GX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Style.display_font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(Style.ACCENT, 0.35))
	title.add_theme_constant_override("outline_size", 14)
	_column.add_child(title)
	_levels = GridContainer.new()
	_levels.columns = 3  # tutorials, then levels: six rows fit the 720 px screen
	_levels.add_theme_constant_override("h_separation", 12)
	_levels.add_theme_constant_override("v_separation", 12)
	_column.add_child(_levels)
	var tune := _button("Tune")
	tune.pressed.connect(func(): TuningPanel.open(self))
	_column.add_child(tune)
	Progress.changed.connect(_list_levels)
	_list_levels()


func _list_levels() -> void:
	for old in _levels.get_children():
		old.free()  # now, not queued: the new buttons replace them in the same frame
	for id in Progress.stages():
		var best := Progress.best_points(id)
		var state := "locked" if not Progress.is_unlocked(id) else ("—" if best < 0 else str(best))
		var label := "Training %s" % id.get_slice("_", 1) if id.begins_with("tutorial_") else id.replace("_", " ").capitalize()
		var button := _button("%s · %s" % [label, state])
		button.disabled = not Progress.is_unlocked(id)
		button.pressed.connect(func(): get_tree().change_scene_to_file(Progress.path_of(id)))
		_levels.add_child(button)
	_column.reset_size()
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 52)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	return button


## project.godot turns off quit_on_go_back so levels can return here; the menu still quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
