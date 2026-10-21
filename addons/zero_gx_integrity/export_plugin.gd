@tool
extends EditorPlugin
## Adds the Play Integrity plugin (`android/plugins/integrity/`, built into `bin/`) to Android exports only.

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	## The Play Games plugin's manifest entry reads the string resource `game_services_project_id`, which that plugin writes only once its export option `godot_play_game_services/game_id` is set; without it the Gradle build fails on the missing resource. Until the id is known, an empty one keeps the build green (sign-in then fails on the device).
	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if get_option("godot_play_game_services/game_id") == "":
			FileAccess.open("res://android/build/res/values/strings.xml", FileAccess.WRITE).store_string("<?xml version=\"1.0\" encoding=\"utf-8\"?><resources><string translatable=\"false\" name=\"game_services_project_id\"></string></resources>")

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_name() -> String:
		return "ZeroGxIntegrity"

	## Relative to `res://addons`.
	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["zero_gx_integrity/bin/zero_gx_integrity-%s.aar" % ("debug" if debug else "release")])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.android.play:integrity:1.4.0"])
