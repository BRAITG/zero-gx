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
