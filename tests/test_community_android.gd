extends "res://tests/test_case.gd"
## The Android platform on a desktop run: no plugin singletons, so community stays off. The sign-in and integrity calls themselves need a device.


## A plugin's signals.
class Source extends RefCounted:
	signal fired(value: String)
	signal other(value: String)


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
