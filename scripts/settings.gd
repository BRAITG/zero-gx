extends Node
## Player settings, saved on the device. Autoloaded as `Settings`.

signal changed

var path := "user://settings.cfg"
## Draw the ship's velocity arrow in levels (tutorials always show it).
var show_velocity := false:
	set(value):
		show_velocity = value
		_save()
## Sound volume, 0 (silent) to 1, applied to the master bus.
var volume := 0.8:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		AudioServer.set_bus_mute(0, volume <= 0.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
		_save()


func _ready() -> void:
	load_file()


func load_file() -> void:
	var file := ConfigFile.new()
	file.load(path)  # a missing or unreadable file keeps the defaults
	show_velocity = file.get_value("display", "show_velocity", false)
	volume = file.get_value("audio", "volume", 0.8)


func _save() -> void:
	if not is_inside_tree():
		return
	var file := ConfigFile.new()
	file.set_value("display", "show_velocity", show_velocity)
	file.set_value("audio", "volume", volume)
	file.save(path)
	changed.emit()
