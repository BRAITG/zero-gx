extends SceneTree

const APP_ID_PATTERN := "^ca-app-pub-[0-9]{16}~[0-9]{10}\\z"
const BANNER_ID_PATTERN := "^ca-app-pub-[0-9]{16}/[0-9]{10}\\z"
const SAMPLE_PUBLISHER := "ca-app-pub-3940256099942544"
const PRESET_OPTION := "zero_gx_monetization/enabled"
const APP_ID_OPTION := "zero_gx_monetization/admob_app_id"
const BANNER_ID_OPTION := "zero_gx_monetization/banner_ad_unit_id"


static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func validate_options(enabled: bool, debug: bool, app_id: String, banner_id: String) -> int:
	if not enabled or debug:
		return OK
	if app_id.strip_edges().is_empty() or banner_id.strip_edges().is_empty():
		return ERR_UNCONFIGURED
	if SAMPLE_PUBLISHER in app_id or SAMPLE_PUBLISHER in banner_id:
		return ERR_INVALID_DATA
	if not _matches(app_id, APP_ID_PATTERN) or not _matches(banner_id, BANNER_ID_PATTERN):
		return ERR_INVALID_DATA
	return OK


func _initialize() -> void:
	var preset_name := "Android Play"
	var debug := false
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		match args[index]:
			"--preset":
				if index + 1 >= args.size():
					_fail("--preset requires a preset name.")
					return
				preset_name = args[index + 1]
				index += 1
			"--debug":
				debug = true
			_:
				_fail("Unknown argument: %s" % args[index])
				return
		index += 1

	var presets := ConfigFile.new()
	var load_error := presets.load("res://export_presets.cfg")
	if load_error != OK:
		_fail("Could not read export_presets.cfg: %s" % error_string(load_error))
		return

	var preset_section := ""
	for section in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") and presets.get_value(section, "name", "") == preset_name:
			preset_section = section + ".options"
			break
	if preset_section.is_empty():
		_fail("Export preset '%s' was not found in export_presets.cfg." % preset_name)
		return

	var enabled := bool(presets.get_value(preset_section, PRESET_OPTION, false))
	var app_id := str(presets.get_value(preset_section, APP_ID_OPTION, ""))
	var banner_id := str(presets.get_value(preset_section, BANNER_ID_OPTION, ""))
	var result := validate_options(enabled, debug, app_id, banner_id)
	if result == ERR_UNCONFIGURED:
		_fail("Preset '%s' enables monetization but is missing its AdMob app ID or banner unit ID." % preset_name)
		return
	if result == ERR_INVALID_DATA:
		_fail("Preset '%s' needs a valid AdMob app ID (~), banner unit ID (/), and a non-sample publisher." % preset_name)
		return

	var mode := "monetization disabled" if not enabled else ("debug sample IDs" if debug else "valid release IDs")
	print("Monetization preflight passed for '%s' (%s)." % [preset_name, mode])
	quit(0)


func _fail(message: String) -> void:
	printerr("Monetization preflight failed: %s" % message)
	quit(1)
