extends "res://tests/test_case.gd"

const MonetizationExportCheck = preload("res://tools/check_monetization_export.gd")


func test_disabled_or_debug_exports_need_no_live_ids() -> void:
	check(MonetizationExportCheck.validate_options(false, false, "", "") == OK, "disabled export must not require live IDs")
	check(MonetizationExportCheck.validate_options(true, true, "", "") == OK, "debug export must not require live IDs")


func test_live_export_refuses_missing_malformed_or_sample_ids() -> void:
	var app_id := "ca-app-pub-1234567890123456~1234567890"
	var banner_id := "ca-app-pub-1234567890123456/0987654321"
	check(MonetizationExportCheck.validate_options(true, false, "", "") == ERR_UNCONFIGURED, "release export with missing IDs must be unconfigured")
	check(MonetizationExportCheck.validate_options(true, false, "", banner_id) == ERR_UNCONFIGURED, "release export with no app ID must be unconfigured")
	check(MonetizationExportCheck.validate_options(true, false, app_id, "") == ERR_UNCONFIGURED, "release export with no banner ID must be unconfigured")
	check(MonetizationExportCheck.validate_options(true, false, banner_id, app_id) == ERR_INVALID_DATA, "swapped app and banner ID forms must be invalid")
	check(MonetizationExportCheck.validate_options(true, false, "ca-app-pub-3940256099942544~3347511713", "ca-app-pub-3940256099942544/9214589741") == ERR_INVALID_DATA, "Google sample publisher IDs must be invalid for release")
	check(MonetizationExportCheck.validate_options(true, false, app_id, banner_id) == OK, "well-formed non-sample release IDs must be accepted")


func test_release_id_shapes_and_sample_publishers_are_checked_independently() -> void:
	var app_id := "ca-app-pub-1234567890123456~1234567890"
	var banner_id := "ca-app-pub-1234567890123456/0987654321"
	var app_shaped_banner_id := "ca-app-pub-1234567890123456/0987654321"
	var banner_shaped_app_id := "ca-app-pub-1234567890~0987654321"
	var sample_app_id := "ca-app-pub-3940256099942544~3347511713"
	var sample_banner_id := "ca-app-pub-3940256099942544/9214589741"
	check(MonetizationExportCheck.validate_options(true, false, app_shaped_banner_id, banner_id) == ERR_INVALID_DATA, "an invalid app ID is rejected independently")
	check(MonetizationExportCheck.validate_options(true, false, app_id, banner_shaped_app_id) == ERR_INVALID_DATA, "an invalid banner ID is rejected independently")
	check(MonetizationExportCheck.validate_options(true, false, sample_app_id, banner_id) == ERR_INVALID_DATA, "a sample app publisher is rejected independently")
	check(MonetizationExportCheck.validate_options(true, false, app_id, sample_banner_id) == ERR_INVALID_DATA, "a sample banner publisher is rejected independently")


func test_release_ids_reject_a_terminal_newline() -> void:
	var app_id := "ca-app-pub-1234567890123456~1234567890"
	var banner_id := "ca-app-pub-1234567890123456/0987654321"
	check(MonetizationExportCheck.validate_options(true, false, app_id + "\n", banner_id) == ERR_INVALID_DATA, "a terminal newline invalidates the app ID")
	check(MonetizationExportCheck.validate_options(true, false, app_id, banner_id + "\n") == ERR_INVALID_DATA, "a terminal newline invalidates the banner ID")
