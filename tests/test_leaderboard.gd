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
	var scores := CommunityScores.new()
	scores.path = Community.history_path.get_basename() + "_scores.json"
	check(scores.load_file() == OK, "isolated score outbox loads")
	var run := Demo.new()
	run.level_sha256 = SHA
	run.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 50.0, "hull": 50.0}, {})
	run.add_event(Demo.Event.GOAL_REACHED)
	check(scores.enqueue("p_me", "stage1", SHA, run.encode()) == OK, "score is already durable before opening")
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
