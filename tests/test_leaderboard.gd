extends "res://tests/test_case.gd"
## Exercise the real shared sheet/preview on the runner's isolated Settings/Progress/Community stores.

const SHEET := "res://scenes/leaderboard.gd"
const SHA := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const ROUTE := "/boards/" + SHA


func _fake() -> FakeTransport:
	var net := FakeTransport.new()
	world.add_child(net)
	Community.transport = net
	Community.platform = FakePlatform.new()
	Community.history_path = "user://test_leaderboard_history.json"
	DirAccess.remove_absolute(Community.history_path)
	var score_path := Community.history_path.get_basename() + "_scores.json"
	DirAccess.remove_absolute(score_path)
	if DirAccess.dir_exists_absolute(CommunityScores.replay_dir(score_path)):
		for file in DirAccess.get_files_at(CommunityScores.replay_dir(score_path)):
			DirAccess.remove_absolute(CommunityScores.replay_dir(score_path) + file)
	var file := ConfigFile.new()
	file.set_value("player", "id", "p_me")
	file.set_value("session", "token", "token")
	file.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
	check(file.save(Community.session_path) == OK, "isolated session saves")
	return net


func _payload(count := 30, own := true) -> Dictionary:
	var rows := []
	for i in mini(count, 25):
		rows.append({"rank": i + 1, "player": {"id": "p_%d" % i, "name": "Pilot %02d" % (i + 1)}, "points": 2000 - i * 50, "seconds": 12.5 + i})
	return {"level": {"kind": "official", "name": "Loop"}, "rows": rows, "you": {"rank": 25, "player": {"id": "p_me", "name": "My Pilot"}, "points": 700, "seconds": 30.25} if own else null, "count": count, "quantiles": range(0, 2100, 100) if count > 0 else []}


## Exactly 950 zeroes, 30 tied at 700, and 20 tied at 2000: the 700-point best is competition rank 21.
func _tied_payload() -> Dictionary:
	var payload := _payload()
	payload.count = 1000
	payload.quantiles = Array(range(20)).map(func(_i: int) -> int: return 0) + [2000]
	payload.you.rank = 21
	for i in payload.rows.size():
		payload.rows[i].rank = 1
		payload.rows[i].points = 2000
	payload.rows = payload.rows.slice(0, 20)
	return payload


func _score_run() -> Demo:
	var run := Demo.new()
	run.level_sha256 = SHA
	run.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 50.0, "hull": 50.0}, {})
	run.add_event(Demo.Event.GOAL_REACHED)
	return run


func _pending_score() -> int:
	var scores := CommunityScores.new()
	scores.path = Community.history_path.get_basename() + "_scores.json"
	check(scores.load_file() == OK, "isolated score outbox loads")
	check(scores.enqueue("p_me", "stage1", SHA, _score_run().encode()) == OK, "score is already durable before opening")
	return scores.revision("p_me", SHA)


func _texts(node: Node) -> String:
	var labels := node.find_children("*", "Label", true, false)
	return "\n".join(labels.map(func(label: Label) -> String: return label.text))


func _rows(node: Node) -> Array:
	return node.find_children("*", "HBoxContainer", true, false).filter(func(row: Node) -> bool: return row.has_meta("board_row"))


func _open(local_points := -1) -> Overlay:
	var script: GDScript = load(SHEET)
	return script.open(world, SHA, "Loop", local_points)


func test_sheet_is_opaque_top20_with_same_columns_and_separate_highlighted_own_row() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open(700)
	await frames(2)
	var rows := _rows(sheet)
	check(rows.size() == 21, "20 public rows plus one separate own row: %d" % rows.size())
	check(rows.all(func(row: Node) -> bool: return row.get_child_count() == 4), "rank/name/points/time use the same four columns")
	var text := _texts(sheet)
	check(text.contains("Pilot 20") and not text.contains("Pilot 21") and text.contains("12.50 s") and text.contains("2,000") == false, "top20 points and seconds are shown")
	check(text.contains("Rank #25 of 30") and text.contains("My Pilot") and not text.contains("Estimate:"), "same local best gets exact own standing")
	var own: PanelContainer = sheet.find_child("OwnStanding", true, false)
	check(own != null and own.get_theme_stylebox("panel").border_color == Style.ACCENT, "separate own standing is highlighted")
	var backdrop := sheet.get_child(0) as ColorRect
	check(backdrop != null and backdrop.color.a == 1.0, "the sheet fully hides the background")


func test_newer_local_best_is_estimated_and_older_exact_best_kept_separate() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open(900)
	var text := _texts(sheet)
	check(text.contains("Local best · 900 points") and text.contains("Estimate:") and text.contains("Your ranked best") and text.contains("Rank #25 of 30"), "new local run is estimated; older exact best stays separately labelled")
	var own: Node = sheet.find_child("OwnStanding", true, false)
	check(_rows(own).size() == 1 and _rows(own)[0].get_meta("board_row").points == 700, "unverified local best never enters any ranked row")


func test_remote_higher_best_is_not_attributed_to_the_lower_local_run() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open(500)
	var text := _texts(sheet)
	check(text.contains("Local best · 500 points") and text.contains("Your ranked best · Rank #25 of 30") and text.contains("700"), "higher remote best has its own label and score")


func test_loading_empty_error_and_offline_states_are_distinct() -> void:
	var net := _fake()
	net.hold("GET", ROUTE)
	net.answer("GET", ROUTE, 200, _payload(0, false))
	var sheet := _open()
	check(_texts(sheet).contains("Loading standings…"), "a held first request displays loading")
	net.release_hold("GET", ROUTE)
	check(_texts(sheet).contains("No ranked runs yet") and _texts(sheet).contains("Not played yet"), "empty board and unplayed own standing are explicit")
	sheet.close()
	await frames(2)
	net.answer("GET", ROUTE, 0)
	var failed := _open()
	var refresh: Button = failed.find_child("RefreshBoard", true, false)
	refresh.pressed.emit()
	check(_texts(failed).contains("Offline · cached standings"), "failed refresh labels the cached sheet")
	failed.close()
	await frames(2)
	DirAccess.remove_absolute(Community.dir + "board_" + SHA + ".json")
	net.answer("GET", ROUTE, 500, {"error": "Standings unavailable"})
	var error_sheet := _open()
	check(_texts(error_sheet).contains("Standings unavailable") and not _texts(error_sheet).contains("No ranked runs yet"), "uncached error is not an empty board")


func test_preview_reuses_top5_and_own_without_network_or_duplicate_widgets() -> void:
	var net := _fake()
	var slot := VBoxContainer.new()
	world.add_child(slot)
	var unrelated := Label.new()
	unrelated.text = "Existing details"
	slot.add_child(unrelated)
	var board := _payload()
	board["owner"] = "p_me"
	load(SHEET).preview(slot, board, 900)
	load(SHEET).preview(slot, board, 900)
	check(net.requests.is_empty(), "preview is pure presentation, no circular board read")
	check(slot.get_child_count() == 2 and is_instance_valid(unrelated), "preview replaces only its own widget")
	check(_rows(slot).size() == 6 and _texts(slot).contains("Pilot 05") and not _texts(slot).contains("Pilot 06"), "top5 plus separate own row only")
	check(_texts(slot).contains("Estimate:"), "preview uses the same own-standing estimate")


func test_back_closes_and_restores_keyboard_focus() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var prior := Button.new()
	prior.text = "Full board"
	world.add_child(prior)
	prior.grab_focus()
	var sheet := _open()
	await frames(2)
	check(sheet.get_viewport().gui_get_focus_owner().text == "Close", "focus starts at Close")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	sheet._unhandled_input(cancel)
	await frames(2)
	check(not is_instance_valid(sheet) and prior.has_focus(), "Back closes and restores its opener")


func test_closing_during_a_request_updates_cache_without_touching_freed_controls() -> void:
	var net := _fake()
	net.hold("GET", ROUTE)
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open(900)
	sheet.close()
	await frames(2)
	net.release_hold("GET", ROUTE)
	await frames(2)
	check(not is_instance_valid(sheet) and Community.cached_board(SHA).rows.size() == 20, "cache updates after close; logger catches any freed-node access")


func test_board_update_signal_renders_cache_without_reading_again() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open()
	Community.board_updated.emit(SHA)
	check(net.count("GET", ROUTE) == 1 and _rows(sheet).size() == 21, "updates redraw but never start circular reads")


func test_explicit_board_open_starts_score_only_sync_without_activating_feedback() -> void:
	var net := _fake()
	var history := CommunityHistory.new()
	history.path = Community.history_path
	check(history.load_file() == OK, "isolated history loads")
	check(history.begin("p_me", "lvl_abcdefghij", SHA, 10) != "", "pending play is saved")
	_pending_score()
	net.answer("GET", "/nonce", 200, {"nonce": "board-sync"})
	net.hold("POST", "/scores")
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open()
	check(_rows(sheet).size() == 21 and not Community._activated and net.count("POST", "/plays") == 0, "drawing does not wait for sync or activate play/vote uploads")
	check(net.count("POST", "/scores") == 1, "explicit board opening starts the pending score immediately")
	sheet.close()
	await frames(2)
	net.answer("POST", "/scores", 200, {"rank": 25, "points": 700, "best": true})
	net.release_hold("POST", "/scores")
	await frames(2)
	check(Community.score_state(SHA).get("state") == "posted" and net.count("GET", ROUTE) == 1, "closed sheet neither accesses controls nor rereads when score completes")


func test_account_switch_drops_the_visible_private_row_before_new_read_returns() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	var sheet := _open()
	var file := ConfigFile.new()
	file.set_value("player", "id", "p_other")
	file.set_value("session", "token", "other")
	file.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
	file.save(Community.session_path)
	net.hold("GET", ROUTE)
	Community.identity_changed.emit("p_other")
	check(not _texts(sheet).contains("My Pilot"), "switch immediately removes the old owner's private standing")
	net.answer("GET", ROUTE, 200, _payload(30, false))
	net.release_hold("GET", ROUTE)
	check(not _texts(sheet).contains("My Pilot"), "new owner never adopts the old private row")


func test_better_local_best_is_bounded_by_own_same_board_rank_in_sheet_and_preview() -> void:
	var net := _fake()
	var payload := _tied_payload()
	check(RankEstimate.estimate(900, payload.count, payload.quantiles, 2000).text.contains("~29 of 1001"), "valid nearest-rank distribution reproduces the coarser quantile estimate")
	net.answer("GET", ROUTE, 200, payload)
	var sheet := _open(900)
	var text := _texts(sheet)
	check(text.contains("Estimate: would rank #21 or better") and not text.contains("~29 of"), "better local score cannot estimate worse than the same-board exact best")
	check(text.contains("Your ranked best · Rank #21 of 1000") and _rows(sheet)[20].get_meta("board_row").points == 700, "bound does not verify the local 900-point run")
	var slot := VBoxContainer.new()
	world.add_child(slot)
	var board := Community.cached_board(SHA)
	load(SHEET).preview(slot, board, 900)
	check(_texts(slot).contains("Estimate: would rank #21 or better") and _texts(slot).contains("Cached standings") and _rows(slot).size() == 6, "cached preview uses the same snapshot bound and keeps the local score out of ranked rows")
	net.answer("GET", ROUTE, 0)
	var refresh: Button = sheet.find_child("RefreshBoard", true, false)
	refresh.pressed.emit()
	check(_texts(sheet).contains("Estimate: would rank #21 or better") and _texts(sheet).contains("Offline · cached standings"), "failed refresh marks the whole board cached once")


func test_latest_post_while_first_board_read_is_held_forces_second_read_and_updates_visible_rank() -> void:
	var net := _fake()
	var revision := _pending_score()
	net.hold("GET", ROUTE)
	net.hold("POST", "/scores")
	net.answer("GET", ROUTE, 200, _payload())
	net.answer("GET", "/nonce", 200, {"nonce": "board-latest"})
	var sheet := _open(900)
	check(net.count("GET", ROUTE) == 1 and net.count("POST", "/scores") == 1, "first board and current score upload are both held")
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": true})
	net.release_hold("POST", "/scores")
	check(Community.score_state(SHA).get("state") == "posted" and net.count("GET", ROUTE) == 1, "successful upload schedules a fresh read after the older one finishes")
	net.hold("GET", ROUTE)
	var updated := _payload()
	updated.you.rank = 7
	updated.you.points = 900
	net.answer("GET", ROUTE, 200, updated)
	net.release_hold("GET", ROUTE)
	check(net.count("GET", ROUTE) == 2, "latest posted result forces a second network read despite the newly fresh one-hour cache")
	check(not _texts(sheet).contains("Rank #7 of 30"), "new exact rank waits for the fresh board answer")
	net.release_hold("GET", ROUTE)
	var text := _texts(sheet)
	check(text.contains("Your ranked best · Rank #7 of 30") and not text.contains("Estimate:") and _rows(sheet)[20].get_meta("board_row").points == 900, "open sheet adopts the new exact rank and score")
	check(Community.queue_score("stage1", _score_run()) == "" and Community.score_state(SHA).get("revision") == revision + 1, "a newer queued revision supersedes the posted result")
	var posted := {"state": "posted", "rank": 1, "points": 999}
	Community.score_result.emit("p_other", SHA, revision + 1, posted)
	Community.score_result.emit("p_me", "b".repeat(64), revision + 1, posted)
	Community.score_result.emit("p_me", SHA, revision, posted)
	Community.score_result.emit("p_me", SHA, revision + 1, {"state": "queued"})
	await frames(2)
	check(net.count("GET", ROUTE) == 2 and _texts(sheet) == text, "stale owner/hash/revision and non-posted answers cannot fetch or alter the displayed standing")


func test_standing_formatter_shares_exact_bounds_cache_and_owner_rules_with_preview() -> void:
	_fake()
	var board := _tied_payload()
	board.owner = "p_me"
	board.cached = true
	var script: GDScript = load(SHEET)
	check(script.standing(board, 900) == "Estimate: would rank #21 or better (cached)", "results use the same exact-own bound as preview")
	check(script.standing(board, 700) == "Your ranked best · Rank #21 of 1000 (cached)", "matching local best receives the exact cached label")
	board.owner = "other"
	check(not script.standing(board, 900).contains("#21 or better"), "another owner's exact row never bounds the estimate")
	check(script.standing({}, 900) == "Estimate unavailable", "missing public distribution never invents a rank")


func test_preview_rows_are_readable_and_cached_status_is_not_repeated() -> void:
	var net := _fake()
	net.answer("GET", ROUTE, 200, _payload())
	await Community.board(SHA)
	var slot := VBoxContainer.new()
	world.add_child(slot)
	load(SHEET).preview(slot, Community.cached_board(SHA), 900)
	for row: HBoxContainer in _rows(slot):
		for label: Label in row.get_children():
			check(label.get_theme_font_size("font_size") >= 24, "rank, name, points and time remain readable in the preview")
	var labels := slot.find_children("*", "Label", true, false)
	for label: Label in labels:
		if label.text in ["Top 5", "You"]:
			check(label.get_theme_font_size("font_size") >= 28, "preview headings retain their hierarchy")
	var own: PanelContainer = slot.find_child("OwnStanding", true, false)
	check(not _texts(own).contains("(cached)"), "the banner labels the whole cached board once, not every own-standing line")
	check(labels.filter(func(label: Label) -> bool: return label.text.begins_with("Cached standings")).size() == 1, "cached state is still visible once")


func test_an_empty_preview_does_not_repeat_no_ranked_runs_in_the_own_card() -> void:
	var slot := VBoxContainer.new()
	world.add_child(slot)
	var board := _payload(0, false)
	board.cached = true
	load(SHEET).preview(slot, board, 834)
	var lines := _texts(slot).split("\n")
	check(lines.count("No ranked runs yet") == 1 and not _texts(slot).contains("No ranked runs yet (cached)"), "the empty-board message appears once while the own card retains the local score")
	check(_texts(slot).contains("Local best · 834 points"), "no-ranked-runs never hides the local best")
