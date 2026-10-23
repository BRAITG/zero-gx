extends "res://tests/test_case.gd"
## Task 6: the community client's play-history reporting and feedback votes, end to end. The real `Community` and a real
## disk-backed history run against a fake server and a fake Play Games device (tests/support/fake_*.gd); only HTTP and the
## platform are replaced. History is read back from disk through `CommunityHistory`, the way a restart would see it.
##
## The Task 6 interface is reached through a Variant (`_c`), so this file compiles without it: `_boot` names what is
## missing and the test ends there, instead of one compile error hiding every test.
##
## Seams assumed beyond the brief (see task-6-report.md): `Community.history_path`, and `Community.use_defaults()` as the
## per-test reset that also cancels flush timers, drops the loaded history and ends the explicit activation. Entry points
## (`sync_feedback`, `set_like`, `set_difficulty`, `feedback`) work without `activate_feedback`; activation only enables
## background scheduling. The routine cooldown is the fixed production 30 s and runs on a SceneTreeTimer (process_always),
## as the native bound already does; `_cooldown` expires it by speeding `Engine.time_scale` up for a few process frames,
## so a test crosses it only when it needs the next flush and no test sleeps on the wall clock.

const LEVEL_ID := "lvl_abcdefghij"
const DIR := "user://test_community_sync/"
const HISTORY := DIR + "history.json"
const LOCKED := DIR + "locked/"  # holds a history that a test makes read-only; the session file is not here
const LOCKED_HISTORY := LOCKED + "history.json"
const UNAUTHORIZED := {"error": "Sign in again."}
const FEEDBACK_PATH := "/levels/" + LEVEL_ID + "/feedback"
const DIFFICULTY_PATH := "/levels/" + LEVEL_ID + "/difficulty"
const LIKE_PATH := "/levels/" + LEVEL_ID + "/like"
const OTHER_LEVEL_ID := "lvl_bcdefghijk"
const OTHER_LIKE_PATH := "/levels/" + OTHER_LEVEL_ID + "/like"
## Keys of `pending_feedback()` (queued selections) and of the public `<sha>.meta.json` / `level_info()`.
const PENDING_LIKE := "like"
const PENDING_DIFFICULTY := "difficulty"
const META_LEVEL := "level_id"
const META_VERSION := "version"
const INTERFACE_METHODS := ["player_id", "activate_feedback", "record_play_start", "record_play_finish", "play_progress", "feedback", "sync_feedback", "set_like", "set_difficulty", "pending_feedback", "level_info"]
const INTERFACE_PROPERTIES := ["history_path"]
const FAST := 100.0  # Engine.time_scale while the cooldown passes: at 60 FPS a frame then spans about 1.7 s
const COOLDOWN_FRAMES := 24  # frames at FAST: about 40 s, past the 30 s cooldown

var _c: Variant = Community
var pilot := FakePlatform.new()


# --- identity and explicit activation ---------------------------------------------------------------------------------


func test_a_legacy_session_refreshes_sign_in_online_and_offline_play_makes_no_ownerless_report() -> void:
	var net := _boot()
	if net == null:
		return
	var row := _place_level()
	var legacy := ConfigFile.new()  # a session saved before the player id was stored
	legacy.set_value("session", "token", "legacy")
	legacy.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
	legacy.save(Community.session_path)
	check(Community.signed_in() and _c.player_id() == "", "control: a legacy token is valid but names no player")
	check(await Community.download(row) == "" and _c.level_info(row.sha256).get(META_LEVEL) == LEVEL_ID, "a cached level must still load and describe itself offline")
	net.answer("GET", "/nonce", 0)
	_c.activate_feedback()
	await _c.sync_feedback()
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	check(id == "" and _attempt_count() == 0, "a play under an unknown account must create no ownerless record: '%s'" % id)
	check(Community.signed_in(), "going offline must not drop the legacy session")
	net.queue.clear()
	net.requests.clear()
	net.answer("GET", "/nonce", 200, {"nonce": "n_refresh"})
	net.answer("POST", "/session", 200, {"token": "tok2", "player": {"id": "p_1", "name": "Pilot"}})
	await _cooldown()
	await _c.sync_feedback()
	check(net.count("POST", "/session") == 1 and _c.player_id() == "p_1", "the next online entry must refresh sign-in and learn the player: %s" % [_urls(net)])
	var reloaded = load("res://scripts/community.gd").new()
	reloaded.session_path = Community.session_path
	check(reloaded.player_id() == "p_1", "the player id must be stored with the session")
	reloaded.free()
	check(net.count("POST", "/plays") == 0 and _attempt_count() == 0, "the earlier offline play must not be attached to the account that signed in later")
	var later: String = _c.record_play_start(row.sha256)
	check(later != "" and _disk().owner_for_attempt(later) == "p_1", "a play after the refresh belongs to the signed-in player")
	_done()


func test_a_session_reply_without_a_valid_player_stores_no_identity() -> void:
	var replies := [{"token": "tok1"}, {"token": "tok1", "player": {"name": "Pilot"}}, {"token": "tok1", "player": {"id": 7, "name": "Pilot"}}, {"token": "tok1", "player": {"id": "", "name": "Pilot"}}]
	for reply: Dictionary in replies:
		var net := _boot()
		if net == null:
			return
		net.answer("GET", "/nonce", 200, {"nonce": "n1"})
		net.answer("POST", "/session", 200, reply)
		await Community.sign_in()
		check(_c.player_id() == "", "a player the server did not describe validly must not become the owner: %s" % [reply])
		_done()


func test_nothing_goes_out_until_the_community_is_entered_and_entering_starts_no_play() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	await _cooldown()  # more than the 30 s cooldown: nothing may be scheduled
	check(net.requests.is_empty(), "a booted game with a stored session must make no request: %s" % [_urls(net)])
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	await _cooldown()
	check(net.requests.is_empty(), "recording a play must not reach the network before the community is entered: %s" % [_urls(net)])
	var before := _attempt_count()
	_c.activate_feedback()
	check(_attempt_count() == before, "entering the community is not a play")
	_done()


func test_a_device_without_play_games_records_and_sends_nothing() -> void:
	var net := _boot()
	if net == null:
		return
	pilot.is_available = false
	var row := _place_level()
	_c.activate_feedback()
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	await _c.sync_feedback()
	await _c.set_like(LEVEL_ID, true)
	await _cooldown()
	check(id == "" and net.requests.is_empty() and not FileAccess.file_exists(HISTORY), "no collection, request or history file without Play Games: %s" % [_urls(net)])
	_done()


# --- play history: revisions, retries, batches, cadence ---------------------------------------------------------------


func test_a_finish_made_during_the_start_upload_stays_queued_and_goes_in_the_next_batch() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	check(id != "", "setup: the start must record")
	net.answer("GET", "/nonce", 200, {"nonce": "n_up1"})
	net.hold("POST", "/plays")
	var results := []
	var upload := func() -> void: results.append(await _c.sync_feedback())
	upload.call()
	await frames(3)
	if net.count("POST", "/plays") != 1:
		check(false, "setup: the upload must be in flight: %s" % [_urls(net)])
		_done()
		return
	var first := _attempts(_plays(net)[0])
	check(first.size() == 1 and first[0].id == id and first[0].revision == 1 and first[0].outcome == null and first[0].ended_ms == null, "the held upload carries the start only: %s" % [first])
	_c.record_play_finish(id, "failed")
	net.answer("POST", "/plays", 200, _ack([[id, 1]]))
	net.release_hold("POST", "/plays")
	await frames(3)
	var rest: Array = _disk().batch("p_1")
	check(rest.size() == 1 and rest[0].id == id and rest[0].revision == 2 and rest[0].outcome == "failed", "acknowledging revision 1 must leave the finish queued: %s" % [rest])
	net.answer("GET", "/nonce", 200, {"nonce": "n_up2"})
	net.answer("POST", "/plays", 200, _ack([[id, 2]]))
	await _cooldown()
	await _c.sync_feedback()
	var second := _attempts(_plays(net)[1]) if net.count("POST", "/plays") >= 2 else []
	check(second.size() == 1 and second[0].id == id and second[0].revision == 2 and second[0].outcome == "failed", "the next batch must carry the finish of the same attempt: %s" % [second])
	check(_disk().batch("p_1").is_empty(), "revision 2 acknowledged: nothing left to send")
	_done()


func test_a_lost_response_is_retried_with_the_same_id_and_the_finish_keeps_it() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	net.answer("GET", "/nonce", 200, {"nonce": "n_l1"})
	net.answer("POST", "/plays", 0)  # the server stored it, the answer never arrived
	await _c.sync_feedback()
	net.answer("GET", "/nonce", 200, {"nonce": "n_l2"})
	net.answer("POST", "/plays", 0)
	await _cooldown()
	await _c.sync_feedback()
	_c.record_play_finish(id, "cleared")
	net.answer("GET", "/nonce", 200, {"nonce": "n_l3"})
	net.answer("POST", "/plays", 200, _ack([[id, 2]]))
	await _cooldown()
	await _c.sync_feedback()
	var plays := _plays(net)
	if plays.size() != 3:
		check(false, "three uploads expected: %s" % [_urls(net)])
		_done()
		return
	var a := _attempts(plays[0])
	var b := _attempts(plays[1])
	var c := _attempts(plays[2])
	check(a.size() == 1 and JSON.stringify(a) == JSON.stringify(b), "a retry of a lost response must send the same snapshot, not a new attempt: %s vs %s" % [a, b])
	check(c.size() == 1 and c[0].id == id and c[0].revision == 2 and c[0].outcome == "cleared" and c[0].started_ms == a[0].started_ms, "the finish must keep the attempt's id and start: %s" % [c])
	check(_report(plays[2]).get("player_id") == "p_1" and _disk().batch("p_1").is_empty(), "owner named and outbox cleared")
	_done()


func test_rapid_syncs_make_one_request_and_an_early_sync_returns_pending_at_once() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	net.answer("GET", "/nonce", 200, {"nonce": "n_r1"})
	net.hold("POST", "/plays")
	var out := []
	var ask := func() -> void: out.append(await _c.sync_feedback())
	ask.call()
	ask.call()
	ask.call()
	await frames(3)
	check(net.count("POST", "/plays") == 1, "three overlapping syncs must make one upload: %s" % [_urls(net)])
	check(out.size() == 2 and out.all(func(r: Dictionary) -> bool: return r.get("pending") == true), "the callers that came meanwhile must return Pending sync without waiting: %s" % [out])
	net.answer("POST", "/plays", 200, _ack([[id, 1]]))
	net.release_hold("POST", "/plays")
	await frames(3)
	check(out.size() == 3 and out[2].get("pending") == false and String(out[2].get("error", "")) == "", "the sync that did the work reports success: %s" % [out])
	var second: String = _c.record_play_start(row.sha256)
	var started := Engine.get_process_frames()
	var early: Dictionary = await _c.sync_feedback()
	check(early.get("pending") == true and Engine.get_process_frames() - started <= 1, "inside the 30 s cooldown a sync must say Pending sync at once, not wait for it: %s" % [early])
	check(net.count("POST", "/plays") == 1 and net.count("GET", "/nonce") == 1, "no request, and no nonce spent, inside the gap: %s" % [_urls(net)])
	var waiting: Array = _disk().batch("p_1")
	check(waiting.size() == 1 and waiting[0].id == second, "the new start stays queued for a later flush: %s" % [waiting])
	_done()


func test_a_batch_holds_at_most_32_snapshots_in_16384_bytes_and_only_sent_ones_are_acknowledged() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var ids := []
	for i in 40:
		ids.append(_c.record_play_start(row.sha256))
	check(not ids.has(""), "setup: forty starts must record")
	_auto_nonces(net)
	# An overbroad answer: the server (or a bug) acknowledges all forty although only the batch was sent.
	net.respond("POST", "/plays", func(_r: Dictionary) -> Dictionary: return {"status": 200, "body": _ack(ids.map(func(i: String) -> Array: return [i, 1]))})
	for i in 4:
		await _cooldown()
		await _c.sync_feedback()
	var plays := _plays(net)
	var sent := []
	for play in plays:
		var attempts := _attempts(play)
		check(attempts.size() <= 32 and play.body.size() <= 16384, "a batch is at most 32 snapshots and 16384 bytes: %d snapshots, %d bytes" % [attempts.size(), play.body.size()])
		sent.append_array(attempts.map(func(a: Dictionary) -> String: return a.id))
	check(not plays.is_empty() and _attempts(plays[0]).size() == 32 and _attempts(plays[0]).map(func(a: Dictionary) -> String: return a.id) == ids.slice(0, 32), "the first batch is the 32 oldest")
	for id: String in ids:
		check(sent.has(id), "an acknowledgment for records that were not in the batch must not clear them: %s was never sent" % id)
	check(_disk().batch("p_1").is_empty(), "everything sent and acknowledged leaves the outbox empty")
	_done()


func test_a_deferred_flush_runs_by_itself_once_the_cadence_allows_it() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var second: String = await _held_back(net, row)
	var early: Dictionary = await _c.sync_feedback()
	check(early.get("pending") == true and net.count("POST", "/plays") == 1, "inside the gap a sync only says Pending sync: %s" % [early])
	await _cooldown()
	var ran: bool = await _until(func() -> bool: return net.count("POST", "/plays") >= 2, 120)
	check(ran, "the deferred flush must run by itself after the gap")
	var last := _attempts(_plays(net).back()) if ran else []
	check(last.any(func(a: Dictionary) -> bool: return a.id == second), "the deferred flush carries the queued start: %s" % [last])
	_done()


func test_a_deferred_flush_does_not_outlive_a_reset() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	await _held_back(net, row)
	Community.use_defaults()  # what the runner does before every test
	Community.transport = net
	Community.platform = pilot
	await _cooldown()
	await frames(5)
	check(net.count("POST", "/plays") == 1, "a timer from before the reset must not flush afterwards: %s" % [_urls(net)])
	_done()


func test_a_flush_queued_by_a_play_in_the_same_frame_as_a_reset_neither_uploads_nor_signs_in() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	_auto_nonces(net)
	_auto_acks(net)
	var saved := ConfigFile.new()  # a 401 dropped the token: a flush that did run would have to sign in again
	saved.load(Community.session_path)
	saved.erase_section("session")
	saved.save(Community.session_path)
	_c.activate_feedback()
	var id: String = _c.record_play_start(row.sha256)  # each of these queues an idle-frame flush ...
	_c.record_play_finish(id, "failed")
	var signed_ins := pilot.sign_ins
	_restart(net)  # ... that the reset in the same frame must cancel, with the fakes put back as a test does
	await frames(5)
	check(net.count("POST", "/plays") == 0 and net.count("GET", "/nonce") == 0 and net.count("POST", "/session") == 0 and pilot.sign_ins == signed_ins, "a flush queued before the reset must neither upload nor sign in again: %s" % [_urls(net)])
	var waiting: Array = _disk().batch("p_1")
	check(waiting.size() == 1 and waiting[0].id == id and waiting[0].revision == 2, "the durable report is still waiting: %s" % [waiting])
	net.answer("POST", "/session", 200, {"token": "tok2", "player": {"id": "p_1", "name": "Pilot"}})
	_c.activate_feedback()  # control: entering the community again does send it
	var sent: bool = await _until(func() -> bool: return net.count("POST", "/plays") >= 1, 120)
	check(sent and _attempts(_plays(net)[0]).any(func(a: Dictionary) -> bool: return a.id == id), "control: the waiting report goes out after a fresh activation: %s" % [_urls(net)])
	_done()


# --- 401, account switches and deletion -------------------------------------------------------------------------------


func test_a_401_signs_in_once_with_a_fresh_nonce_and_resends_a_freshly_bound_report() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	net.answer("GET", "/nonce", 200, {"nonce": "n_a"})
	net.answer("POST", "/plays", 401, UNAUTHORIZED)
	net.answer("GET", "/nonce", 200, {"nonce": "n_b"})
	net.answer("POST", "/session", 200, {"token": "tok2", "player": {"id": "p_1", "name": "Pilot"}})
	net.answer("GET", "/nonce", 200, {"nonce": "n_c"})
	net.answer("POST", "/plays", 200, _ack([[id, 2]]))
	var result: Dictionary = await _c.sync_feedback()
	check(_steps(net) == ["GET /nonce", "POST /plays", "GET /nonce", "POST /session", "GET /nonce", "POST /plays"], "requests: %s" % [_steps(net)])
	var plays := _plays(net)
	if plays.size() == 2:
		check(_header(plays[0], "Authorization") == "Bearer tok1" and _header(plays[1], "Authorization") == "Bearer tok2", "the retry must carry the new token")
		check(_bound(plays[0], "n_a") and _bound(plays[1], "n_c"), "each report is bound to its own fresh nonce and its own bytes")
		check(JSON.stringify(_attempts(plays[0])) == JSON.stringify(_attempts(plays[1])), "the retry reports the same attempt")
	check(net.requests.size() >= 4 and net.requests[3].body.get_string_from_utf8().contains("ok:n_b"), "the silent sign-in uses a fresh nonce of its own")
	check(result.get("pending") == false and _disk().batch("p_1").is_empty(), "the retried report is acknowledged: %s" % [result])
	_done()


func test_a_second_401_keeps_the_report_queued_and_makes_no_third_upload() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	net.answer("GET", "/nonce", 200, {"nonce": "n_a"})
	net.answer("POST", "/plays", 401, UNAUTHORIZED)
	net.answer("GET", "/nonce", 200, {"nonce": "n_b"})
	net.answer("POST", "/session", 200, {"token": "tok2", "player": {"id": "p_1", "name": "Pilot"}})
	net.answer("GET", "/nonce", 200, {"nonce": "n_c"})
	net.answer("POST", "/plays", 401, UNAUTHORIZED)
	var result: Dictionary = await _c.sync_feedback()
	await frames(5)
	check(net.count("POST", "/plays") == 2 and net.count("POST", "/session") == 1, "exactly one silent sign-in and one retry: %s" % [_urls(net)])
	var waiting: Array = _disk().batch("p_1")
	check(result.get("pending") == true and waiting.size() == 1 and waiting[0].id == id, "the report stays queued: %s %s" % [result, waiting])
	_done()


func test_a_401_that_changes_the_player_never_posts_the_old_owners_bytes() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	pilot.account = "p_2"  # Play Games now has another account
	net.answer("GET", "/nonce", 200, {"nonce": "n_a"})
	net.answer("POST", "/plays", 401, UNAUTHORIZED)
	net.answer("GET", "/nonce", 200, {"nonce": "n_b"})
	net.answer("POST", "/session", 200, {"token": "tok2", "player": {"id": "p_2", "name": "Other"}})
	pilot.nonces.clear()
	await _c.sync_feedback()
	await frames(5)
	check(_c.player_id() == "p_2", "the silent sign-in belongs to the new player")
	check(net.count("POST", "/plays") == 1 and _header(_plays(net)[0], "Authorization") == "Bearer tok1", "p_1's bytes must never go out with p_2's token: %s" % [_urls(net)])
	check(net.count("GET", "/nonce") == 2 and pilot.nonces.size() == 2, "the owner is rechecked before any further nonce is fetched or signed: %d nonces, %d signed" % [net.count("GET", "/nonce"), pilot.nonces.size()])
	var h: Variant = _disk()
	check(h.batch("p_1").size() == 1 and h.owner_for_attempt(id) == "p_1" and h.batch("p_2").is_empty(), "p_1's record stays p_1's and still pending")
	_done()


func test_finishing_after_an_account_switch_changes_only_the_starting_owners_record() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net, "p_1", "tok1")
	var row: Dictionary = await _cached(net)
	var id_a: String = _c.record_play_start(row.sha256)
	await _sign_in(net, "p_2", "tok2")  # the scene of A's play is still on screen
	_c.record_play_finish(id_a, "cleared")
	var h: Variant = _disk()
	var a: Array = h.batch("p_1")
	check(a.size() == 1 and a[0].id == id_a and a[0].revision == 2 and a[0].outcome == "cleared" and h.owner_for_attempt(id_a) == "p_1", "A's own record is finished: %s" % [a])
	check(h.batch("p_2").is_empty(), "B gets no record from A's finish")
	var id_b: String = _c.record_play_start(row.sha256)
	net.answer("GET", "/nonce", 200, {"nonce": "n_b1"})
	net.answer("POST", "/plays", 200, _ack([[id_b, 1]]))
	await _c.sync_feedback()
	var plays := _plays(net)
	check(plays.size() == 1 and _header(plays[0], "Authorization") == "Bearer tok2" and _report(plays[0]).get("player_id") == "p_2", "B's report goes out as B: %s" % [_urls(net)])
	if plays.size() == 1:
		var ids := _attempts(plays[0]).map(func(x: Dictionary) -> String: return x.id)
		check(ids == [id_b], "A's attempt must not travel with B's token: %s" % [ids])
	_done()


func test_deleting_the_account_clears_this_owners_history_votes_and_cache_but_keeps_downloads() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256))
	await _c.feedback(LEVEL_ID, row.sha256)
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	net.respond("GET", "/nonce", func(_r: Dictionary) -> Dictionary: return {"status": 0})
	await _c.set_like(LEVEL_ID, true)
	check(_disk().pending_votes("p_1").size() == 1, "setup: a like is queued")
	net.responders.clear()
	net.answer("DELETE", "/me", 204)
	check(await Community.delete_account() == "", "deleting the account must succeed")
	var h: Variant = _disk()
	check(h.batch("p_1").is_empty() and h.pending_votes("p_1").is_empty() and h.owner_for_attempt(id) == "", "history and queued votes are erased")
	check(FileAccess.file_exists(Community.level_path(row.sha256)) and _c.level_info(row.sha256).get(META_LEVEL) == LEVEL_ID, "downloaded public levels stay")
	_c.record_play_finish(id, "failed")  # the scene of an erased attempt ends later
	check(_c.record_play_start(row.sha256) == "" and _attempt_count() == 0 and _c.player_id() == "", "an erased attempt's finish is a no-op and nobody is signed in to start a new one")
	await _sign_in(net, "p_1", "tok9")  # a later explicit sign-in, even as the same id, must find nothing of the old account
	net.answer("GET", FEEDBACK_PATH, 0)
	var cached: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(cached.has("error") and not cached.has("stats"), "the private feedback cache must be gone: %s" % [cached])
	check(_disk().batch("p_1").is_empty() and _disk().pending_votes("p_1").is_empty(), "signing in again does not bring the old queue back")
	_done()


func test_deleting_the_account_during_a_held_flush_recreates_no_history_and_starts_no_retry() -> void:
	for answer_status: int in [200, 401]:
		var net := _boot()
		if net == null:
			return
		await _sign_in(net)
		var row: Dictionary = await _cached(net)
		var id: String = _c.record_play_start(row.sha256)
		_c.record_play_finish(id, "failed")
		net.answer("GET", "/nonce", 200, {"nonce": "n_d1"})
		net.hold("POST", "/plays")
		var flushed := []
		var flush := func() -> void: flushed.append(await _c.sync_feedback())
		flush.call()
		await frames(3)
		if net.count("POST", "/plays") != 1:
			check(false, "setup: the upload must be in flight: %s" % [_urls(net)])
			_done()
			return
		net.answer("DELETE", "/me", 204)
		var deleted := []
		var erase := func() -> void: deleted.append(await Community.delete_account())
		erase.call()
		var signed_ins := pilot.sign_ins
		net.answer("POST", "/plays", answer_status, _ack([[id, 2]]) if answer_status == 200 else UNAUTHORIZED)
		net.release_hold("POST", "/plays")
		await frames(5)
		var tag := "held answer %d: " % answer_status
		check(deleted == [""], tag + "the deletion must complete: %s" % [deleted])
		check(flushed.size() == 1, tag + "the flush must end")
		var h: Variant = _disk()
		check(h.batch("p_1").is_empty() and h.owner_for_attempt(id) == "" and _attempt_count() == 0, tag + "the late answer must not recreate the erased history")
		check(not Community.signed_in() and _c.player_id() == "", tag + "the session stays erased")
		check(net.count("POST", "/plays") == 1 and net.count("POST", "/session") == 0 and pilot.sign_ins == signed_ins, tag + "no retry and no silent sign-in for erased activity: %s" % [_urls(net)])
		_done()


func test_a_sign_in_started_before_the_account_was_deleted_cannot_restore_the_session() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	pilot.sign_in_held = true
	net.answer("GET", "/nonce", 200, {"nonce": "n_re"})
	var again := func() -> void: await Community.sign_in()
	again.call()
	await frames(3)
	net.answer("DELETE", "/me", 204)
	var deleted := []
	var erase := func() -> void: deleted.append(await Community.delete_account())
	erase.call()
	await frames(3)
	net.answer("POST", "/session", 200, {"token": "tok_stale", "player": {"id": "p_1", "name": "Pilot"}})
	pilot.release_sign_in()
	await frames(5)
	check(deleted == [""], "the deletion completes: %s" % [deleted])
	check(not Community.signed_in() and _c.player_id() == "", "a sign-in that was under way when the account was erased must not bring the old session or player back")
	var h: Variant = _disk()
	check(h.batch("p_1").is_empty() and h.owner_for_attempt(id) == "", "nor the old history")
	_done()


func test_a_failed_local_erasure_after_a_remote_delete_is_no_success_and_old_activity_never_goes_out() -> void:
	var net := _boot(LOCKED_HISTORY)
	if net == null:
		return
	check(Community.session_path.get_base_dir() != LOCKED.trim_suffix("/") and not Community.session_path.begins_with(LOCKED), "control: the session file lives apart from the history folder, so only the history cannot be written")
	DirAccess.make_dir_recursive_absolute(LOCKED)
	await _sign_in(net, "p_2", "tok2")  # another account on this device: it must come through untouched
	var row: Dictionary = await _cached(net)
	var other: String = _c.record_play_start(row.sha256)
	await _sign_in(net, "p_1", "tok1")
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "failed")
	net.respond("GET", "/nonce", func(_r: Dictionary) -> Dictionary: return {"status": 0})
	await _c.set_like(LEVEL_ID, true)
	net.responders.clear()
	var before: Variant = _disk(LOCKED_HISTORY)
	check(other != "" and id != "" and before.batch("p_1").size() == 1 and before.pending_votes("p_1").size() == 1 and before.batch("p_2").size() == 1, "setup: p_1 has a queued play and like, p_2 a queued start")
	if not _lock(LOCKED):
		_done()
		return
	net.answer("DELETE", "/me", 204)
	var result: String = await Community.delete_account()
	check(result != "", "the server deleted the account but its history could not be erased here: that must not read as a successful deletion")
	check(_disk(LOCKED_HISTORY).batch("p_1").size() == 1, "control: the failed save left the old queue in the file, so only the client can keep it from going out")
	# The same session, signed in again as the same player (an explicit action).
	await _sign_in(net, "p_1", "tok9")
	_auto_nonces(net)
	_auto_acks(net)
	net.respond("POST", LIKE_PATH, func(_r: Dictionary) -> Dictionary: return {"status": 200, "body": {"likes": 1}})
	_c.record_play_finish(id, "failed")  # the scene of the erased attempt ends later
	await _cooldown()
	await _c.sync_feedback()
	await _cooldown()
	check(_writes(net).is_empty(), "erased activity must not be sent after signing in again: %s" % [_steps(net)])
	# A relaunch: timers and the loaded history are gone, the files stay.
	_restart(net)
	_auto_nonces(net)
	_auto_acks(net)
	net.respond("POST", LIKE_PATH, func(_r: Dictionary) -> Dictionary: return {"status": 200, "body": {"likes": 1}})
	_c.activate_feedback()
	await _cooldown()
	await _c.sync_feedback()
	await _cooldown()
	check(_writes(net).is_empty(), "nor after a restart, in the background or on demand: %s" % [_steps(net)])
	check(_c.pending_feedback(LEVEL_ID, row.sha256).is_empty(), "a choice of the erased account is not shown as pending: %s" % [_c.pending_feedback(LEVEL_ID, row.sha256)])
	# The folder is writable again: the erasure completes and nothing of the old account comes back.
	_unlock(LOCKED)
	_c.record_play_finish(id, "failed")
	await _cooldown()
	await _c.sync_feedback()
	await _cooldown()
	var after: Variant = _disk(LOCKED_HISTORY)
	check(_writes(net).is_empty(), "nothing of the erased account goes out once the folder is writable: %s" % [_steps(net)])
	check(after.batch("p_1").is_empty() and after.pending_votes("p_1").is_empty() and after.owner_for_attempt(id) == "", "the erasure completes on disk: %s %s" % [after.batch("p_1"), after.pending_votes("p_1")])
	check(after.batch("p_2").size() == 1 and after.owner_for_attempt(other) == "p_2", "the other account's history is preserved")
	check(FileAccess.file_exists(Community.level_path(row.sha256)) and _c.level_info(row.sha256).get(META_LEVEL) == LEVEL_ID, "downloaded public levels are preserved")
	_done()


func test_a_private_cache_that_cannot_be_removed_is_no_deletion_success_and_is_never_served_afterwards() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"liked": true, "attempts": 4321}))
	var live: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(not live.has("error") and _private_files().size() == 1, "setup: the private payload is cached for this player: %s" % [_private_files()])
	if not _lock(Community.dir):  # files stay readable, but none can be removed
		_done()
		return
	net.answer("DELETE", "/me", 204)
	var result: String = await Community.delete_account()
	check(result != "", "the account is gone on the server but its private cache could not be removed here: that must not read as a successful deletion")
	await _sign_in(net, "p_1", "tok9")
	net.answer("GET", FEEDBACK_PATH, 0)
	var offline: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.has("error") and not offline.has("you") and not offline.has("stats"), "an erased account's cache is never served again: %s" % [offline])
	_restart(net)  # a relaunch: the files stay
	net.answer("GET", FEEDBACK_PATH, 0)
	offline = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.has("error") and not offline.has("you") and not offline.has("stats"), "nor after a restart: %s" % [offline])
	_unlock(Community.dir)
	await _c.sync_feedback()
	net.answer("GET", FEEDBACK_PATH, 0)
	offline = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.has("error") and not offline.has("you") and _private_files().is_empty(), "once the folder is writable the erasure completes: %s %s" % [offline, _private_files()])
	check(FileAccess.file_exists(Community.level_path(row.sha256)) and _c.level_info(row.sha256).get(META_LEVEL) == LEVEL_ID, "downloaded public levels are preserved")
	_done()


func test_a_private_cache_in_an_unlistable_folder_is_no_deletion_success_and_is_never_served_afterwards() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"liked": true, "attempts": 4321}))
	var live: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	var names := _private_files()
	check(not live.has("error") and names.size() == 1, "setup: the private payload is cached for this player: %s" % [names])
	if names.size() != 1:
		_done()
		return
	var known: String = Community.dir + names[0]  # captured while the folder can still be listed
	if not _lock(Community.dir, "111"):  # search only: a known name opens, nothing can be listed, created or removed
		_done()
		return
	var cache_dir := DirAccess.open(Community.dir)
	var listing_failed := cache_dir == null or cache_dir.list_dir_begin() != OK
	if cache_dir != null:
		cache_dir.list_dir_end()
	check(FileAccess.get_file_as_string(known).contains("you") and listing_failed, "control: the known private file is readable while the folder cannot be listed (so a listing that looks empty proves nothing)")
	net.answer("DELETE", "/me", 204)
	var result: String = await Community.delete_account()
	check(result != "", "the account is gone on the server but the private cache cannot be listed or removed here: that must not read as a successful deletion")
	check(FileAccess.get_file_as_string(known).contains("you"), "control: the file is still there, so only the client can keep it from being served")
	await _sign_in(net, "p_1", "tok9")
	net.answer("GET", FEEDBACK_PATH, 0)
	var offline: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.has("error") and not offline.has("you") and not offline.has("stats"), "an erased account's cache is never served again: %s" % [offline])
	_restart(net)  # a relaunch: the files stay
	net.answer("GET", FEEDBACK_PATH, 0)
	offline = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.has("error") and not offline.has("you") and not offline.has("stats"), "nor after a restart: %s" % [offline])
	_unlock(Community.dir)
	await _c.sync_feedback()
	net.answer("GET", FEEDBACK_PATH, 0)
	offline = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.has("error") and not offline.has("you") and not FileAccess.file_exists(known), "the next explicit entry after the folder is listable again erases the private file: %s" % [offline])
	check(FileAccess.file_exists(Community.level_path(row.sha256)) and _c.level_info(row.sha256).get(META_LEVEL) == LEVEL_ID, "downloaded public levels are preserved")
	_done()


# --- feedback reads and the per-owner cache ---------------------------------------------------------------------------


func test_feedback_returns_the_servers_payload_and_serves_only_this_owners_cache_offline() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net, "p_1", "tok1")
	var row: Dictionary = await _cached(net)
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"difficulty": "hard", "attempts": 3}))
	var live: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(net.requests.size() == 1 and net.requests[0].url.ends_with(FEEDBACK_PATH + "?sha256=" + row.sha256) and _header(net.requests[0], "Authorization") == "Bearer tok1", "one authorized read of this version: %s" % [_urls(net)])
	check(not live.has("error") and live.get("offline") == false and live.stats.players_started == 12 and live.stats.clear_rate == 0.25 and live.community_difficulty.value == "normal" and live.you.difficulty == "hard", "the payload is the server's: %s" % [live])
	net.answer("GET", FEEDBACK_PATH, 0)
	var offline: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.get("offline") == true and offline.stats.players_started == 12 and offline.stats.clear_rate == 0.25 and offline.stats.median_tries == 3 and offline.you.difficulty == "hard", "offline serves the cached payload as it was, never recomputed: %s" % [offline])
	await _sign_in(net, "p_2", "tok2")
	net.answer("GET", FEEDBACK_PATH, 0)
	var other: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(other.has("error") and other.get("offline") == true and not other.has("you"), "another account must not see p_1's cached payload: %s" % [other])
	_done()


func test_a_feedback_answer_held_across_an_account_switch_is_not_cached_for_the_new_owner() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net, "p_1", "tok1")
	var row: Dictionary = await _cached(net)
	net.hold("GET", FEEDBACK_PATH)
	var out := []
	var read := func() -> void: out.append(await _c.feedback(LEVEL_ID, row.sha256))
	read.call()
	await frames(3)
	await _sign_in(net, "p_2", "tok2")
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"liked": true, "attempts": 4321}))
	net.release_hold("GET", FEEDBACK_PATH)
	await frames(5)
	net.queue.clear()
	net.answer("GET", FEEDBACK_PATH, 0)
	var other: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(other.has("error") and not other.has("you"), "p_1's private answer must not become p_2's cache: %s" % [other])
	_done()


func test_deleting_the_account_during_a_held_feedback_read_does_not_cache_it_afterwards() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.hold("GET", FEEDBACK_PATH)
	var out := []
	var read := func() -> void: out.append(await _c.feedback(LEVEL_ID, row.sha256))
	read.call()
	await frames(3)
	net.answer("DELETE", "/me", 204)
	var deleted := []
	var erase := func() -> void: deleted.append(await Community.delete_account())
	erase.call()
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"attempts": 4321}))
	net.release_hold("GET", FEEDBACK_PATH)
	await frames(5)
	check(deleted == [""], "the deletion must complete: %s" % [deleted])
	await _sign_in(net, "p_1", "tok9")
	net.answer("GET", FEEDBACK_PATH, 0)
	var cached: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(cached.has("error") and not cached.has("you"), "a read answered after the erase must not leave private data behind: %s" % [cached])
	_done()


# --- likes and difficulty votes ---------------------------------------------------------------------------------------


func test_offline_votes_keep_the_latest_choice_and_the_plays_go_out_before_any_vote() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var id: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(id, "cleared")
	net.respond("GET", "/nonce", func(_r: Dictionary) -> Dictionary: return {"status": 0})
	var easy: Dictionary = await _c.set_difficulty(LEVEL_ID, row.sha256, "easy")
	var hard: Dictionary = await _c.set_difficulty(LEVEL_ID, row.sha256, "hard")
	var liked: Dictionary = await _c.set_like(LEVEL_ID, true)
	check(easy.get("pending") == true and hard.get("pending") == true and liked.get("pending") == true, "offline choices read as Pending sync: %s" % [[easy, hard, liked]])
	var votes: Array = _disk().pending_votes("p_1")
	check(votes.size() == 2 and _vote(votes, "difficulty", row.sha256).get("value") == "hard" and _vote(votes, "like", "").get("value") == true, "one queued value per choice, the latest one: %s" % [votes])
	check(net.count("PUT", DIFFICULTY_PATH) == 0 and net.count("POST", LIKE_PATH) == 0, "no vote may go out ahead of the play history it needs")
	var queued: Dictionary = _c.pending_feedback(LEVEL_ID, row.sha256)
	check(queued.get(PENDING_DIFFICULTY) == "hard" and queued.get(PENDING_LIKE) == true, "the queued selections are shown: %s" % [queued])
	net.responders.clear()
	net.requests.clear()
	net.answer("GET", "/nonce", 200, {"nonce": "n_p"})
	net.answer("POST", "/plays", 200, _ack([[id, 2]]))
	_eligible(net, row.sha256)
	net.answer("PUT", DIFFICULTY_PATH, 200, {"difficulty": "hard"})
	net.answer("POST", LIKE_PATH, 200, {"likes": 1})
	await _cooldown()
	var done: Dictionary = await _c.sync_feedback()
	var writes := _steps(net).filter(func(s: String) -> bool: return not s.begins_with("GET"))
	check(writes.size() == 3 and writes[0] == "POST /plays" and writes.has("PUT " + DIFFICULTY_PATH) and writes.has("POST " + LIKE_PATH), "plays first, then each vote once, 'easy' never: %s" % [writes])
	var put := net.requests.filter(func(r: Dictionary) -> bool: return r.method == "PUT")
	check(put.size() == 1 and JSON.parse_string(put[0].body.get_string_from_utf8()) == {"sha256": row.sha256, "difficulty": "hard"} and _header(put[0], "Authorization") == "Bearer tok1", "the vote body is the latest choice: %s" % [put])
	check(done.get("pending") == false and _disk().pending_votes("p_1").is_empty() and not _c.pending_feedback(LEVEL_ID, row.sha256).has(PENDING_DIFFICULTY), "nothing stays pending: %s" % [done])
	_done()


func test_a_vote_stays_queued_when_the_connection_fails() -> void:
	await _check_retained(0)


func test_a_vote_stays_queued_when_the_server_fails() -> void:
	await _check_retained(500)
	await _check_retained(503)


func test_a_429_keeps_the_vote_queued_and_waits_for_a_later_flush_instead_of_looping() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	_eligible(net, row.sha256)
	net.answer("PUT", DIFFICULTY_PATH, 429, {"error": "Too many requests."})
	var first: Dictionary = await _c.set_difficulty(LEVEL_ID, row.sha256, "hard")
	await frames(10)
	check(first.get("pending") == true and net.count("PUT", DIFFICULTY_PATH) == 1, "a 429 keeps the vote pending without an immediate retry: %s" % [first])
	var early: Dictionary = await _c.sync_feedback()
	check(early.get("pending") == true and net.count("PUT", DIFFICULTY_PATH) == 1, "inside the gap a sync only says Pending sync: %s" % [early])
	net.answer("PUT", DIFFICULTY_PATH, 200, {"difficulty": "hard"})
	await _cooldown()
	var later: Dictionary = await _c.sync_feedback()
	check(net.count("PUT", DIFFICULTY_PATH) == 2 and later.get("pending") == false and _disk().pending_votes("p_1").is_empty(), "a later flush sends it again and clears it: %s" % [later])
	_done()


func test_a_permanent_refusal_drops_the_queued_vote_restores_the_confirmed_state_and_shows_the_sentence() -> void:
	for status: int in [400, 403, 404]:
		await _check_refused(status)


func test_a_refused_like_is_removed_and_the_confirmed_state_returns() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"liked": false}))
	await _c.feedback(LEVEL_ID, row.sha256)
	net.queue.clear()
	net.answer("POST", LIKE_PATH, 403, {"error": "Play this level first."})
	var result: Dictionary = await _c.set_like(LEVEL_ID, true)
	check(result.get("error") == "Play this level first." and result.get("pending") == false, "the refusal sentence comes back, nothing pending: %s" % [result])
	check(_disk().pending_votes("p_1").is_empty() and not _c.pending_feedback(LEVEL_ID, row.sha256).has(PENDING_LIKE), "the refused like is removed")
	await _cooldown()
	await _c.sync_feedback()
	check(net.count("POST", LIKE_PATH) == 1, "a refused like is not retried")
	net.answer("GET", FEEDBACK_PATH, 0)
	var offline: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.get("offline") == true and offline.you.liked == false, "the confirmed state is what shows: %s" % [offline])
	_done()


func test_a_refused_votes_failed_acknowledgment_save_is_a_history_error_and_settles_locally_without_asking_the_server_again() -> void:
	var net := _boot(LOCKED_HISTORY)
	if net == null:
		return
	DirAccess.make_dir_recursive_absolute(LOCKED)
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"difficulty": "normal"}))
	await _c.feedback(LEVEL_ID, row.sha256)  # the confirmed vote is normal
	var refusal := "Play this level first."
	var settled := []  # the error of every vote_result
	var listener := func(_account: String, _kind: String, _level: String, _sha: String, _value: Variant, error: String) -> void: settled.append(error)
	_c.vote_result.connect(listener)
	net.hold("PUT", DIFFICULTY_PATH)
	net.answer("PUT", DIFFICULTY_PATH, 403, {"error": refusal})
	var results := []
	var vote := func() -> void: results.append(await _c.set_difficulty(LEVEL_ID, row.sha256, "hard"))
	vote.call()
	await frames(3)
	check(net.count("PUT", DIFFICULTY_PATH) == 1 and _disk(LOCKED_HISTORY).pending_votes("p_1").size() == 1, "setup: the vote is queued on disk and its request is out: %d" % net.count("PUT", DIFFICULTY_PATH))
	var before := FileAccess.get_file_as_bytes(LOCKED_HISTORY)
	if not _lock(LOCKED):  # the history folder only: the session and downloads stay writable
		_c.vote_result.disconnect(listener)
		_done()
		return
	net.release_hold("PUT", DIFFICULTY_PATH)  # the refusal arrives, and its acknowledgment cannot be saved
	await frames(3)
	var failed: Dictionary = results[0] if results.size() == 1 else {}
	check(results.size() == 1 and failed.get("error", "") != "" and failed.get("error") != refusal, "the storage failure is reported, not the server's refusal as if settled: %s" % [results])
	check(not settled.has(refusal), "no ordinary refusal is signalled while it cannot be recorded: %s" % [settled])
	check(FileAccess.get_file_as_bytes(LOCKED_HISTORY) == before and _disk(LOCKED_HISTORY).pending_votes("p_1").size() == 1, "the history file keeps its original bytes, the vote still queued")
	_unlock(LOCKED)  # the filesystem works again
	await _cooldown()
	var again: Dictionary = await _c.sync_feedback()
	await frames(3)
	check(net.count("PUT", DIFFICULTY_PATH) == 1, "the refused request is not sent again while this process knows its outcome: %d" % net.count("PUT", DIFFICULTY_PATH))
	check(_disk(LOCKED_HISTORY).pending_votes("p_1").is_empty() and _c.pending_feedback(LEVEL_ID, row.sha256).is_empty() and again.get("pending") == false, "the known outcome settles locally once the save works: %s %s" % [_disk(LOCKED_HISTORY).pending_votes("p_1"), again])
	check(settled.count(refusal) == 1, "and its refusal is signalled once, now: %s" % [settled])
	_c.vote_result.disconnect(listener)
	_done()


func test_a_refused_choice_can_be_requested_again_later_as_a_new_revision() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.answer("POST", LIKE_PATH, 403, {"error": "Play this level first."})
	var refused: Dictionary = await _c.set_like(LEVEL_ID, true)
	check(refused.get("error") == "Play this level first." and refused.get("pending") == false and _disk().pending_votes("p_1").is_empty(), "setup: the first like is refused and dropped: %s" % [refused])
	var first_revision := 1
	net.answer("POST", LIKE_PATH, 500, {"error": "Try again later."})  # the player became eligible and asks for the same like again
	var again: Dictionary = await _c.set_like(LEVEL_ID, true)
	var votes: Array = _disk().pending_votes("p_1")
	check(net.count("POST", LIKE_PATH) == 2, "the same choice asked for again must be sent again: %s" % [_urls(net)])
	check(again.get("pending") == true and votes.size() == 1 and votes[0].value == true and int(votes[0].revision) > first_revision, "the new request is a pending new revision: %s %s" % [again, votes])
	check(_c.pending_feedback(LEVEL_ID, row.sha256).get(PENDING_LIKE) == true, "the queued like is shown")
	net.answer("POST", LIKE_PATH, 200, {"likes": 1})
	await _cooldown()
	var later: Dictionary = await _c.sync_feedback()
	check(later.get("pending") == false and net.count("POST", LIKE_PATH) == 3 and _disk().pending_votes("p_1").is_empty(), "the retry goes through and clears the queue: %s" % [later])
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"liked": true}))
	var confirmed: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(confirmed.get("offline") == false and confirmed.you.liked == true, "the new confirmed state shows: %s" % [confirmed])
	_done()


func test_a_late_acknowledgment_of_an_older_choice_does_not_clear_a_newer_one() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	_eligible(net, row.sha256)
	net.hold("PUT", DIFFICULTY_PATH)
	var out := []
	var vote := func(value: String) -> void: out.append(await _c.set_difficulty(LEVEL_ID, row.sha256, value))
	vote.call("easy")
	await frames(3)
	if net.count("PUT", DIFFICULTY_PATH) != 1:
		check(false, "setup: the first vote must be in flight: %s" % [_urls(net)])
		_done()
		return
	vote.call("hard")
	check(out.size() == 1 and out[0].get("pending") == true, "the newer choice returns Pending sync while a flush is in flight: %s" % [out])
	net.answer("PUT", DIFFICULTY_PATH, 200, {"difficulty": "easy"})
	net.release_hold("PUT", DIFFICULTY_PATH)
	await frames(3)
	var votes: Array = _disk().pending_votes("p_1")
	check(votes.size() == 1 and votes[0].value == "hard", "the answer for 'easy' must leave 'hard' queued: %s" % [votes])
	net.answer("PUT", DIFFICULTY_PATH, 200, {"difficulty": "hard"})
	await _cooldown()
	await _c.sync_feedback()
	var puts := net.requests.filter(func(r: Dictionary) -> bool: return r.method == "PUT")
	var labels := puts.map(func(r: Dictionary) -> Variant: return JSON.parse_string(r.body.get_string_from_utf8()).get("difficulty"))
	check(labels.size() >= 2 and labels[0] == "easy" and labels.back() == "hard" and labels.count("easy") == 1, "'easy' goes once, then the latest 'hard': %s" % [labels])
	check(_disk().pending_votes("p_1").is_empty() and not _c.pending_feedback(LEVEL_ID, row.sha256).has(PENDING_DIFFICULTY), "the newest choice ends up applied")
	_done()


func test_two_difficulty_choices_made_during_a_held_sign_in_end_with_the_latest_one() -> void:
	var net := _boot()
	if net == null:
		return
	var sha: String = _row().sha256
	var server := _held_sign_in(net)
	var out := []
	var vote := func(value: String) -> void: out.append(await _c.set_difficulty(LEVEL_ID, sha, value))
	vote.call("easy")
	await frames(3)
	check(pilot.sign_ins == 1, "setup: the first choice is waiting in the held sign-in")
	vote.call("hard")  # the later choice, made while that sign-in is still open
	await frames(3)
	check(pilot.sign_ins == 1 and net.count("PUT", DIFFICULTY_PATH) == 0 and not FileAccess.file_exists(HISTORY), "setup: nothing is sent or stored before the player is known: %s" % [_urls(net)])
	pilot.release_sign_in()
	await frames(5)
	var labels := net.requests.filter(func(r: Dictionary) -> bool: return r.method == "PUT").map(func(r: Dictionary) -> Variant: return JSON.parse_string(r.body.get_string_from_utf8()).get("difficulty"))
	check(out.size() == 2, "both calls return: %s" % [out])
	check(server.get("difficulty") == "hard" and not labels.is_empty() and labels.back() == "hard", "the latest choice made is the one the server ends with: server %s, sent %s" % [server.get("difficulty"), labels])
	check(_disk().pending_votes("p_1").is_empty(), "nothing older stays pending: %s" % [_disk().pending_votes("p_1")])
	_done()


func test_a_like_toggled_twice_during_a_held_sign_in_ends_with_the_latest_value() -> void:
	var net := _boot()
	if net == null:
		return
	var server := _held_sign_in(net)
	var out := []
	var toggle := func(value: bool) -> void: out.append(await _c.set_like(LEVEL_ID, value))
	toggle.call(true)
	await frames(3)
	check(pilot.sign_ins == 1, "setup: the first choice is waiting in the held sign-in")
	toggle.call(false)
	await frames(3)
	check(pilot.sign_ins == 1 and net.count("POST", LIKE_PATH) + net.count("DELETE", LIKE_PATH) == 0 and not FileAccess.file_exists(HISTORY), "setup: nothing is sent or stored before the player is known: %s" % [_urls(net)])
	pilot.release_sign_in()
	await frames(5)
	var likes := _steps(net).filter(func(s: String) -> bool: return s.ends_with("/like"))
	check(out.size() == 2, "both calls return: %s" % [out])
	check(server.get("liked") == false and not likes.is_empty() and likes.back() == "DELETE " + LIKE_PATH, "the latest value is the one the server ends with: server %s, sent %s" % [server.get("liked"), likes])
	check(_disk().pending_votes("p_1").is_empty(), "nothing older stays pending: %s" % [_disk().pending_votes("p_1")])
	_done()


# --- local progress ---------------------------------------------------------------------------------------------------


func test_local_progress_counts_a_pending_finish_once_and_separates_unsent_starts() -> void:
	var h: Variant = _history()
	if h == null:
		return
	var sha := "a".repeat(64)
	var id: String = h.begin("p_1", LEVEL_ID, sha, 1000)
	h.finish("p_1", id, "failed", 1500)
	var progress: Dictionary = h.local_progress("p_1", LEVEL_ID, sha)
	check(progress.get("attempts") == 1 and progress.get("pending_starts") == 1 and progress.get("pending") == true and progress.get("cleared") == false, "an unsent attempt is one try and one pending start: %s" % [progress])
	h.acknowledge("p_1", {"acknowledged": [{"id": id, "revision": 1}], "discarded": [], "cleared": []})
	progress = h.local_progress("p_1", LEVEL_ID, sha)
	check(progress.get("attempts") == 1 and progress.get("pending_starts") == 0 and progress.get("pending") == true, "an acknowledged start with a pending finish is still one try, not another start: %s" % [progress])
	h.acknowledge("p_1", {"acknowledged": [{"id": id, "revision": 2}], "discarded": [], "cleared": []})
	progress = h.local_progress("p_1", LEVEL_ID, sha)
	check(progress.get("attempts") == 1 and progress.get("pending_starts") == 0 and progress.get("pending") == false, "acknowledged records stay history, not outbox: %s" % [progress])
	h.begin("p_1", LEVEL_ID, sha, 3000)
	check(h.local_progress("p_1", LEVEL_ID, sha).get("attempts") == 2 and h.local_progress("p_1", LEVEL_ID, sha).get("pending_starts") == 1, "a new start counts")
	check(h.local_progress("p_1", LEVEL_ID, "b".repeat(64)).get("attempts") == 0 and h.local_progress("p_2", LEVEL_ID, sha).get("attempts") == 0, "another version or another account has its own count")
	_wipe()


func test_local_progress_stops_counting_at_the_earliest_local_clear() -> void:
	var h: Variant = _history()
	if h == null:
		return
	var sha := "a".repeat(64)
	var failed: String = h.begin("p_1", LEVEL_ID, sha, 1000)
	h.finish("p_1", failed, "failed", 1100)
	var win: String = h.begin("p_1", LEVEL_ID, sha, 2000)
	h.begin("p_1", LEVEL_ID, sha, 3000)  # started before the clear was known, ends after it
	h.finish("p_1", win, "cleared", 2500)
	var progress: Dictionary = h.local_progress("p_1", LEVEL_ID, sha)
	check(progress.get("cleared") == true and progress.get("attempts") == 2, "the failed try and the winning one count, the start after the clear does not: %s" % [progress])
	h.acknowledge("p_2", {"acknowledged": [], "discarded": [], "cleared": [sha]})
	var verified: Dictionary = h.local_progress("p_2", LEVEL_ID, sha)
	check(verified.get("cleared") == true and verified.get("attempts") == 0, "a server-reported clear invents no tries: %s" % [verified])
	_wipe()


func test_the_rating_offer_opens_after_five_local_tries_or_a_clear_without_server_eligibility() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	check(_c.play_progress(row.sha256).get("can_offer_rating") == false, "no play yet: nothing to rate")
	for i in 4:
		_c.record_play_finish(_c.record_play_start(row.sha256), "failed")
	check(_c.play_progress(row.sha256).get("can_offer_rating") == false, "four tries are not enough")
	_c.record_play_finish(_c.record_play_start(row.sha256), "failed")
	check(_c.play_progress(row.sha256).get("can_offer_rating") == true, "the fifth local try opens Rate level")
	check(net.requests.is_empty(), "discovering it asks the server nothing")
	_done()


# --- public metadata, downloads and submissions -----------------------------------------------------------------------


func test_a_cache_hit_still_saves_the_public_meta_and_repairs_a_damaged_one() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row := _place_level()
	check(not FileAccess.file_exists(_meta_path(row.sha256)) and _c.level_info(row.sha256).is_empty(), "control: no meta yet")
	check(await Community.download(row) == "" and net.requests.is_empty(), "a cache hit needs no request: %s" % [_urls(net)])
	var meta := _meta(row.sha256)
	check(meta.get(META_LEVEL) == LEVEL_ID and int(meta.get(META_VERSION, -1)) == 2, "the stable level id and version are saved with the cached file: %s" % [meta])
	check(not meta.has("you") and not meta.has("liked") and not meta.has("difficulty"), "public meta carries nothing private: %s" % [meta])
	var info: Dictionary = _c.level_info(row.sha256)
	check(info.get(META_LEVEL) == LEVEL_ID and int(info.get(META_VERSION, -1)) == 2, "level_info reads it: %s" % [info])
	check(_c.level_info("0".repeat(64)).is_empty(), "an unknown version has no info")
	for damaged: String in ["{\"level_id\": 7", "{\"level_id\": 7, \"version\": 2}"]:
		var file := FileAccess.open(_meta_path(row.sha256), FileAccess.WRITE)
		file.store_string(damaged)
		file.close()
		check(_c.level_info(row.sha256).is_empty(), "a meta file that is not valid reads as none: %s" % damaged)
		check(await Community.download(row) == "" and _c.level_info(row.sha256).get(META_LEVEL) == LEVEL_ID, "a cache hit repairs it: %s" % damaged)
	_done()


func test_a_fresh_download_saves_the_public_meta_and_never_sends_the_token_to_the_cdn() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var bytes := LevelFormat.to_json(LevelDoc.blank()).to_utf8_buffer()
	var row := {"level_id": LEVEL_ID, "title": "Loop", "author": "Pilot", "latest": 2, "sha256": CommunityWire.sha256_hex(bytes), "likes": 0, "players": 0}
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	check(await Community.download(row) == "", "the download must succeed")
	var cdn := net.requests.filter(func(r: Dictionary) -> bool: return r.url.begins_with("https://cdn.jsdelivr.net/"))
	check(cdn.size() == 1 and _header(cdn[0], "Authorization") == "", "the session token must never go to jsDelivr")
	check(_meta(row.sha256).get(META_LEVEL) == LEVEL_ID and int(_meta(row.sha256).get(META_VERSION, -1)) == 2, "the meta is saved with a fresh download too")
	check(not FileAccess.get_file_as_string(_meta_path(row.sha256)).contains("tok1"), "no token in public meta")
	_done()


func test_a_submission_with_a_suggested_difficulty_binds_it_as_the_third_part() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var id := _draft_with_demo()
	var level := LevelFormat.to_json(MyLevels.load_level(id)).to_utf8_buffer()
	var demo := FileAccess.get_file_as_bytes(MyLevels.demo_path(id))
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	check(await _c.submit(id, "hard") == "", "the submission must succeed")
	var post: Dictionary = net.requests[1] if net.requests.size() > 1 else {}
	var boundary := _header(post, "Content-Type").get_slice("boundary=", 1)
	var files := {"level": ["level.json", level], "demo": ["demo.gz", demo]}
	check(post.get("body") == CommunityWire.multipart({"suggested_difficulty": "hard"}, files, boundary), "the body carries the suggestion as a form field")
	var parts: Array[PackedByteArray] = [level, demo, "hard".to_utf8_buffer()]
	check(_header(post, "X-Nonce") == "n2" and _header(post, "X-Integrity") == "ok:" + CommunityWire.bound_nonce("n2", parts), "integrity is bound to the level, the demo and the suggestion's UTF-8 bytes")
	_done()


func test_another_stages_blocking_failure_is_not_this_actions_error() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	net.respond("PUT", DIFFICULTY_PATH, func(_r: Dictionary) -> Dictionary: return {"status": 429, "body": {"error": "Too many requests."}})
	net.respond("POST", OTHER_LIKE_PATH, func(_r: Dictionary) -> Dictionary: return {"status": 200, "body": {"likes": 1}})
	var first: Dictionary = await _c.set_difficulty(LEVEL_ID, row.sha256, "hard")
	check(first.get("pending") == true and net.count("PUT", DIFFICULTY_PATH) == 1, "setup: stage A's vote is kept after a 429: %s" % [first])
	await _cooldown()  # the retry gap passes: the next flush starts with stage A's vote
	var puts := net.count("PUT", DIFFICULTY_PATH)
	var other: Dictionary = await _c.set_like(OTHER_LEVEL_ID, true)
	check(net.count("PUT", DIFFICULTY_PATH) - puts == 1 and net.count("POST", OTHER_LIKE_PATH) == 0, "setup: stage A's retry goes first and its failure stops the flush before stage B's like: PUT %d, POST like %d" % [net.count("PUT", DIFFICULTY_PATH) - puts, net.count("POST", OTHER_LIKE_PATH)])
	check(other.get("error", "") == "" and other.get("pending") == true, "stage A's failure is not stage B's own error; B is only pending: %s" % [other])
	check(_c.pending_feedback(OTHER_LEVEL_ID, row.sha256).get(PENDING_LIKE) == true and _c.pending_feedback(LEVEL_ID, row.sha256).get(PENDING_DIFFICULTY) == "hard", "both choices stay queued")
	await _cooldown()
	var batch: Dictionary = await _c.sync_feedback()
	check(batch.get("error") == "Too many requests." and batch.get("pending") == true, "sync_feedback keeps the batch's own error, stage A's: %s" % [batch])
	_done()


# --- helpers ----------------------------------------------------------------------------------------------------------


## The fake world: paths redirected to test folders, history and fakes in place. Null (and one failed check) when the
## Task 6 interface is not there yet, or when a path would touch real user files. `history_file` is where the history lives.
func _boot(history_file := HISTORY) -> FakeTransport:
	var missing := PackedStringArray()
	for name: String in INTERFACE_METHODS:
		if not _c.has_method(name):
			missing.append(name + "()")
	for name: String in INTERFACE_PROPERTIES:
		if not (name in _c):
			missing.append(name)
	if not missing.is_empty():
		check(false, "Community lacks the Task 6 interface: " + ", ".join(missing))
		return null
	if not (Community.dir.begins_with("user://test_") and Community.session_path.begins_with("user://test_")):
		check(false, "Community must be redirected to test paths by the runner: %s %s" % [Community.dir, Community.session_path])
		return null
	for stranded: String in [LOCKED, Community.dir]:  # a test that died while a folder was read-only must not strand it
		if DirAccess.dir_exists_absolute(stranded):
			OS.execute("chmod", ["755", ProjectSettings.globalize_path(stranded)])
	_wipe()
	_wipe_dir(Community.dir)
	DirAccess.remove_absolute(Community.session_path)
	_c.history_path = history_file
	Community.use_defaults()
	Engine.time_scale = 1.0  # a test that failed mid-cooldown must not leave the clock fast
	var net := FakeTransport.new()
	world.add_child(net)  # freed with the world
	Community.transport = net
	Community.platform = pilot
	return net


## The end of every test: the reset the runner does, so no timer or loaded history outlives it.
func _done() -> void:
	for path in _locked.duplicate():
		_unlock(path)
	Community.use_defaults()
	_wipe()


func _wipe() -> void:
	_wipe_dir(DIR)


## Folders this test made read-only.
var _locked: Array[String] = []


## Makes `path` unwritable with a real permission change (a file cannot be created or removed in it); `mode` 555 leaves it listable, 111 (search only) leaves known file names readable but the listing impossible. False, and a failed check, when the platform did not enforce it (no chmod, or the test runs as root).
func _lock(path: String, mode := "555") -> bool:
	_locked.append(path)
	OS.execute("chmod", [mode, ProjectSettings.globalize_path(path)])
	var probe := path.path_join("probe.tmp")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file != null:
		file.close()
		DirAccess.remove_absolute(probe)
		check(false, "control: %s could not be made read-only here (no chmod, or running as root)" % path)
		return false
	return true


func _unlock(path: String) -> void:
	_locked.erase(path)
	OS.execute("chmod", ["755", ProjectSettings.globalize_path(path)])


## What a relaunch does: timers, activation and the loaded history are gone; files, session and downloads stay.
func _restart(net: FakeTransport) -> void:
	Community.use_defaults()
	Community.transport = net
	Community.platform = pilot


## The requests that carry a player's activity: play reports and votes.
func _writes(net: FakeTransport) -> Array:
	return _steps(net).filter(func(s: String) -> bool: return s.begins_with("POST /plays") or s.ends_with("/like") or s.ends_with("/difficulty"))


## Files in the downloads folder that hold a player's private feedback (a payload with a `you` block), wherever the client keeps them.
func _private_files() -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(Community.dir):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(Community.dir + file)) == OK and json.data is Dictionary and json.data.has("you"):
			out.append(file)
	return out


## A signed-out client whose sign-in is held at Play Games and whose server answers every vote, remembering the last one. Returns that server state: `difficulty` and `liked`.
func _held_sign_in(net: FakeTransport) -> Dictionary:
	var server := {"difficulty": "", "liked": null}
	net.answer("GET", "/nonce", 200, {"nonce": "n_held"})
	net.answer("POST", "/session", 200, {"token": "tok1", "player": {"id": "p_1", "name": "Pilot"}})
	net.respond("PUT", DIFFICULTY_PATH, func(r: Dictionary) -> Dictionary:
		var body: Dictionary = JSON.parse_string(r.body.get_string_from_utf8())
		server["difficulty"] = body.difficulty
		return {"status": 200, "body": {"difficulty": body.difficulty}})
	net.respond("POST", LIKE_PATH, func(_r: Dictionary) -> Dictionary:
		server["liked"] = true
		return {"status": 200, "body": {"likes": 1}})
	net.respond("DELETE", LIKE_PATH, func(_r: Dictionary) -> Dictionary:
		server["liked"] = false
		return {"status": 200, "body": {"likes": 0}})
	pilot.sign_in_held = true
	return server


func _wipe_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_wipe_dir(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))


## Signs in as `player` with `token` and forgets the requests that took.
func _sign_in(net: FakeTransport, player := "p_1", token := "tok1") -> void:
	pilot.account = player
	net.answer("GET", "/nonce", 200, {"nonce": "n_in"})
	net.answer("POST", "/session", 200, {"token": token, "player": {"id": player, "name": "Pilot"}})
	var error: String = await Community.sign_in()
	check(error == "" and _c.player_id() == player, "setup: sign-in as %s failed: '%s' (player '%s')" % [player, error, _c.player_id()])
	net.requests.clear()
	pilot.nonces.clear()


func _level_bytes() -> PackedByteArray:
	return LevelFormat.to_json(LevelDoc.blank()).to_utf8_buffer()


func _row() -> Dictionary:
	return {"level_id": LEVEL_ID, "title": "Loop", "author": "Pilot", "latest": 2, "sha256": CommunityWire.sha256_hex(_level_bytes()), "likes": 0, "players": 0}


## A downloaded level whose file is already in the cache; no request made.
func _place_level() -> Dictionary:
	var row := _row()
	DirAccess.make_dir_recursive_absolute(Community.dir)
	var file := FileAccess.open(Community.level_path(row.sha256), FileAccess.WRITE)
	file.store_buffer(_level_bytes())
	file.close()
	return row


## A downloaded level, fetched through the fake CDN while signed in; so its public meta exists too.
func _cached(net: FakeTransport) -> Dictionary:
	var row := _row()
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, _level_bytes())
	var error: String = await Community.download(row)
	check(error == "", "setup: the level must download: %s" % error)
	net.requests.clear()
	return row


func _meta_path(sha: String) -> String:
	return Community.dir + sha + ".meta.json"


func _meta(sha: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_meta_path(sha)))
	return parsed if parsed is Dictionary else {}


## A history read from the file, as a restart would see it.
func _disk(path := HISTORY) -> Variant:
	var h := CommunityHistory.new()
	h.path = path
	h.load_file()
	return h


## A fresh empty history for the tests that need no `Community`; null (and a failed check) without `local_progress`.
func _history() -> Variant:
	_wipe()
	var h := CommunityHistory.new()
	h.path = HISTORY
	if not h.has_method("local_progress"):
		check(false, "CommunityHistory.local_progress(owner, level, sha) is missing")
		return null
	check(h.load_file() == OK, "load")
	return h


func _attempt_count() -> int:
	if not FileAccess.file_exists(HISTORY):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HISTORY))
	var total := 0
	if data is Dictionary:
		for owner in data.get("owners", {}):
			total += data.owners[owner].get("attempts", {}).size()
	return total


func _header(request: Dictionary, name: String) -> String:
	for header: String in request.get("headers", PackedStringArray()):
		if header.begins_with(name + ": "):
			return header.trim_prefix(name + ": ")
	return ""


## Whether `request` names `nonce` and carries the integrity token bound to that nonce and its own body bytes.
func _bound(request: Dictionary, nonce: String) -> bool:
	var body: PackedByteArray = request.body
	var parts: Array[PackedByteArray] = [body]
	return _header(request, "X-Nonce") == nonce and _header(request, "X-Integrity") == "ok:" + CommunityWire.bound_nonce(nonce, parts)


func _plays(net: FakeTransport) -> Array:
	return net.requests.filter(func(r: Dictionary) -> bool: return r.method == "POST" and r.url.get_slice("?", 0).ends_with("/plays"))


func _report(request: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(request.body.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _attempts(request: Dictionary) -> Array:
	var attempts: Variant = _report(request).get("attempts")
	return attempts if attempts is Array else []


func _ack(entries: Array) -> Dictionary:
	return {"acknowledged": entries.map(func(e: Array) -> Dictionary: return {"id": e[0], "revision": e[1]}), "discarded": [], "cleared": []}


func _steps(net: FakeTransport) -> Array:
	return net.requests.map(func(r: Dictionary) -> String: return "%s /%s" % [r.method, r.url.split("/", true, 3)[3].get_slice("?", 0)])


func _urls(net: FakeTransport) -> Array:
	return _steps(net)


func _vote(votes: Array, kind: String, sha: String) -> Dictionary:
	for vote: Dictionary in votes:
		if vote.get("kind") == kind and vote.get("sha", "") == sha:
			return vote
	return {}


## Task 2's feedback payload with a `you` block that `overrides` change.
func _dto(sha: String, overrides := {}) -> Dictionary:
	var you := {"liked": false, "like_eligible": true, "difficulty": null, "difficulty_eligible": true, "attempts": 2, "cleared": false}
	you.merge(overrides, true)
	return {
		"level_id": LEVEL_ID, "sha256": sha, "reviewed_difficulty": "hard", "community_difficulty": {"value": "normal", "votes": 6},
		"stats": {"players_started": 12, "players_cleared": 3, "total_attempts": 54, "clear_rate": 0.25, "attempts_per_first_clear": 18, "median_tries": 3, "unbeaten_5": 3, "unbeaten_10": 2, "unbeaten_20": 1},
		"you": you,
	}


## An optional fresh-eligibility read before a vote is applied: queued so a client that makes it is answered, harmless when it does not.
func _eligible(net: FakeTransport, sha: String, overrides := {}) -> void:
	net.answer("GET", FEEDBACK_PATH, 200, _dto(sha, overrides))


func _auto_nonces(net: FakeTransport) -> void:
	net.respond("GET", "/nonce", func(_r: Dictionary) -> Dictionary: return {"status": 200, "body": {"nonce": "n_auto_%d" % net.count("GET", "/nonce")}})


## Acknowledges exactly the snapshots each upload carried.
func _auto_acks(net: FakeTransport) -> void:
	net.respond("POST", "/plays", func(r: Dictionary) -> Dictionary: return {"status": 200, "body": _ack(_attempts(r).map(func(a: Dictionary) -> Array: return [a.id, int(a.revision)]))})


## An activated community, one finished play flushed in the background and a second start recorded right after, so the
## cadence must hold it back. Returns the second attempt's id.
func _held_back(net: FakeTransport, row: Dictionary) -> String:
	_auto_nonces(net)
	_auto_acks(net)
	_c.activate_feedback()
	var first: String = _c.record_play_start(row.sha256)
	_c.record_play_finish(first, "failed")
	var sent: bool = await _until(func() -> bool: return net.count("POST", "/plays") >= 1, 300)
	check(sent, "setup: an activated community flushes a finished play by itself")
	return _c.record_play_start(row.sha256)


func _check_retained(status: int) -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	_eligible(net, row.sha256)
	net.answer("PUT", DIFFICULTY_PATH, status, {"error": "Try again later."} if status > 0 else "")
	var result: Dictionary = await _c.set_difficulty(LEVEL_ID, row.sha256, "hard")
	await frames(5)
	var tag := "status %d: " % status
	var votes: Array = _disk().pending_votes("p_1")
	check(result.get("pending") == true, tag + "the vote reads as Pending sync: %s" % [result])
	check(votes.size() == 1 and votes[0].value == "hard", tag + "the vote stays queued: %s" % [votes])
	check(net.count("PUT", DIFFICULTY_PATH) == 1, tag + "no immediate retry loop")
	check(_c.pending_feedback(LEVEL_ID, row.sha256).get(PENDING_DIFFICULTY) == "hard", tag + "the queued choice is still shown")
	_done()


func _check_refused(status: int) -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _cached(net)
	var tag := "status %d: " % status
	net.answer("GET", FEEDBACK_PATH, 200, _dto(row.sha256, {"difficulty": "normal"}))
	var seen: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(seen.get("you", {}).get("difficulty") == "normal", tag + "setup: the confirmed vote is 'normal': %s" % [seen])
	net.queue.clear()
	_eligible(net, row.sha256, {"difficulty": "normal"})
	net.answer("PUT", DIFFICULTY_PATH, status, {"error": "Play this level first."})
	var result: Dictionary = await _c.set_difficulty(LEVEL_ID, row.sha256, "hard")
	check(result.get("error") == "Play this level first." and result.get("pending") == false, tag + "the server's sentence comes back and nothing is pending: %s" % [result])
	check(_disk().pending_votes("p_1").is_empty() and not _c.pending_feedback(LEVEL_ID, row.sha256).has(PENDING_DIFFICULTY), tag + "the refused change is removed")
	await _cooldown()
	await _c.sync_feedback()
	await frames(5)
	check(net.count("PUT", DIFFICULTY_PATH) == 1, tag + "a refusal is not retried")
	net.queue.clear()
	net.answer("GET", FEEDBACK_PATH, 0)
	var offline: Dictionary = await _c.feedback(LEVEL_ID, row.sha256)
	check(offline.get("offline") == true and offline.get("you", {}).get("difficulty") == "normal", tag + "the confirmed vote is what shows again: %s" % [offline])
	_done()


## Coroutine: lets the 30 s routine cooldown (a SceneTreeTimer) expire by speeding the engine clock up for a few
## process frames, then puts the clock back. Call it only where a test needs the next flush.
func _cooldown() -> void:
	var was := Engine.time_scale
	Engine.time_scale = FAST
	for _frame in COOLDOWN_FRAMES:
		await tree.process_frame
	Engine.time_scale = was


## Coroutine: true as soon as `done` is, false when `limit` process frames pass first.
func _until(done: Callable, limit: int) -> bool:
	for _frame in limit:
		if done.call():
			return true
		await tree.process_frame
	return done.call()


func _draft_with_demo() -> String:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var run := Demo.new()
	run.add_frame({"position": Vector2(100, 100), "rotation": 0.0, "firing": false, "fuel": 10.0, "hull": 10.0}, {})
	run.level_sha256 = LevelFormat.sha256(MyLevels.load_level(id))
	MyLevels.save_demo(id, run)
	return id
