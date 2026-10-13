extends Control
## Level list: one button per `res://levels/*.tscn`, sorted by file name.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title := Label.new()
	title.text = "ZERO-GX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	column.add_child(title)
	var files := Array(ResourceLoader.list_directory("res://levels/")).filter(func(f: String): return f.ends_with(".tscn"))
	files.sort()
	for file: String in files:
		var button := Button.new()
		button.text = file.get_basename().replace("_", " ").capitalize()
		button.custom_minimum_size = Vector2(320, 64)
		button.add_theme_font_size_override("font_size", 28)
		button.pressed.connect(Sfx.play.bind("tap"))
		button.pressed.connect(func(): get_tree().change_scene_to_file("res://levels/" + file))
		column.add_child(button)
	column.reset_size()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


## project.godot turns off quit_on_go_back so levels can return here; the menu still quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
