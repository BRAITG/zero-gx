@tool
extends EditorPlugin

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const ExportCheck = preload("res://tools/check_monetization_export.gd")
	const ENABLED_OPTION := "zero_gx_monetization/enabled"
	const APP_ID_OPTION := "zero_gx_monetization/admob_app_id"
	const BANNER_ID_OPTION := "zero_gx_monetization/banner_ad_unit_id"
	const DEBUG_APP_ID := "ca-app-pub-3940256099942544~3347511713"
	const DEBUG_BANNER_ID := "ca-app-pub-3940256099942544/9214589741"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_name() -> String:
		return "ZeroGxMonetization"

	func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
		if not _supports_platform(platform):
			return []
		return [
			{
				"option": {"name": ENABLED_OPTION, "type": TYPE_BOOL},
				"default_value": false,
				"update_visibility": true,
			},
			{
				"option": {"name": APP_ID_OPTION, "type": TYPE_STRING, "hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "ca-app-pub-…~…"},
				"default_value": "",
				"update_visibility": true,
			},
			{
				"option": {"name": BANNER_ID_OPTION, "type": TYPE_STRING, "hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "ca-app-pub-…/…"},
				"default_value": "",
				"update_visibility": true,
			},
		]

	func _get_export_option_visibility(platform: EditorExportPlatform, option: String) -> bool:
		if not _supports_platform(platform):
			return false
		if option == APP_ID_OPTION or option == BANNER_ID_OPTION:
			return bool(get_option(ENABLED_OPTION))
		return true

	func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
		if not _supports_platform(platform) or option != ENABLED_OPTION:
			return ""
		var result := ExportCheck.validate_options(
			bool(get_option(ENABLED_OPTION)),
			false,
			str(get_option(APP_ID_OPTION)),
			str(get_option(BANNER_ID_OPTION))
		)
		if result == ERR_UNCONFIGURED:
			return "Enabled release exports need an AdMob app ID and banner unit ID."
		if result == ERR_INVALID_DATA:
			return "Use a valid AdMob app ID (~), banner unit ID (/), and non-sample publisher."
		return ""

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if not bool(get_option(ENABLED_OPTION)):
			return PackedStringArray()
		return PackedStringArray([
			"zero_gx_monetization/bin/zero_gx_monetization-%s.aar" % ("debug" if debug else "release")
		])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if not bool(get_option(ENABLED_OPTION)):
			return PackedStringArray()
		return PackedStringArray([
			"com.google.android.libraries.ads.mobile.sdk:ads-mobile-sdk:1.6.0",
			"com.google.android.ump:user-messaging-platform:4.0.0",
			"com.android.billingclient:billing:9.1.0",
		])

	func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
		if not _supports_platform(platform) or not bool(get_option(ENABLED_OPTION)):
			return ""
		var app_id := DEBUG_APP_ID if debug else str(get_option(APP_ID_OPTION))
		var banner_id := DEBUG_BANNER_ID if debug else str(get_option(BANNER_ID_OPTION))
		return """
			<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s" />
			<meta-data android:name="dev.braitg.zerogx.BANNER_UNIT_ID" android:value="%s" />
		""" % [app_id.xml_escape(true), banner_id.xml_escape(true)]
