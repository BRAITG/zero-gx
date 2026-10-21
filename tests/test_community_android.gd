extends "res://tests/test_case.gd"
## The Android platform on a desktop run: no plugin singletons, so community stays off. The sign-in and integrity calls themselves need a device.


## A plugin's signals.
class Source extends RefCounted:
	signal fired(value: String)
	signal other(value: String)


## The Play Integrity plugin's surface, failing the way Play Integrity does: with a long raw message.
class FailingIntegrity extends RefCounted:
	signal integrity_token(token: String)
	signal integrity_failed(message: String)

	func request(_nonce: String, _project: int) -> void:
		integrity_failed.emit("-12: Integrity API error (https://developer.android.com/google/play/integrity/reference/com/google/android/play/core/integrity/model/IntegrityErrorCode): the Cloud project number is invalid.")


func test_without_the_plugins_the_android_platform_is_unavailable() -> void:
	var platform := CommunityAndroid.new(world)
	check(not platform.available(), "no plugin singletons, so no community")
	var auth: Dictionary = await platform.sign_in()
	check(auth.get("error") == CommunityPlatform.UNAVAILABLE, "sign-in must say why not: %s" % [auth])
	var proof: Dictionary = await platform.integrity("n1")
	check(proof.get("error") == CommunityPlatform.UNAVAILABLE, "integrity must say why not: %s" % [proof])


func test_a_desktop_run_keeps_the_base_platform() -> void:
	check(Community.platform.get_script() == CommunityPlatform, "desktop must not pick the Android platform")
	check(not Community.available(), "community is off on desktop")


func test_the_first_signal_wins_the_race() -> void:
	var platform := CommunityAndroid.new(world)
	var source := Source.new()
	var race := platform._race([source.fired, source.other], 0.05)
	source.other.emit("b")
	source.fired.emit("a")
	check(await race.result() == [1, "b"], "the first signal to fire is the answer")
	await tree.create_timer(0.1).timeout  # the race's own timer must not outlive the test


func test_a_silent_race_times_out() -> void:
	var platform := CommunityAndroid.new(world)
	var race := platform._race([Source.new().fired], 0.05)
	check(await race.result() == [-1, null], "no signal means the timeout answer")


func test_community_needs_the_setup_values() -> void:
	var client: Variant = ProjectSettings.get_setting("community/google_web_client_id", "")
	var project: Variant = ProjectSettings.get_setting("community/cloud_project_number", 0)
	ProjectSettings.set_setting("community/google_web_client_id", "")
	ProjectSettings.set_setting("community/cloud_project_number", 0)
	check(not CommunityAndroid.configured(), "neither value set")
	ProjectSettings.set_setting("community/google_web_client_id", "123-abc.apps.googleusercontent.com")
	check(not CommunityAndroid.configured(), "the Cloud project number is still missing")
	ProjectSettings.set_setting("community/cloud_project_number", 123456789)
	check(CommunityAndroid.configured(), "both values set")
	ProjectSettings.set_setting("community/google_web_client_id", "")
	check(not CommunityAndroid.configured(), "the web client id is missing")
	ProjectSettings.set_setting("community/google_web_client_id", client)
	ProjectSettings.set_setting("community/cloud_project_number", project)


func test_only_the_play_preset_carries_the_community_feature() -> void:
	var presets := ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "export_presets.cfg must load")
	var carriers := []
	for section in presets.get_sections():
		if section.count(".") == 1 and str(presets.get_value(section, "custom_features", "")).split(",").has(CommunityAndroid.FEATURE):
			carriers.append(presets.get_value(section, "name"))
	check(carriers == ["Android Play"], "a sideloaded APK cannot sign in, so only the Play build may show community: %s" % [carriers])


func test_a_failed_integrity_request_reads_as_one_short_sentence() -> void:
	var plugin := FailingIntegrity.new()  # the engine does not count a singleton's reference
	Engine.register_singleton(CommunityAndroid.INTEGRITY, plugin)
	var proof: Dictionary = await CommunityAndroid.new(world).integrity("n1")
	Engine.unregister_singleton(CommunityAndroid.INTEGRITY)
	check(proof.get("error") == "Play Integrity could not check this device.", "the raw text must not reach the player: %s" % [proof])
