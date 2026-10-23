extends "res://tests/test_case.gd"
## The Android platform on a desktop run: no plugin singletons, so community stays off. The sign-in and integrity calls run here against the native fakes in `tests/support/fake_native_signals.gd`; the real plugins need a device.

const BOUND := 30.0  # the longest the platform waits for one Play Games or Integrity answer
const SLACK := 5.0  # seconds past BOUND a settle may still land: a timer fires up to a frame late, ~1.7 s at FAST
const FAST := 100.0  # Engine.time_scale while a bound passes: at 60 FPS a frame then spans 1.7 s, so a 30 s bound takes ~18 frames
const LIMIT := 1200  # frames a waiting test allows before it calls the answer missing
const NATIVE_TEXT := "Integrity API error"  # the native plugin's failure text: the player must never read it


## A plugin's signals.
class Source extends RefCounted:
	signal fired(value: String)
	signal other(value: String)


## The Android platform on a device with the Play Games plugin. `available()` needs the export feature, which a desktop run cannot set.
class ReadyAndroid extends CommunityAndroid:
	func available() -> bool:
		return true


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


func test_a_failed_integrity_request_answers_an_error_without_the_native_text() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	native.instant = {"error": "-12: Integrity API error (https://developer.android.com/google/play/integrity/reference/com/google/android/play/core/integrity/model/IntegrityErrorCode): the Cloud project number is invalid."}
	var got := {}
	_ask(CommunityAndroid.new(world), "n1", got)
	check(await _within(func() -> bool: return got.has("n1")), "a failed integrity request must answer")
	check(_failed_quietly(got.get("n1")), "the failure must carry no token and no native text: %s" % [got])
	await _finish(clock)


func test_two_callers_queue_their_native_requests_and_each_gets_its_own_answer() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	var platform := CommunityAndroid.new(world)
	var got := {}
	_ask(platform, "a", got)
	_ask(platform, "b", got)
	await frames(2)
	check(native.requests.size() == 1 and native.request_at(0).get("nonce") == "a", "the second caller waits while one native request is in flight: %s" % [native.requests])
	native.answer(0, "ok:a")
	check(await _within(func() -> bool: return native.requests.size() == 2), "the next request goes out once the first is answered")
	check(native.request_at(1).get("nonce") == "b", "the second request carries the second nonce: %s" % [native.requests])
	native.answer(1, "ok:b")
	check(await _within(func() -> bool: return got.size() == 2), "both callers must get an answer: %s" % [got])
	check(got.get("a") == {"token": "ok:a"}, "caller a gets its own token: %s" % [got.get("a")])
	check(got.get("b") == {"token": "ok:b"}, "caller b gets its own token: %s" % [got.get("b")])
	check(native.request_at(0).get("request_id") != native.request_at(1).get("request_id"), "each request carries its own id")
	check(native.request_at(0).get("cloud_project_number") == ProjectSettings.get_setting("community/cloud_project_number"), "the Cloud project number goes with each request")
	await _finish(clock)


func test_a_result_under_another_request_id_does_not_settle_the_request() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	var got := {}
	_ask(CommunityAndroid.new(world), "a", got)
	check(await _within(func() -> bool: return native.requests.size() == 1), "the request must reach native")
	var other: int = native.request_at(0).get("request_id", -1) + 1
	native.reply(other, "ok:forged")
	native.reply(other, "", "-12: forged failure")
	await frames(2)
	check(not got.has("a"), "a result under another request id must not settle the request: %s" % [got])
	native.answer(0, "ok:a")
	check(await _within(func() -> bool: return got.has("a")), "the request's own id still settles it")
	check(got.get("a") == {"token": "ok:a"}, "the answer under its own id is the token: %s" % [got.get("a")])
	await _finish(clock)


func test_a_late_answer_to_a_timed_out_request_does_not_settle_the_next_one() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	var platform := CommunityAndroid.new(world)
	var got := {}
	_ask(platform, "a", got)
	check(await _within(func() -> bool: return got.has("a")), "a request nobody answers must give up within the bound")
	check(_field(got.get("a"), "error") != "" and _field(got.get("a"), "token") == "", "a timed-out request reads as an error: %s" % [got.get("a")])
	var late: int = native.request_at(0).get("request_id", -1)
	_ask(platform, "b", got)
	check(await _within(func() -> bool: return native.requests.size() == 2), "the timeout must release the queue for the next request")
	check(native.request_at(1).get("nonce") == "b", "the next request is the second caller's: %s" % [native.requests])
	native.reply(late, "ok:a")  # the old request's answer, arriving after its timeout
	await frames(2)
	check(not got.has("b"), "a late answer for a timed-out request must not settle the next one: %s" % [got.get("b")])
	native.answer(1, "ok:b")
	check(await _within(func() -> bool: return got.has("b")), "the next request still gets its own answer")
	check(got.get("b") == {"token": "ok:b"}, "the next caller gets its own token: %s" % [got.get("b")])
	await _finish(clock)


func test_a_failed_request_releases_the_queue_for_the_next_one() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	var platform := CommunityAndroid.new(world)
	var got := {}
	_ask(platform, "a", got)
	_ask(platform, "b", got)
	check(await _within(func() -> bool: return native.requests.size() == 1), "the first request must reach native")
	native.answer(0, "", "-12: Integrity API error: the Cloud project number is invalid.")
	check(await _within(func() -> bool: return native.requests.size() == 2), "a failed request must not hold up the next one")
	native.answer(1, "ok:b")
	check(await _within(func() -> bool: return got.size() == 2), "both callers must get an answer: %s" % [got])
	check(_failed_quietly(got.get("a")), "the failure must carry no token and no native text: %s" % [got.get("a")])
	check(got.get("b") == {"token": "ok:b"}, "the next caller gets its own token: %s" % [got.get("b")])
	await _finish(clock)


func test_an_integrity_answer_given_during_the_request_call_is_not_lost() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	native.instant = {"token": "ok:n1"}
	var got := {}
	_ask(CommunityAndroid.new(world), "n1", got)
	check(await _within(func() -> bool: return got.has("n1")), "an answer given during the call must settle it")
	check(got.get("n1") == {"token": "ok:n1"}, "the token comes back unchanged: %s" % [got])
	await _finish(clock)


func test_a_play_games_answer_given_during_the_calls_is_not_lost() -> void:
	var clock := _fast_clock()
	var plugin := FakeNativeSignals.PlayGames.new()
	plugin.authenticates_at_once = true
	plugin.code_at_once = "code-1"
	_install_play_games(plugin)
	var got := {}
	_sign_in(ReadyAndroid.new(world), got)
	check(await _within(func() -> bool: return got.has("sign_in")), "sign-in answers given during the Play Games calls must still settle it")
	check(got.get("sign_in") == {"auth_code": "code-1"}, "the code comes back as the auth code: %s" % [got.get("sign_in")])
	await _finish(clock)


func test_a_play_games_sign_in_nobody_answers_gives_up_within_the_bound() -> void:
	var clock := _fast_clock()
	var plugin := FakeNativeSignals.PlayGames.new()
	_install_play_games(plugin)
	var got := {}
	_sign_in(ReadyAndroid.new(world), got)
	check(await _within(func() -> bool: return got.has("sign_in")), "a sign-in that Play Games never answers must give up")
	check(_field(got.get("sign_in"), "error") != "" and _field(got.get("sign_in"), "auth_code") == "", "a timed-out sign-in reads as an error: %s" % [got.get("sign_in")])
	await _finish(clock)


func test_a_server_code_nobody_sends_gives_up_within_the_bound() -> void:
	var clock := _fast_clock()
	var plugin := FakeNativeSignals.PlayGames.new()
	_install_play_games(plugin)
	var got := {}
	_sign_in(ReadyAndroid.new(world), got)
	plugin.authenticate(true)  # the player signs in, and no code follows
	check(await _within(func() -> bool: return got.has("sign_in")), "a sign-in that never gets a code must give up")
	check(_field(got.get("sign_in"), "error") != "" and _field(got.get("sign_in"), "auth_code") == "", "a sign-in without a code reads as an error: %s" % [got.get("sign_in")])
	await _finish(clock)


func test_two_callers_share_one_bound_when_the_first_native_request_never_answers() -> void:
	var clock := _fast_clock()
	var native := _install_integrity()
	var platform := CommunityAndroid.new(world)
	var got := {}
	var overrun := {"fired": false}  # one bound for both callers, queueing included
	tree.create_timer(BOUND + SLACK).timeout.connect(func() -> void: overrun["fired"] = true)
	_ask(platform, "a", got)
	_ask(platform, "b", got)  # queued behind a native request that is never answered
	check(await _within(func() -> bool: return got.size() == 2), "both callers must settle though the first native request never answers: %s" % [got])
	check(not overrun["fired"], "both callers together must settle within one bound of %s s: %s" % [BOUND, got])
	check(_index_of(native, "b") == -1, "a caller that spent its bound in the queue must never issue a native request: %s" % [native.requests])
	check(_field(got.get("b"), "error") != "" and _field(got.get("b"), "token") == "", "that caller reads as an error: %s" % [got.get("b")])
	_ask(platform, "c", got)
	_ask(platform, "d", got)
	check(await _within(func() -> bool: return _index_of(native, "c") >= 0), "a later caller gets its native request once the earlier ones settled: %s" % [native.requests])
	await frames(2)
	check(_index_of(native, "d") == -1, "a later caller waits while another native request is in flight: %s" % [native.requests])
	native.answer(_index_of(native, "c"), "ok:c")
	check(await _within(func() -> bool: return _index_of(native, "d") >= 0), "the next later caller goes out once the one in flight is answered")
	native.answer(_index_of(native, "d"), "ok:d")
	check(await _within(func() -> bool: return got.size() == 4), "both later callers must get an answer: %s" % [got])
	check(got.get("c") == {"token": "ok:c"}, "the first later caller gets its own token: %s" % [got.get("c")])
	check(got.get("d") == {"token": "ok:d"}, "the second later caller gets its own token: %s" % [got.get("d")])
	await _finish(clock)


## Speeds the engine clock up so a bound passes in a few frames. Returns the value to restore.
func _fast_clock() -> float:
	var was := Engine.time_scale
	Engine.time_scale = FAST
	return was


## Registers a native Integrity fake. The engine does not own a registered singleton: `_finish` frees the fake.
func _install_integrity() -> FakeNativeSignals.Integrity:
	var native := FakeNativeSignals.Integrity.new()
	Engine.register_singleton(CommunityAndroid.INTEGRITY, native)
	return native


## Registers a Play Games fake for the autoload's `initialize` to find. `_finish` frees it, as above.
func _install_play_games(plugin: FakeNativeSignals.PlayGames) -> void:
	GodotPlayGameServices.android_plugin = null  # the autoload keeps the plugin it found the first time
	Engine.register_singleton(CommunityAndroid.PLAY_GAMES, plugin)


## Starts `integrity(nonce)` as one caller would; `got[nonce]` holds its answer once it comes.
func _ask(platform: CommunityAndroid, nonce: String, got: Dictionary) -> void:
	got[nonce] = await platform.integrity(nonce)


func _sign_in(platform: CommunityAndroid, got: Dictionary) -> void:
	got["sign_in"] = await platform.sign_in()


## One field of an answer, "" when the answer lacks it. Tests read answers through this so a missing one fails a check instead of crashing the test.
func _field(answer: Variant, key: String) -> String:
	return str(answer.get(key, "")) if answer is Dictionary else ""

## Whether `answer` is a failure a player can read: an error, no token, and none of the native text.
func _failed_quietly(answer: Variant) -> bool:
	return _field(answer, "error") != "" and _field(answer, "token") == "" and not str(answer).contains(NATIVE_TEXT)


## The index of the first native request that carries `nonce`, -1 when there is none.
func _index_of(native: FakeNativeSignals.Integrity, nonce: String) -> int:
	for i in native.requests.size():
		if native.request_at(i).get("nonce") == nonce:
			return i
	return -1


## Waits up to `LIMIT` frames for `done`. False when it never came true, so a missing answer fails the test instead of hanging it.
func _within(done: Callable) -> bool:
	for _frame in LIMIT:
		if done.call():
			return true
		await tree.process_frame
	return done.call()


## Ends a test that used the platform: waits until its race timers have fired, puts the clock back and removes the fakes.
func _finish(clock: float) -> void:
	await tree.create_timer(BOUND).timeout  # a timer made earlier than this one fires no later than it
	Engine.time_scale = clock
	GodotPlayGameServices.android_plugin = null  # before the fake it points at is freed
	for singleton in [CommunityAndroid.INTEGRITY, CommunityAndroid.PLAY_GAMES]:
		if Engine.has_singleton(singleton):
			var fake := Engine.get_singleton(singleton)
			Engine.unregister_singleton(singleton)
			fake.free()  # the engine does not own a registered Object
