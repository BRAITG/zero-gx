extends Node
## Player settings, saved on the device. Autoloaded as `Settings`.

signal changed

var path := "user://settings.cfg"
## Draw the ship's velocity arrow in levels (tutorials always show it).
var show_velocity := false:
	set(value):
		show_velocity = value
		_save()


func _ready() -> void:
	load_file()


func load_file() -> void:
	var file := ConfigFile.new()
	file.load(path)  # a missing or unreadable file keeps the defaults
	show_velocity = file.get_value("display", "show_velocity", false)


func _save() -> void:
	if not is_inside_tree():
		return
	var file := ConfigFile.new()
	file.set_value("display", "show_velocity", show_velocity)
	file.save(path)
	changed.emit()
