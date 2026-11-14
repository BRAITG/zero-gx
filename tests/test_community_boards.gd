extends "res://tests/test_case.gd"
## The real board client and isolated disk cache, using the runner's redirected storage.

const SHA := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const ROUTE := "/boards/" + SHA


func _fake(owner := "p_1") -> FakeTransport:
	var net := FakeTransport.new()
	world.add_child(net)
	Community.transport = net
	Community.platform = FakePlatform.new()
	Community.history_path = "user://test_board_history.json"
	DirAccess.remove_absolute(Community.history_path)
	DirAccess.remove_absolute(Community.history_path.get_basename() + "_scores.json")
	_owner(owner)
	return net


func _owner(owner: String) -> void:
	var file := ConfigFile.new()
	if owner != "":
		file.set_value("player", "id", owner)
		file.set_value("session", "token", "token_" + owner)
		file.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
	check(file.save(Community.session_path) == OK, "isolated session saves")


func _row(owner := "p_1", points := 700) -> Dictionary:
	return {"rank": 2, "player": {"id": owner, "name": "Pilot"}, "points": points, "seconds": 12.5, "fuel": 10, "hull": 20, "demo": null}


func _payload(owner := "p_1") -> Dictionary:
	return {"level": {"kind": "official", "name": "Loop"}, "rows": [_row()], "you": _row(owner), "count": 30, "quantiles": range(0, 2100, 100)}


func test_board_fetch_caches_public_hash_and_private_owner_across_reload() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var events := []
	var received := func(sha: String) -> void: events.append(sha)
	Community.board_updated.connect(received)
	var reply: Dictionary = await Community.board(SHA)
	Community.board_updated.disconnect(received)
	check(reply.get("sha256") == SHA and reply.get("owner") == "p_1" and reply.you.player.id == "p_1", "hash and owner survive the answer")
	check(net.requests[0].url.ends_with(ROUTE + "?limit=20") and events == [SHA], "one top-20 read emits an update")
	var public: Variant = JSON.parse_string(FileAccess.get_file_as_string(Community.dir + "board_" + SHA + ".json"))
	check(public is Dictionary and not public.has("you") and not public.has("owner"), "public cache contains no private standing")
	Community.use_defaults()
	Community.platform = FakePlatform.new()
	var cached: Dictionary = Community.cached_board(SHA)
	check(cached.get("sha256") == SHA and cached.get("you", {}).get("points") == 700 and cached.get("cached") == true, "persistent cache reloads for its owner")
	cached.rows.clear()
	check(Community.cached_board(SHA).rows.size() == 1, "callers cannot mutate the stored public board")


func test_within_hour_reads_reuse_cache_force_and_expired_reads_refresh() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA)
	await Community.board(SHA)
	check(net.count("GET", ROUTE) == 1, "a fresh board is reused")
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA, true)
	check(net.count("GET", ROUTE) == 2, "force bypasses the hour")
	var path := Community.dir + "board_" + SHA + ".json"
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	stored.fetched_at -= 3601
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(stored))
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA)
	check(net.count("GET", ROUTE) == 3, "expired boards refresh")


func test_failed_refresh_marks_cached_rows_and_exact_standing_offline() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA)
	for status in [0, 500]:
		net.answer("GET", ROUTE, status, {"error": "Unavailable"})
		var reply: Dictionary = await Community.board(SHA, true)
		check(reply.get("cached") == true and reply.get("offline") == true and reply.rows.size() == 1, "all failed refreshes mark stale data, including server errors")
		check(Community.cached_board(SHA).get("offline") == true, "cache-only consumers see the failed refresh marker")


func test_account_switch_never_adopts_previous_private_row_and_fetches_own() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA)
	_owner("p_2")
	check(Community.cached_board(SHA).get("you") == null, "public cache does not confer the old owner's row")
	net.answer("GET", ROUTE, 200, _payload("p_2"))
	var other: Dictionary = await Community.board(SHA)
	check(net.count("GET", ROUTE) == 2 and other.you.player.id == "p_2", "new owner gets a read even within the public cache hour")
	_owner("")
	check(Community.cached_board(SHA).get("you") == null, "anonymous cache has no private row")


func test_desktop_and_nonplay_make_no_request_even_with_a_token() -> void:
	var net := _fake()
	Community.platform = CommunityPlatform.new()
	var reply: Dictionary = await Community.board(SHA)
	check(reply.has("error") and net.requests.is_empty(), "desktop token cannot bypass the platform gate")
	var pilot := FakePlatform.new()
	pilot.is_available = false
	Community.platform = pilot
	await Community.board(SHA, true)
	check(net.requests.is_empty(), "non-Play also makes no requests")
	await Community.board("not a hash")
	check(net.requests.is_empty(), "invalid hashes never reach HTTP")


func test_identical_concurrent_reads_coalesce() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	net.hold("GET", ROUTE)
	var results := []
	var read := func() -> void: results.append(await Community.board(SHA, true))
	read.call()
	read.call()
	check(net.count("GET", ROUTE) == 1 and results.is_empty(), "overlapping reads share the held request")
	net.release_hold("GET", ROUTE)
	check(results.size() == 2 and results[0].rows == results[1].rows, "both callers receive the board")


func test_owner_and_generation_are_part_of_read_coalescing() -> void:
	var net := _fake()
	net.hold("GET", ROUTE)
	var results := []
	var read := func() -> void: results.append(await Community.board(SHA, true))
	read.call()
	_owner("p_2")
	net.answer("GET", ROUTE, 200, _payload("p_2"))
	read.call()
	check(net.count("GET", ROUTE) == 2 and results.size() == 1 and results[0].you.player.id == "p_2", "another owner does not join the previous read")
	net.answer("GET", ROUTE, 200, _payload())
	net.release_hold("GET", ROUTE)
	check(Community.cached_board(SHA).you.player.id == "p_2", "late previous owner cannot replace current private standing")
	net.hold("GET", ROUTE)
	read.call()
	Community.use_defaults()
	Community.transport = net
	Community.platform = FakePlatform.new()
	net.answer("GET", ROUTE, 200, _payload("p_2"))
	read.call()
	check(net.count("GET", ROUTE) == 4, "a reset generation does not join the old read")
	net.answer("GET", ROUTE, 200, _payload())
	net.release_hold("GET", ROUTE)
	check(Community.cached_board(SHA).you.player.id == "p_2", "late reset answer cannot overwrite the cache")


func test_malformed_percentile_payloads_are_ignored_without_losing_rows() -> void:
	var net := _fake()
	for bad: Variant in [null, "percentiles", [], [0, 1], range(21).map(func(i: int) -> int: return 20 - i), range(20) + ["20"], range(20) + [-1], range(20) + [20.5], range(20) + [null]]:
		var payload := _payload()
		payload.quantiles = bad
		net.answer("GET", ROUTE, 200, payload)
		var reply: Dictionary = await Community.board(SHA, true)
		check(reply.get("quantiles") == [] and reply.rows.size() == 1 and not reply.has("error"), "bad distribution ignored: %s" % [bad])
	for bad: Variant in [-1, "30", null, 30.5]:
		var payload := _payload()
		payload.count = bad
		net.answer("GET", ROUTE, 200, payload)
		var reply: Dictionary = await Community.board(SHA, true)
		check(reply.get("count") == -1 and reply.get("quantiles") == [], "bad population cannot produce estimates")


func test_mismatched_private_identity_and_malformed_rows_are_not_cached() -> void:
	var net := _fake()
	var payload := _payload("p_2")
	payload.rows.append({"rank": "first"})
	net.answer("GET", ROUTE, 200, payload)
	var reply: Dictionary = await Community.board(SHA)
	check(reply.get("you") == null and reply.rows.size() == 1, "row identity is checked inside you; malformed public rows are discarded")


func test_deleted_owner_private_board_is_erased_but_public_board_stays() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA)
	net.answer("DELETE", "/me", 204)
	check(await Community.delete_account() == "", "account deletion succeeds")
	_owner("p_1")
	check(Community.cached_board(SHA).get("you") == null and Community.cached_board(SHA).rows.size() == 1, "erasure removes private standing, not public rows")


func _upload_board(posted := false, owner := "p_1") -> Dictionary:
	var payload := _payload(owner)
	payload.rows = []
	var points: Array = [1200, 1150, 1100, 1050, 1000, 950] + ([900] if posted else []) + range(890, 710, -10) + ([] if posted else [700]) + range(690, 640, -10)
	for i in points.size():
		var row := _row(owner if points[i] == (900 if posted else 700) else "other_%d" % i, points[i])
		row.rank = i + 1
		if row.player.id == owner:
			payload.you = row
		if i < 20:
			payload.rows.append(row)
	payload.quantiles = []
	return payload


func _queue_board_score(net: FakeTransport, sha := SHA) -> void:
	var run := Demo.new()
	run.level_sha256 = sha
	run.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 50.0, "hull": 40.0}, {})
	run.add_event(Demo.Event.GOAL_REACHED)
	Progress.record_win("stage1", 900, 0.0)
	Progress.save_best_demo("stage1", run)
	net.answer("GET", "/nonce", 200, {"nonce": "board_upload"})
	check(Community.queue_score("stage1", run) == "", "score queues without any result or board UI")


func test_final_fix_background_post_expires_public_and_private_cache_before_board_opens() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _upload_board())
	await Community.board(SHA)
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
	_queue_board_score(net)
	await frames(4)
	check(net.count("POST", "/scores") == 1 and net.count("GET", ROUTE) == 1, "background success does not add a UI refresh loop")
	var cached := Community.cached_board(SHA)
	check(cached.you.points == 700 and cached.you.rank == 25 and cached.fetched_at == 0, "old data remains available for explicitly cached display but is stale")
	var public: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Community.dir + "board_" + SHA + ".json"))
	var private: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Community._board_you_path("p_1", SHA)))
	check(public.fetched_at == 0 and private.fetched_at == 0, "both cache components expire durably")
	check(Progress.best_points("stage1") == 900 and Progress.best_demo("stage1") != null, "posting never deletes the local best")
	Community.use_defaults()
	Community.transport = net
	Community.platform = FakePlatform.new()
	net.answer("GET", ROUTE, 200, _upload_board(true))
	var sheet := Leaderboard.open(world, SHA, "Loop", 900)
	check(net.count("GET", ROUTE) == 2 and Community.cached_board(SHA).you.rank == 7 and Community.cached_board(SHA).you.points == 900, "opening after a restart fetches the posted board instead of reusing the hour-old standing")
	sheet.close()


func test_final_fix_preupload_get_cannot_restore_freshness_after_background_post() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _upload_board())
	await Community.board(SHA)
	net.hold("GET", ROUTE)
	var results := []
	var read := func() -> void: results.append(await Community.board(SHA, true))
	read.call()
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
	_queue_board_score(net)
	await frames(4)
	net.answer("GET", ROUTE, 200, _upload_board())
	net.release_hold("GET", ROUTE)
	check(results.size() == 1 and Community.cached_board(SHA).fetched_at == 0, "a held pre-upload answer cannot make stale rows fresh")
	net.answer("GET", ROUTE, 200, _upload_board(true))
	var sheet := Leaderboard.open(world, SHA, "Loop", 900)
	check(net.count("GET", ROUTE) == 3 and Community.cached_board(SHA).you.rank == 7, "opening still fetches after the stale in-flight answer completes")
	sheet.close()


func test_final_fix_postupload_get_does_not_join_or_get_overwritten_by_older_get() -> void:
	var net := _fake()
	net.hold("GET", ROUTE)
	var results := []
	var read := func() -> void: results.append(await Community.board(SHA, true))
	read.call()
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
	_queue_board_score(net)
	await frames(4)
	net.answer("GET", ROUTE, 200, _upload_board(true))
	var fresh := []
	var read_fresh := func() -> void: fresh.append(await Community.board(SHA))
	read_fresh.call()
	check(net.count("GET", ROUTE) == 2 and fresh.size() == 1 and fresh[0].get("you", {}).get("rank") == 7, "post-upload reads cannot coalesce with requests from before the upload")
	net.answer("GET", ROUTE, 200, _upload_board())
	net.release_hold("GET", ROUTE)
	var cached := Community.cached_board(SHA)
	check(results.size() == 1 and cached.you.rank == 7 and cached.you.points == 900 and cached.fetched_at > 0, "late old answer cannot overwrite the newer fresh cache")


func test_final_fix_score_invalidation_matches_captured_owner_and_hash() -> void:
	for changed in ["owner", "hash"]:
		Community.use_defaults()
		var net := _fake()
		net.answer("GET", ROUTE, 200, _upload_board())
		await Community.board(SHA, true)
		net.hold("POST", "/scores")
		_queue_board_score(net, "b".repeat(64) if changed == "hash" else SHA)
		await frames(4)
		if changed == "owner":
			_owner("p_2")
			net.answer("GET", ROUTE, 200, _upload_board(false, "p_2"))
			await Community.board(SHA)
		net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
		net.release_hold("POST", "/scores")
		await Community.board(SHA)
		check(net.count("GET", ROUTE) == (2 if changed == "owner" else 1), "%s: another owner's or hash's success cannot invalidate the current board" % changed)


func test_residual_fix_older_success_expires_board_without_adopting_rank_for_newer_revision() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _upload_board())
	await Community.board(SHA)
	net.hold("POST", "/scores")
	_queue_board_score(net)
	await frames(4)
	_queue_board_score(net)
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
	net.release_hold("POST", "/scores")
	var pending := Community.score_state(SHA)
	check(pending.get("revision") == 2 and pending.get("state") == "queued" and not pending.has("rank"), "older uploaded rank cannot verify the newer queued recording")
	check(Community.cached_board(SHA).fetched_at == 0, "older upload still changed the server and must expire the cached 700-point standing")
	net.answer("GET", ROUTE, 200, _upload_board(true))
	var fresh: Dictionary = await Community.board(SHA)
	check(net.count("GET", ROUTE) == 2 and fresh.you.points == 900 and fresh.you.rank == 7, "next opening fetches the actual stored best while the newer run remains queued")


func test_residual_fix_obsolete_failure_or_malformed_get_cannot_poison_new_success() -> void:
	for status in [503, 200]:
		Community.use_defaults()
		var net := _fake()
		net.answer("GET", ROUTE, 200, _upload_board())
		await Community.board(SHA, true)
		net.hold("GET", ROUTE)
		var results := []
		var read := func() -> void: results.append(await Community.board(SHA, true))
		read.call()
		net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
		_queue_board_score(net)
		await frames(4)
		net.answer("GET", ROUTE, 200, _upload_board(true))
		var fresh: Dictionary = await Community.board(SHA)
		var events := []
		var updated := func(sha: String) -> void: events.append(sha)
		Community.board_updated.connect(updated)
		net.answer("GET", ROUTE, status, {"error": "Unavailable"} if status == 503 else {"rows": "malformed", "level": {}})
		net.release_hold("GET", ROUTE)
		Community.board_updated.disconnect(updated)
		var cached := Community.cached_board(SHA)
		check(results.size() == 1 and results[0].get("you", {}).get("rank") == 7 and not results[0].get("offline", true) and not results[0].has("error"), "%d: obsolete read returns the current successful cache" % status)
		check(cached.you.rank == 7 and cached.you.points == 900 and cached.fetched_at == fresh.fetched_at and not cached.offline and not cached.has("error"), "%d: old failure cannot change freshness or poison the newer board" % status)
		check(events.is_empty(), "%d: ignored old answer emits no stale error update" % status)
		await Community.board(SHA)
		check(net.count("GET", ROUTE) == 3, "%d: newer successful board remains reusable without another GET" % status)
