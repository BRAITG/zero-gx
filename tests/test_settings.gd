extends "res://tests/test_case.gd"


func test_volume_sets_the_master_bus_and_persists() -> void:
	Settings.volume = 0.5
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)) and not AudioServer.is_bus_mute(0), "half volume: %f dB" % AudioServer.get_bus_volume_db(0))
	Settings.volume = 0.0
	check(AudioServer.is_bus_mute(0), "zero volume must mute")
	Settings.volume = 0.3
	Settings.load_file()
	check(is_equal_approx(Settings.volume, 0.3), "volume must survive a reload: %f" % Settings.volume)
	Settings.volume = 0.8
