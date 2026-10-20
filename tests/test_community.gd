extends "res://tests/test_case.gd"
## The community client against a fake server and a fake Play Games device (tests/support/fake_*.gd).

const LEVEL_ID := "lvl_abcdefghij"
const SESSION := {"token": "tok1", "player": {"id": "p_1", "name": "Pilot"}}
const UNAUTHORIZED := {"error": "Sign in again."}

var pilot := FakePlatform.new()


func _fake() -> FakeTransport:
	var net := FakeTransport.new()
	world.add_child(net)  # freed with the world
	Community.transport = net
	Community.platform = pilot
	return net


## Signs in with nonce n1 and forgets the requests that took.
func _signed_in(net: FakeTransport) -> void:
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	var error: String = await Community.sign_in()
	check(error == "", "sign-in failed: %s" % error)
	net.requests.clear()


func _header(request: Dictionary, name: String) -> String:
	for header: String in request.headers:
		if header.begins_with(name + ": "):
			return header.trim_prefix(name + ": ")
	return ""


func _draft_with_demo() -> String:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var run := Demo.new()
	run.add_frame({"position": Vector2(100, 100), "rotation": 0.0, "firing": false, "fuel": 10.0, "hull": 10.0}, {})
	run.level_sha256 = LevelFormat.sha256(MyLevels.load_level(id))
	MyLevels.save_demo(id, run)
	return id


func _row(bytes: PackedByteArray) -> Dictionary:
	return {"level_id": LEVEL_ID, "title": "Loop", "author": "Pilot", "latest": 2, "sha256": CommunityWire.sha256_hex(bytes), "likes": 0, "players": 0}


func test_the_desktop_platform_is_unavailable_and_makes_no_calls() -> void:
	var net := FakeTransport.new()
	world.add_child(net)
	Community.transport = net
	check(not Community.available(), "the default platform must be unavailable")
	var listed: Dictionary = await Community.list("top", 0)
	check(listed.has("error") and listed.rows.is_empty(), "a list without Play Games must fail with no rows: %s" % [listed])
	check(await Community.statuses() == {} and net.requests.is_empty(), "nothing may reach the network: %s" % [net.requests])


func test_sign_in_asks_for_a_nonce_then_posts_the_session_and_stores_the_token() -> void:
	var net := _fake()
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	check(not Community.signed_in(), "nobody is signed in yet")
	var error: String = await Community.sign_in()
	check(error == "", "sign-in failed: %s" % error)
	check(net.requests.size() == 2 and net.requests[0].method == "GET" and net.requests[0].url.ends_with("/nonce"), "first request must be GET /nonce: %s" % [net.requests])
	var post: Dictionary = net.requests[1]
	check(post.method == "POST" and post.url.ends_with("/session") and _header(post, "Content-Type") == "application/json", "second request must be a JSON POST /session")
	check(JSON.parse_string(post.body.get_string_from_utf8()) == {"authCode": "test:p1:Pilot", "integrityToken": "ok:n1", "nonce": "n1"}, "session body: %s" % post.body.get_string_from_utf8())
	check(Community.signed_in(), "the token must be stored")
	var reloaded = load("res://scripts/community.gd").new()
	reloaded.session_path = Community.session_path
	check(reloaded.signed_in(), "the stored session must survive a reload")
	reloaded.free()


func test_an_expired_session_is_not_signed_in() -> void:
	_fake()
	var file := ConfigFile.new()
	file.set_value("session", "token", "old")
	file.set_value("session", "expires", int(Time.get_unix_time_from_system()) - 1)
	file.save(Community.session_path)
	check(not Community.signed_in(), "an expired token must not count")


func test_a_failed_play_games_or_integrity_step_stops_sign_in_with_its_sentence() -> void:
	var net := _fake()
	pilot.sign_in_error = "Play Games sign-in was cancelled"
	check(await Community.sign_in() == "Play Games sign-in was cancelled", "the sign-in sentence must come back")
	check(net.requests.is_empty(), "a cancelled sign-in must not touch the server")
	pilot.sign_in_error = ""
	pilot.integrity_error = "Play Integrity is unavailable"
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	check(await Community.sign_in() == "Play Integrity is unavailable", "the integrity sentence must come back")
	check(net.count("POST", "/session") == 0 and not Community.signed_in(), "no session may be posted without a token")


func test_a_server_refusal_of_the_session_comes_back_as_its_sentence() -> void:
	var net := _fake()
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 403, {"error": "This player is banned."})
	check(await Community.sign_in() == "This player is banned." and not Community.signed_in(), "the server's sentence must come back")


func test_a_401_signs_in_once_more_and_retries_once() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 401, UNAUTHORIZED)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/session", 200, {"token": "tok2", "player": SESSION.player})
	net.answer("GET", "/levels", 200, [{"level_id": LEVEL_ID}])
	var listed: Dictionary = await Community.list("top", 0)
	check(not listed.has("error") and listed.rows.size() == 1, "the retry must succeed: %s" % [listed])
	var steps := net.requests.map(func(r: Dictionary) -> String: return "%s %s" % [r.method, r.url.get_slice("?", 0).get_slice("/", 3)])
	check(steps == ["GET levels", "GET nonce", "POST session", "GET levels"], "requests: %s" % [steps])
	check(_header(net.requests[0], "Authorization") == "Bearer tok1" and _header(net.requests[3], "Authorization") == "Bearer tok2", "the retry must carry the new token")
	check(net.requests[2].body.get_string_from_utf8().contains("ok:n2"), "the second sign-in must use a fresh nonce")


func test_a_second_401_gives_up_without_a_third_request() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 401, UNAUTHORIZED)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/session", 200, {"token": "tok2", "player": SESSION.player})
	net.answer("GET", "/levels", 401, UNAUTHORIZED)
	var listed: Dictionary = await Community.list("top", 0)
	check(listed.get("error") == "Sign in again." and listed.rows.is_empty(), "the second 401 must end the call: %s" % [listed])
	check(net.requests.size() == 4 and net.count("GET", "/levels") == 2, "exactly one retry: %d requests" % net.requests.size())


func test_an_unexpected_answer_is_an_error_not_a_crash() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, {"not": "a list"})
	var listed: Dictionary = await Community.list("top", 0)
	check(listed.has("error") and listed.rows.is_empty(), "a non-list answer must fail the call: %s" % [listed])


func test_offline_list_shows_the_cached_page() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [{"level_id": LEVEL_ID, "title": "Loop"}])
	var online: Dictionary = await Community.list("top", 0)
	check(not online.has("error") and online.rows.size() == 1, "online list: %s" % [online])
	check(net.requests[0].url.ends_with("/levels?sort=top&page=0"), "list url: %s" % net.requests[0].url)
	net.answer("GET", "/levels", 0)
	var offline: Dictionary = await Community.list("top", 0)
	check(offline.get("error") == "No connection" and offline.get("offline") == true and offline.rows.size() == 1 and offline.rows[0].title == "Loop", "cached rows offline: %s" % [offline])
	net.answer("GET", "/levels", 0)
	var uncached: Dictionary = await Community.list("new", 0)
	check(uncached.get("error") == "No connection" and uncached.get("offline") == true and uncached.rows.is_empty(), "no cache offline: %s" % [uncached])


func test_a_server_error_keeps_the_cached_page_and_is_not_offline() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [{"level_id": LEVEL_ID}])
	await Community.list("new", 2)
	net.answer("GET", "/levels", 500, {"error": "Internal error."})
	var failed: Dictionary = await Community.list("new", 2)
	check(failed.get("error") == "Internal error." and failed.get("offline") == false and failed.rows.size() == 1, "server error: %s" % [failed])


func test_download_builds_the_url_from_the_index_commit_and_caches_a_verified_file() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := LevelFormat.to_json(LevelDoc.blank()).to_utf8_buffer()
	var row := _row(bytes)
	check(row.sha256 == LevelFormat.sha256(LevelDoc.blank()), "the row's hash is the level's content hash")
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	check(await Community.download(row) == "", "a matching file must be accepted")
	check(net.requests[1].url == "https://cdn.jsdelivr.net/gh/BRAITG/zero-gx-levels@abc123/levels/%s/v2.json" % LEVEL_ID, "download url: %s" % net.requests[1].url)
	check(_header(net.requests[1], "Authorization") == "", "the session token must never go to the CDN")
	check(FileAccess.get_file_as_bytes(Community.level_path(row.sha256)) == bytes, "the file must be cached under its hash")
	net.requests.clear()
	check(await Community.download(row) == "" and net.requests.is_empty(), "a cached file needs no request: %s" % [net.requests])


func test_download_rejects_a_file_that_does_not_match_the_list() -> void:
	var net := _fake()
	await _signed_in(net)
	var row := _row(LevelFormat.to_json(LevelDoc.blank()).to_utf8_buffer())
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, "{\"tampered\": true}")
	var error: String = await Community.download(row)
	check(error == "The downloaded file did not match the level list.", "rejection sentence: %s" % error)
	check(not FileAccess.file_exists(Community.level_path(row.sha256)), "a rejected file must not be cached")


func test_download_fetches_again_when_the_cached_file_is_damaged() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := LevelFormat.to_json(LevelDoc.blank()).to_utf8_buffer()
	var row := _row(bytes)
	DirAccess.make_dir_recursive_absolute(Community.dir)
	FileAccess.open(Community.level_path(row.sha256), FileAccess.WRITE).store_string("{\"trunc")
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	check(await Community.download(row) == "" and net.count("GET", "/gh/") == 1, "a damaged cache file must be downloaded again")
	check(FileAccess.get_file_as_bytes(Community.level_path(row.sha256)) == bytes, "the damaged file must be replaced")


func test_can_submit_needs_a_matching_demo_and_an_available_platform() -> void:
	_fake()
	var bare := MyLevels.new_id()
	MyLevels.save(bare, LevelDoc.blank())
	check(not Community.can_submit(bare), "a draft without a demo cannot be submitted")
	var id := _draft_with_demo()
	check(Community.can_submit(id), "a finished draft can be submitted")
	var edited := LevelDoc.blank()
	edited.title = "Edited"
	MyLevels.save(id, edited)
	check(not Community.can_submit(id), "an edited draft has lost its demo match")
	var finished := _draft_with_demo()
	pilot.is_available = false
	check(not Community.can_submit(finished), "no submitting where community is unavailable")


func test_submit_sends_the_draft_and_its_demo_bound_to_a_fresh_nonce_and_remembers_the_level_id() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _draft_with_demo()
	var level := LevelFormat.to_json(MyLevels.load_level(id)).to_utf8_buffer()
	var demo := FileAccess.get_file_as_bytes(MyLevels.demo_path(id))
	var files := {"level": ["level.json", level], "demo": ["demo.gz", demo]}
	check(Community.level_id_of(id) == "", "never submitted: no level id")
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	check(await Community.submit(id) == "", "the first submission must succeed")
	var post: Dictionary = net.requests[1]
	var boundary := _header(post, "Content-Type").get_slice("boundary=", 1)
	check(_header(post, "Content-Type") == "multipart/form-data; boundary=" + boundary and boundary != "", "multipart content type: %s" % _header(post, "Content-Type"))
	check(post.body == CommunityWire.multipart({}, files, boundary), "the body must carry exactly the draft bytes and the demo file")
	var parts: Array[PackedByteArray] = [level, demo]
	check(_header(post, "X-Nonce") == "n2" and _header(post, "X-Integrity") == "ok:" + CommunityWire.bound_nonce("n2", parts), "integrity must be bound to the nonce and both files")
	check(_header(post, "Authorization") == "Bearer tok1", "submissions need the session")
	check(Community.level_id_of(id) == LEVEL_ID, "the returned level id must be stored for the draft")
	net.answer("GET", "/nonce", 200, {"nonce": "n3"})
	net.answer("POST", "/submissions", 200, {"level_id": LEVEL_ID, "version": 2, "pull_request": 7})
	check(await Community.submit(id) == "", "the second submission must succeed")
	var again: Dictionary = net.requests[3]
	boundary = _header(again, "Content-Type").get_slice("boundary=", 1)
	check(again.body == CommunityWire.multipart({"level_id": LEVEL_ID}, files, boundary), "the stored level id must be sent with the next submission")
	check(_header(again, "X-Nonce") == "n3", "every submission needs its own nonce")


func test_a_rejected_submission_returns_the_servers_sentence_and_the_next_try_gets_a_new_nonce() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _draft_with_demo()
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 429, {"error": "At most 5 submissions are accepted per day."})
	check(await Community.submit(id) == "At most 5 submissions are accepted per day.", "the server's sentence must come back as it is")
	check(Community.level_id_of(id) == "", "a failed submission stores no level id")
	net.answer("GET", "/nonce", 200, {"nonce": "n3"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	check(await Community.submit(id) == "", "the retry must succeed")
	check(net.count("GET", "/nonce") == 2 and _header(net.requests[-1], "X-Nonce") == "n3", "each try needs a new nonce: %s" % [net.requests.map(func(r): return r.url)])


func test_submit_refuses_a_draft_that_cannot_be_submitted() -> void:
	var net := _fake()
	await _signed_in(net)
	var bare := MyLevels.new_id()
	MyLevels.save(bare, LevelDoc.blank())
	check(await Community.submit(bare) != "" and net.requests.is_empty(), "no demo, no request")


func test_statuses_map_my_submissions_and_fall_back_to_the_last_known_offline() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/me/submissions", 200, [
		{"level_id": "lvl_aaaaaaaaaa", "version": 2, "status": "open", "comment": null, "pull_request": 5, "title": "Loop"},
		{"level_id": "lvl_aaaaaaaaaa", "version": 1, "status": "approved", "comment": null, "pull_request": 3, "title": "Loop"},
		{"level_id": "lvl_bbbbbbbbbb", "version": 1, "status": "rejected", "comment": "Too easy.", "pull_request": 4, "title": "Dash"},
	])
	var expected := {
		"lvl_aaaaaaaaaa": {"status": "open", "version": 2, "comment": ""},
		"lvl_bbbbbbbbbb": {"status": "rejected", "version": 1, "comment": "Too easy."},
	}
	var fresh: Dictionary = await Community.statuses()
	check(fresh == expected, "newest row of each level: %s" % [fresh])
	net.answer("GET", "/me/submissions", 0)
	check(await Community.statuses() == expected, "offline must show the last known statuses")


func test_statuses_make_no_request_when_signed_out() -> void:
	var net := _fake()
	check(await Community.statuses() == {} and net.requests.is_empty(), "signed out: nothing known and no request")


func test_delete_account_clears_the_session_statuses_and_level_ids() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _draft_with_demo()
	MyLevels.set_level_id(id, LEVEL_ID)
	net.answer("GET", "/me/submissions", 200, [{"level_id": LEVEL_ID, "version": 1, "status": "open", "comment": null}])
	await Community.statuses()
	net.requests.clear()
	net.answer("DELETE", "/me", 204)
	check(await Community.delete_account() == "", "deleting the account must succeed")
	check(net.requests.size() == 1 and _header(net.requests[0], "Authorization") == "Bearer tok1", "one DELETE /me with the session: %s" % [net.requests])
	check(not Community.signed_in() and Community.level_id_of(id) == "", "session and level ids must be gone")
	check(await Community.statuses() == {}, "the last known statuses must be gone")


func test_a_failed_account_deletion_keeps_everything_and_returns_the_sentence() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _draft_with_demo()
	MyLevels.set_level_id(id, LEVEL_ID)
	net.answer("DELETE", "/me", 500, {"error": "Internal error."})
	check(await Community.delete_account() == "Internal error.", "the server's sentence must come back")
	check(Community.signed_in() and Community.level_id_of(id) == LEVEL_ID, "a failed deletion must keep the session and level ids")
