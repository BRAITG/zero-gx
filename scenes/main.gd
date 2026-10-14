extends Control
## Level list: one button per level in `Progress.levels()`, with its best points, locked until
## the level before it is finished.

var _levels: GridContainer
var _column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 12)
	add_child(_column)
	var title := Label.new()
	title.text = "ZERO-GX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	_column.add_child(title)
	_levels = GridContainer.new()
	_levels.columns = 2  # ten rows would not fit the 720 px screen
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
	for id in Progress.levels():
		var best := Progress.best_points(id)
		var state := "locked" if not Progress.is_unlocked(id) else ("—" if best < 0 else str(best))
		var button := _button("%s · %s" % [id.replace("_", " ").capitalize(), state])
		button.disabled = not Progress.is_unlocked(id)
		button.pressed.connect(func(): get_tree().change_scene_to_file("res://levels/%s.tscn" % id))
		_levels.add_child(button)
	_column.reset_size()
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 56)
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(Sfx.play.bind("tap"))
	return button


## project.godot turns off quit_on_go_back so levels can return here; the menu still quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
