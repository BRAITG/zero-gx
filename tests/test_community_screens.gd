extends "res://tests/test_case.gd"
## The community screens and the buttons that reach them, against a fake server and a fake Play Games device (tests/support/fake_*.gd).

const LEVEL_ID := "lvl_abcdefghij"
const SESSION := {"token": "tok1", "player": {"id": "p_1", "name": "Pilot"}}
const DELETE_WARNING := "This removes your scores, likes, reports and your name from Zero-GX's servers. Levels you shared stay, shown as by Deleted player."

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


func _bytes() -> PackedByteArray:
	return LevelFormat.to_json(LevelDoc.blank()).to_utf8_buffer()


func _row(bytes: PackedByteArray, title := "Loop") -> Dictionary:
	return {"level_id": LEVEL_ID, "title": title, "author": "Nova", "latest": 2, "sha256": CommunityWire.sha256_hex(bytes), "likes": 7, "players": 3}


func _rows(count: int) -> Array:
	return range(count).map(func(i: int) -> Dictionary: return {"level_id": "lvl_%010d" % i, "title": "Loop %d" % i, "author": "Nova", "latest": 1, "sha256": "%064x" % i, "likes": 0, "players": 0})


## Finishes draft `id` as it is saved now: its winning demo and the completed mark, as a won test flight leaves them.
func _finish(id: String) -> void:
	var run := Demo.new()
	run.add_frame({"position": Vector2(100, 100), "rotation": 0.0, "firing": false, "fuel": 10.0, "hull": 10.0}, {})
	run.level_sha256 = LevelFormat.sha256(MyLevels.load_level(id))
	MyLevels.save_demo(id, run)
	MyLevels.mark_completed(id)


func _finished_draft() -> String:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	_finish(id)
	return id


func _buttons(node: Node, text: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())


func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.is_visible_in_tree()).map(func(l: Label) -> String: return l.text)


func _community() -> CommunityScreen:
	var screen := CommunityScreen.new()
	world.add_child(screen)
	await frames(2)
	return screen


func _settings(screen: CommunityScreen) -> Overlay:
	var buttons := _buttons(screen, "Settings")
	check(buttons.size() == 1, "Community must offer Settings")
	if buttons.is_empty():
		return null
	buttons[0].grab_focus()
	buttons[0].pressed.emit()
	await frames(2)
	return screen.find_children("*", "Overlay", true, false).back()


func _menu() -> Control:
	var main: Control = load("res://scenes/main.gd").menu(false)
	world.add_child(main)
	return main


func _leave_scene() -> void:
	if tree.current_scene:
		tree.current_scene.free()
		tree.current_scene = null


func _send_action(action: StringName, pressed := true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_the_main_menu_has_no_community_button_on_desktop() -> void:
	var main := _menu()
	check(Community.platform is CommunityPlatform and not Community.available(), "control: the default platform is unavailable")
	check(_buttons(main, "Community").is_empty(), "desktop must not show Community")
	check(not _buttons(main, "My levels").is_empty(), "control: My levels stays")


func test_the_main_menu_shows_community_next_to_my_levels_where_available() -> void:
	_fake()
	var main := _menu()
	var labels: Array = main.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	check(labels.find("Community") == labels.find("My levels") + 1 and labels.has("Community"), "Community must follow My levels: %s" % [labels])


func test_the_first_tap_on_community_signs_in_and_opens_it() -> void:
	var net := _fake()
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	net.answer("GET", "/levels", 200, [])
	var main := _menu()
	_buttons(main, "Community")[0].pressed.emit()
	await frames(2)
	check(Community.signed_in(), "the tap must sign in")
	check(tree.current_scene is CommunityScreen, "Community must open: %s" % tree.current_scene)
	_leave_scene()


func test_a_failed_sign_in_shows_why_and_the_menu_stays() -> void:
	var net := _fake()
	pilot.sign_in_error = "Play Games sign-in was cancelled"
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	var main := _menu()
	_buttons(main, "Community")[0].pressed.emit()
	await frames(2)
	var sheets := main.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1 and "Play Games sign-in was cancelled" in _texts(sheets[0]), "the reason must show in a sheet: %s" % [sheets.map(_texts)])
	check(tree.current_scene == null and net.count("POST", "/session") == 0, "the menu must stay and no session be posted")


func test_offline_with_an_expired_session_opens_community_and_plays_from_the_cache() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := _bytes()
	var row := _row(bytes)
	net.answer("GET", "/levels", 200, [row])
	await Community.list("top", 0)
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	check(await Community.download(row) == "", "control: the level is cached")
	var file := ConfigFile.new()  # six days on: the session has run out
	file.set_value("session", "token", "old")
	file.set_value("session", "expires", int(Time.get_unix_time_from_system()) - 1)
	file.save(Community.session_path)
	net.requests.clear()
	net.answer("GET", "/nonce", 0)  # the menu's sign-in
	net.answer("GET", "/nonce", 0)  # the screen's list
	var main := _menu()
	_buttons(main, "Community")[0].pressed.emit()
	await frames(2)
	var screen := tree.current_scene
	check(screen is CommunityScreen, "offline must still open Community: %s" % screen)
	if not screen is CommunityScreen:
		return
	check("You are offline" in _texts(screen) and _buttons(screen, "Play").size() == 1, "the cached page must show with the offline note: %s" % [_texts(screen)])
	_buttons(screen, "Play")[0].pressed.emit()
	await frames(2)
	var stage := tree.current_scene
	check(stage is Level and stage.level_id == "community_" + row.sha256, "Play must open the cached stage: %s" % stage)
	check(net.count("GET", "/gh/") == 0 and net.count("GET", "/index") == 0, "the cached level needs no download")
	_leave_scene()


func test_community_lists_top_rows_with_title_version_author_and_likes() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row(_bytes())])
	var screen := await _community()
	check(net.requests.size() == 1 and net.requests[0].url.ends_with("/levels?sort=top&page=0"), "Top page 0 must be fetched first: %s" % [net.requests.map(func(r): return r.url)])
	var rows := _texts(screen).filter(func(t: String) -> bool: return t.contains("Loop"))
	check(rows.size() == 1 and rows[0].contains("v2") and rows[0].contains("Nova") and rows[0].contains("7"), "row text: %s" % [rows])
	check(_buttons(screen, "Play").size() == 1, "each row has Play")
	check(_buttons(screen, "More").is_empty(), "a short page has no More")


func test_new_switches_the_sort_and_replaces_the_rows() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row(_bytes(), "Old favourite")])
	var screen := await _community()
	net.answer("GET", "/levels", 200, [_row(_bytes(), "Fresh one")])
	_buttons(screen, "New")[0].pressed.emit()
	await frames(2)
	check(net.requests[-1].url.ends_with("/levels?sort=new&page=0"), "New must ask for sort=new page 0: %s" % net.requests[-1].url)
	var titles := _texts(screen).filter(func(t: String) -> bool: return t.contains("favourite") or t.contains("Fresh"))
	check(titles.size() == 1 and titles[0].contains("Fresh one"), "the rows must be replaced: %s" % [titles])


func test_more_asks_for_the_next_page_and_adds_its_rows() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, _rows(50))
	var screen := await _community()
	check(_buttons(screen, "Play").size() == 50 and _buttons(screen, "More").size() == 1, "a full page offers More")
	net.answer("GET", "/levels", 200, [_row(_bytes(), "Page two")])
	_buttons(screen, "More")[0].pressed.emit()
	await frames(2)
	check(net.requests[-1].url.ends_with("/levels?sort=top&page=1"), "More must ask for page 1: %s" % net.requests[-1].url)
	check(_buttons(screen, "Play").size() == 51 and _buttons(screen, "More").is_empty(), "page 2's row joins the list and a short page ends More")


func test_offline_with_no_cache_says_no_connection_and_shows_no_rows() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 0)
	var screen := await _community()
	check("No connection" in _texts(screen), "the note: %s" % [_texts(screen)])
	check(_buttons(screen, "Play").is_empty(), "no rows without a cache")


func test_offline_shows_the_last_fetched_page_with_a_note() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row(_bytes())])
	await Community.list("top", 0)
	net.answer("GET", "/levels", 0)
	var screen := await _community()
	check("You are offline" in _texts(screen), "the note: %s" % [_texts(screen)])
	check(_buttons(screen, "Play").size() == 1, "the cached row must show")


func test_play_downloads_then_opens_the_cached_stage() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := _bytes()
	var row := _row(bytes)
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	_buttons(screen, "Play")[0].pressed.emit()
	await frames(2)
	check(FileAccess.get_file_as_bytes(Community.level_path(row.sha256)) == bytes, "the level must be cached under its hash")
	var stage := tree.current_scene
	check(stage is Level and stage.level_id == "community_" + row.sha256, "Play must open community_<sha256>: %s" % stage)
	_leave_scene()


func test_a_rejected_download_shows_its_sentence_and_opens_nothing() -> void:
	var net := _fake()
	await _signed_in(net)
	var row := _row(_bytes())
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, "{\"tampered\": true}")
	_buttons(screen, "Play")[0].pressed.emit()
	await frames(2)
	var sheets := screen.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1 and "The downloaded file did not match the level list." in _texts(sheets[0]), "the sentence must show: %s" % [sheets.map(_texts)])
	check(tree.current_scene == null, "nothing may open: %s" % tree.current_scene)


func test_a_level_this_version_cannot_build_is_refused_not_opened() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := "{\"format\": \"something-else\"}".to_utf8_buffer()
	var row := _row(bytes)
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	_buttons(screen, "Play")[0].pressed.emit()
	await frames(2)
	var sheets := screen.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1 and "This level cannot be played." in _texts(sheets[0]), "the sentence must show: %s" % [sheets.map(_texts)])
	check(tree.current_scene == null, "nothing may open: %s" % tree.current_scene)


func test_a_community_stage_builds_from_the_cache_and_stands_alone() -> void:
	var net := _fake()
	var bytes := _bytes()
	var sha := CommunityWire.sha256_hex(bytes)
	DirAccess.make_dir_recursive_absolute(Community.dir)
	var file := FileAccess.open(Community.level_path(sha), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var id := "community_" + sha
	var lvl := Progress.build(id)
	world.add_child(lvl)
	await frames(2)
	check(lvl.level_id == id and lvl.level_sha256 == sha and lvl.level_data.get("format") == "zero-gx-level", "built from the cached file: %s" % lvl.level_id)
	lvl.finish(true)
	check(Progress.next_level(id) == "" and not lvl.hud._next.visible, "a community stage has no Next")
	check(lvl.hud.can_replay and lvl.hud._replay.visible, "the result card keeps Replay")
	lvl.hud.retry_requested.emit()
	await frames(2)
	check(tree.current_scene is Level and tree.current_scene.level_id == id, "Retry must reopen the same stage: %s" % tree.current_scene)
	_leave_scene()
	lvl = Progress.build(id)
	world.add_child(lvl)
	await frames(2)
	lvl.hud.menu_requested.emit()
	await frames(2)
	check(tree.current_scene is CommunityScreen, "Menu must return to Community: %s" % tree.current_scene)
	_leave_scene()


func test_the_community_screen_takes_focus_and_leaves_on_cancel() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	var focus := tree.root.gui_get_focus_owner()
	check(focus is Button and screen.is_ancestor_of(focus), "a screen must open with focus on a button, not %s" % focus)
	_send_action(&"ui_cancel")
	await frames(2)
	var scene := tree.current_scene
	check(scene != null and scene.scene_file_path == "res://scenes/main.tscn", "ui_cancel must return to the main menu: %s" % scene)
	_leave_scene()


func test_account_deletion_is_in_settings_not_the_level_list() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	check(_buttons(screen, "Delete my community account").is_empty(), "the level list must not offer deletion")
	var settings := await _settings(screen)
	if settings == null:
		return
	check("Account" in _texts(settings), "settings must group the account action")
	var deletion: Button = _buttons(settings, "Delete my community account")[0]
	check(deletion.size.x < screen.get_viewport_rect().size.x / 2, "deletion must be a normal-sized action, not full width: %s" % deletion.size)
	_send_action(&"ui_cancel")
	await frames(2)
	check(screen.is_inside_tree() and tree.current_scene == null, "closing settings must keep Community open")
	check(screen.find_children("*", "Overlay", true, false).is_empty(), "settings must close")
	check(tree.root.gui_get_focus_owner() == _buttons(screen, "Settings")[0], "focus must return to Settings")
	check(net.count("DELETE", "/me") == 0, "opening and closing settings must not delete")


func test_account_deletion_is_absent_from_settings_when_signed_out() -> void:
	_fake()
	var screen := await _community()
	var settings := await _settings(screen)
	if settings != null:
		check(_buttons(settings, "Delete my community account").is_empty(), "signed out: no deletion in settings")


func test_android_back_closes_confirmation_then_settings_without_deleting() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	var settings := await _settings(screen)
	_buttons(settings, "Delete my community account")[0].pressed.emit()
	await frames(1)
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(screen.find_children("*", "Overlay", true, false).size() == 1, "Back must close only the confirmation")
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(screen.find_children("*", "Overlay", true, false).is_empty(), "Back must then close settings")
	check(screen.is_inside_tree() and tree.current_scene == null, "Community must stay open")
	check(Community.signed_in() and net.count("DELETE", "/me") == 0, "Back must not delete the account")


func test_delete_account_asks_first_and_cancelling_sends_nothing() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	await _settings(screen)
	_buttons(screen, "Delete my community account")[0].grab_focus()
	_buttons(screen, "Delete my community account")[0].pressed.emit()
	await frames(1)
	var sheets := screen.find_children("*", "Overlay", true, false)
	check(sheets.size() == 2 and DELETE_WARNING in _texts(sheets.back()), "the confirmation must carry the warning: %s" % [sheets.map(_texts)])
	sheets.back().close()
	await frames(2)
	check(net.count("DELETE", "/me") == 0 and Community.signed_in(), "cancelling must send nothing")
	check(screen.find_children("*", "Overlay", true, false).size() == 1, "cancelling deletion must return to settings")
	check(tree.root.gui_get_focus_owner() == _buttons(screen, "Delete my community account")[0], "focus must return to the account action")


func test_confirming_deletes_the_account_and_returns_to_the_menu() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	await _settings(screen)
	_buttons(screen, "Delete my community account")[0].pressed.emit()
	await frames(1)
	net.answer("DELETE", "/me", 204)
	_buttons(screen, "Delete account")[0].pressed.emit()
	await frames(3)
	check(net.count("DELETE", "/me") == 1 and not Community.signed_in(), "the account must be deleted and the session cleared")
	var scene := tree.current_scene
	check(scene != null and scene.scene_file_path == "res://scenes/main.tscn", "the main menu must open: %s" % scene)
	_leave_scene()


func test_a_failed_deletion_shows_the_sentence_and_stays() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	await _settings(screen)
	_buttons(screen, "Delete my community account")[0].pressed.emit()
	await frames(1)
	net.answer("DELETE", "/me", 500, {"error": "Internal error."})
	_buttons(screen, "Delete account")[0].pressed.emit()
	await frames(3)
	var sheets := screen.find_children("*", "Overlay", true, false)
	check(sheets.size() == 2 and "Internal error." in _texts(sheets.back()), "the sentence must show above settings: %s" % [sheets.map(_texts)])
	check(Community.signed_in() and tree.current_scene == null, "a failed deletion keeps the session and the screen")


func test_my_levels_offers_submit_only_for_a_completed_draft_with_its_demo() -> void:
	_fake()
	var bare := MyLevels.new_id()
	MyLevels.save(bare, LevelDoc.blank())
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(_buttons(screen, "Submit").is_empty(), "a draft without a demo has no Submit")
	screen.free()
	_finished_draft()
	screen = MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(_buttons(screen, "Submit").size() == 1, "only the finished draft has Submit: %d" % _buttons(screen, "Submit").size())


func test_my_levels_shows_nothing_of_community_on_desktop() -> void:
	var net := FakeTransport.new()
	world.add_child(net)
	Community.transport = net
	var id := _finished_draft()
	MyLevels.set_level_id(id, LEVEL_ID)
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(_buttons(screen, "Submit").is_empty() and not _texts(screen).has("Pending"), "desktop shows neither Submit nor statuses")
	check(net.requests.is_empty(), "desktop must not reach the server: %s" % [net.requests])


func test_submit_sends_the_draft_and_the_row_then_shows_pending() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(not _texts(screen).has("Pending"), "control: nothing is pending yet")
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	_buttons(screen, "Submit")[0].pressed.emit()
	await frames(2)
	check(net.count("POST", "/submissions") == 1 and Community.level_id_of(id) == LEVEL_ID, "the draft must be sent and its level id kept")
	check(_texts(screen).has("Pending"), "the row must show Pending: %s" % [_texts(screen)])
	check(_buttons(screen, "Submit").is_empty(), "a submitted draft offers no second Submit")


func test_submit_signs_in_first_when_signed_out() -> void:
	var net := _fake()
	_finished_draft()
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	_buttons(screen, "Submit")[0].pressed.emit()
	await frames(2)
	check(Community.signed_in() and net.count("POST", "/submissions") == 1, "Submit must sign in and send")


func test_a_failed_submit_shows_the_sentence_and_no_status() -> void:
	var net := _fake()
	await _signed_in(net)
	_finished_draft()
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 429, {"error": "At most 5 submissions are accepted per day."})
	_buttons(screen, "Submit")[0].pressed.emit()
	await frames(2)
	var sheets := screen.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1 and "At most 5 submissions are accepted per day." in _texts(sheets[0]), "the server's sentence must show: %s" % [sheets.map(_texts)])
	check(not _texts(screen).has("Pending"), "a refused submission is not pending")


func test_my_levels_maps_submission_statuses_to_row_text() -> void:
	var net := _fake()
	await _signed_in(net)
	var open := _finished_draft()
	var approved := _finished_draft()
	var rejected := _finished_draft()
	MyLevels.set_level_id(open, "lvl_aaaaaaaaaa")
	MyLevels.set_level_id(approved, "lvl_bbbbbbbbbb")
	MyLevels.set_level_id(rejected, "lvl_cccccccccc")
	net.answer("GET", "/me/submissions", 200, [
		{"level_id": "lvl_aaaaaaaaaa", "version": 1, "status": "open", "comment": null, "pull_request": 5, "title": "A"},
		{"level_id": "lvl_bbbbbbbbbb", "version": 2, "status": "approved", "comment": null, "pull_request": 6, "title": "B"},
		{"level_id": "lvl_cccccccccc", "version": 1, "status": "rejected", "comment": "Too easy.", "pull_request": 7, "title": "C"},
	])
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	var texts := _texts(screen)
	check("Pending" in texts and "Approved v2" in texts and "Rejected: Too easy." in texts, "status lines: %s" % [texts])


func test_my_levels_shows_the_last_known_status_offline() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	MyLevels.set_level_id(id, LEVEL_ID)
	net.answer("GET", "/me/submissions", 200, [{"level_id": LEVEL_ID, "version": 3, "status": "approved", "comment": null}])
	await Community.statuses()
	net.answer("GET", "/me/submissions", 0)
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check("Approved v3" in _texts(screen), "offline must show the last known status: %s" % [_texts(screen)])


func test_my_levels_shows_submitted_for_an_unchanged_draft_until_it_is_edited() -> void:
	_fake()
	var id := _finished_draft()
	MyLevels.set_submitted(id, LevelFormat.sha256(MyLevels.load_level(id)))
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(_buttons(screen, "Submit").is_empty() and _texts(screen).has("Submitted"), "an unchanged submitted draft shows Submitted and no Submit: %s" % [_texts(screen)])
	screen.free()
	var edited := MyLevels.load_level(id)
	edited.title = "Edited"
	MyLevels.save(id, edited)
	_finish(id)  # tested and won again
	screen = MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(_buttons(screen, "Submit").size() == 1 and not _texts(screen).has("Submitted"), "an edited draft offers Submit again: %s" % [_texts(screen)])


func test_the_community_button_says_signing_in_and_is_off_while_it_waits() -> void:
	var net := _fake()
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	net.answer("GET", "/levels", 200, [])
	net.held = true
	var main := _menu()
	var button: Button = _buttons(main, "Community")[0]
	button.pressed.emit()
	check(button.text == "Signing in…" and button.disabled, "while it waits: %s, disabled %s" % [button.text, button.disabled])
	net.release()
	await frames(2)
	check(button.text == "Community" and not button.disabled, "afterwards the button is as before: %s" % button.text)
	check(tree.current_scene is CommunityScreen, "Community must open: %s" % tree.current_scene)
	_leave_scene()


func test_submit_says_submitting_and_is_off_while_it_waits_then_comes_back_after_a_refusal() -> void:
	var net := _fake()
	await _signed_in(net)
	_finished_draft()
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 429, {"error": "At most 5 submissions are accepted per day."})
	net.held = true
	var submit: Button = _buttons(screen, "Submit")[0]
	submit.pressed.emit()
	check(submit.text == "Submitting…" and submit.disabled, "while it waits: %s, disabled %s" % [submit.text, submit.disabled])
	net.release()
	await frames(2)
	check(submit.text == "Submit" and not submit.disabled, "a refused submission gives the button back: %s" % submit.text)


func test_play_says_loading_and_is_off_while_the_level_downloads() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := _bytes()
	net.answer("GET", "/levels", 200, [_row(bytes)])
	var screen := await _community()
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	net.held = true
	var play: Button = _buttons(screen, "Play")[0]
	play.pressed.emit()
	check(play.text == "Loading…" and play.disabled, "while it waits: %s, disabled %s" % [play.text, play.disabled])
	net.release()
	await frames(2)
	check(play.text == "Play" and not play.disabled, "afterwards the button is as before: %s" % play.text)
	check(tree.current_scene is Level, "the level must open: %s" % tree.current_scene)
	_leave_scene()


func test_more_says_loading_and_is_off_while_the_next_page_arrives() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, _rows(50))
	var screen := await _community()
	net.answer("GET", "/levels", 200, [_row(_bytes(), "Page two")])
	net.held = true
	var more: Button = _buttons(screen, "More")[0]
	more.pressed.emit()
	check(more.text == "Loading…" and more.disabled, "while it waits: %s, disabled %s" % [more.text, more.disabled])
	net.release()
	await frames(2)
	check(more.text == "More" and not more.disabled, "afterwards the button is as before: %s" % more.text)


func test_delete_account_says_deleting_and_is_off_while_it_waits() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	await _settings(screen)
	_buttons(screen, "Delete my community account")[0].pressed.emit()
	await frames(1)
	net.answer("DELETE", "/me", 204)
	net.held = true
	var confirm: Button = _buttons(screen, "Delete account")[0]
	confirm.pressed.emit()
	check(confirm.text == "Deleting…" and confirm.disabled, "while it waits: %s, disabled %s" % [confirm.text, confirm.disabled])
	net.release()
	await frames(3)
	check(not Community.signed_in(), "the account must be deleted")
	_leave_scene()
