extends "res://tests/test_case.gd"
## The community screens and the buttons that reach them, against a fake server and a fake Play Games device (tests/support/fake_*.gd).

const LEVEL_ID := "lvl_abcdefghij"
const SESSION := {"token": "tok1", "player": {"id": "p_1", "name": "Pilot"}}
const DELETE_WARNING := "This removes your scores, likes, reports, play history, difficulty ratings and your name from Zero-GX's servers. Levels you shared stay, shown as by Deleted player."
const MAIN := preload("res://scenes/main.gd")

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
	return {"level_id": LEVEL_ID, "title": title, "author": "Nova", "latest": 2, "sha256": CommunityWire.sha256_hex(bytes), "likes": 7, "players": 3, "starters": 64}


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


func _my_levels() -> MyLevelsScreen:
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	return screen


func _sheets(node: Node) -> Array:
	return node.find_children("*", "Overlay", true, false)


## How many POSTs the fake server has seen: sign-in and submission are the only ones.
func _posts(net: FakeTransport) -> int:
	return net.requests.filter(func(r: Dictionary) -> bool: return r.method == "POST").size()


## Taps row `index` of My levels: the level's sheet.
func _open_row(screen: MyLevelsScreen, index := 0) -> void:
	screen._list.get_child(index).pressed.emit()
	await frames(2)


## Row, then Publish in its sheet: the Publish sheet, which replaces the level's.
func _open_publish(screen: MyLevelsScreen, index := 0) -> void:
	await _open_row(screen, index)
	_buttons(screen, "Publish")[0].pressed.emit()
	await frames(2)


## The actions the level's sheet offers, in order (its Close excluded); the sheet is closed again.
func _actions(screen: MyLevelsScreen, index := 0) -> Array:
	await _open_row(screen, index)
	var sheet: Overlay = _sheets(screen).back()
	var actions: Array = sheet.body.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	sheet.close()
	await frames(2)
	return actions


## Publish, then Use previous run: step 1 done; only Submit for review leaves the sheet.
func _confirmation(screen: MyLevelsScreen) -> void:
	await _open_publish(screen)
	_buttons(screen, "Use previous run")[0].pressed.emit()
	await frames(2)


## Chooses a Suggested difficulty in the open confirmation, as a player does: the choice Submit for review waits for.
func _suggest(node: Node, value := "hard") -> void:
	var options := node.find_children("*", "OptionButton", true, false)
	check(options.size() == 1, "the confirmation asks for one Suggested difficulty: %d" % options.size())
	if options.size() != 1:
		return
	var option: OptionButton = options[0]
	for i in option.item_count:
		if option.get_item_metadata(i) == value:
			option.select(i)
			option.item_selected.emit(i)


## Publish, then `choice` ("Play to prove it" or "Play again"): the flight that replaces the screen, or null.
func _fly_proof(screen: MyLevelsScreen, choice: String) -> Level:
	await _open_publish(screen)
	_buttons(screen, choice)[0].pressed.emit()
	await frames(2)
	return tree.current_scene as Level


func _buttons(node: Node, text: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())


func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.is_visible_in_tree()).map(func(l: Label) -> String: return l.text)


func _community() -> CommunityScreen:
	var screen := CommunityScreen.new()
	world.add_child(screen)
	await frames(2)
	return screen


## The gear that opens Community settings, pressed as a player does.
func _gear(screen: CommunityScreen) -> Button:
	var gears := screen.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.tooltip_text == "Community settings")
	check(gears.size() == 1, "Community must offer one gear for settings: %d" % gears.size())
	return gears[0] if gears.size() == 1 else null


func _settings(screen: CommunityScreen) -> Overlay:
	var gear := _gear(screen)
	if gear == null:
		return null
	gear.grab_focus()
	gear.pressed.emit()
	await frames(2)
	return screen.find_children("*", "Overlay", true, false).back()


func _menu() -> Control:
	var main: Control = MAIN.menu(MAIN.Page.HOME)
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
	check(_buttons(main, "Community levels").is_empty(), "desktop must not show Community")
	check(not _buttons(main, "My levels").is_empty(), "control: My levels stays")


func test_community_is_offered_on_home_and_not_on_the_lists() -> void:
	_fake()
	var home := _menu()
	check(not _buttons(home, "Community levels").is_empty(), "home must offer Community where it is available")
	home.free()
	var list := MAIN.menu(MAIN.Page.OFFICIAL)
	world.add_child(list)
	check(_buttons(list, "Community levels").is_empty(), "the official list must not offer Community")
	list.free()


func test_the_first_tap_on_community_signs_in_and_opens_it() -> void:
	var net := _fake()
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	net.answer("GET", "/levels", 200, [])
	var main := _menu()
	_buttons(main, "Community levels")[0].pressed.emit()
	await frames(2)
	check(Community.signed_in(), "the tap must sign in")
	check(tree.current_scene is CommunityScreen, "Community must open: %s" % tree.current_scene)
	_leave_scene()


func test_a_failed_sign_in_shows_why_and_the_menu_stays() -> void:
	var net := _fake()
	pilot.sign_in_error = "Play Games sign-in was cancelled"
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	var main := _menu()
	_buttons(main, "Community levels")[0].pressed.emit()
	await frames(2)
	var sheets := main.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1 and "Play Games sign-in was cancelled" in _texts(sheets[0]), "the reason must show in a sheet: %s" % [sheets.map(_texts)])
	check(tree.current_scene == null and net.count("POST", "/session") == 0, "the menu must stay and no session be posted")


func test_a_failed_sign_in_gives_the_community_button_back() -> void:
	var net := _fake()
	pilot.sign_in_error = "Play Games sign-in was cancelled"
	pilot.sign_in_held = true
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	var main := _menu()
	var button: Button = _buttons(main, "Community levels")[0]
	button.pressed.emit()
	check(button.disabled, "while it waits the button must be off")
	pilot.release_sign_in()
	await frames(2)
	check(not button.disabled and button.text == "Community levels", "a failed sign-in must give the button back: %s" % button.text)
	check(main.find_children("*", "Overlay", true, false).size() == 1, "the failure must show in a sheet")
	main.free()


func test_offline_with_an_expired_session_opens_community_and_plays_from_the_cache() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := _bytes()
	var row := _row(bytes)
	net.answer("GET", "/levels", 200, [row])
	await Community.list("popular", 0)
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
	_buttons(main, "Community levels")[0].pressed.emit()
	await frames(2)
	var screen := tree.current_scene
	check(screen is CommunityScreen, "offline must still open Community: %s" % screen)
	if not screen is CommunityScreen:
		return
	check("Offline: showing saved levels" in _texts(screen) and _buttons(screen, "Play").size() == 1, "the cached page must show with the offline banner: %s" % [_texts(screen)])
	_buttons(screen, "Play")[0].pressed.emit()
	await frames(2)
	var stage := tree.current_scene
	check(stage is Level and stage.level_id == "community_" + row.sha256, "Play must open the cached stage: %s" % stage)
	check(net.count("GET", "/gh/") == 0 and net.count("GET", "/index") == 0, "the cached level needs no download")
	_leave_scene()


func test_rows_show_title_author_chip_hearts_and_players() -> void:
	var net := _fake()
	await _signed_in(net)
	var row := _row(_bytes())
	row.rated = "hard"
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	check(net.requests.size() == 1 and net.requests[0].url.ends_with("/levels?sort=popular&page=0"), "Popular page 0 must be fetched first: %s" % [net.requests.map(func(r): return r.url)])
	var texts := _texts(screen)
	for expected in ["Loop", "by Nova", "Rated Hard", "♥ 7", "64 players"]:
		check(expected in texts, "the row must show %s: %s" % [expected, texts])
	check(not texts.any(func(t: String) -> bool: return t.contains("v2")), "versions belong to the details sheet: %s" % [texts])
	check(_buttons(screen, "Play").size() == 1, "each row has Play")
	check(_buttons(screen, "More").is_empty(), "a short page has no More")


func test_the_row_button_opens_details_and_play_is_its_sibling() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row(_bytes())])
	var screen := await _community()
	var rows := screen.find_children("Row", "Button", true, false)
	var play: Button = _buttons(screen, "Play")[0]
	check(rows.size() == 1 and rows[0].get_parent() == play.get_parent() and not rows[0].is_ancestor_of(play), "Play must be a sibling of the row button, not a child")
	check(rows[0].size.y == 100 and play.focus_mode == Control.FOCUS_ALL, "the row is 100 px high and Play has its own focus stop: %s" % rows[0].size)
	check(_sheets(screen).is_empty(), "control: no sheet yet")
	rows[0].pressed.emit()
	await frames(2)
	check(_sheets(screen).size() == 1, "the row must open the details sheet")


func test_the_sort_and_filter_chips_request_the_right_list() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	for step in [["Hard", "sort=popular&page=0&difficulty=hard"], ["New", "sort=new&page=0&difficulty=hard"], ["All", "sort=new&page=0"], ["Expert", "sort=new&page=0&difficulty=expert"], ["Popular", "sort=popular&page=0&difficulty=expert"]]:
		net.answer("GET", "/levels", 200, [])
		_buttons(screen, step[0])[0].pressed.emit()
		await frames(2)
		check(net.requests[-1].url.ends_with("/levels?" + step[1]), "%s must ask for %s: %s" % [step[0], step[1], net.requests[-1].url])


func test_an_empty_filter_says_so_and_show_all_clears_it() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row(_bytes())])
	var screen := await _community()
	check(_buttons(screen, "Show all").is_empty(), "control: All offers no Show all")
	net.answer("GET", "/levels", 200, [])
	_buttons(screen, "Hard")[0].pressed.emit()
	await frames(2)
	check("No Hard levels yet" in _texts(screen) and _buttons(screen, "Play").is_empty(), "the empty filter must say so: %s" % [_texts(screen)])
	check(_buttons(screen, "Show all").size() == 1, "and offer Show all")
	net.answer("GET", "/levels", 200, [])
	net.held = true
	_buttons(screen, "All")[0].pressed.emit()
	await frames(2)
	check(not screen._note.visible, "the empty note must go while another filter loads: %s" % [_texts(screen)])
	net.release()
	await frames(2)
	net.answer("GET", "/levels", 200, [])
	_buttons(screen, "Hard")[0].pressed.emit()  # back to the empty filter
	await frames(2)
	net.answer("GET", "/levels", 200, [_row(_bytes())])
	_buttons(screen, "Show all")[0].pressed.emit()
	await frames(2)
	check(net.requests[-1].url.ends_with("/levels?sort=popular&page=0"), "Show all must ask for every level: %s" % net.requests[-1].url)
	check(_buttons(screen, "Play").size() == 1 and _buttons(screen, "Show all").is_empty(), "the rows return and Show all goes")
	check(_buttons(screen, "All")[0].button_pressed, "All must be the chosen chip again")
	net.answer("GET", "/levels", 200, [])
	screen.free()
	screen = await _community()
	check("No levels yet" in _texts(screen) and _buttons(screen, "Show all").is_empty(), "an empty All says No levels yet: %s" % [_texts(screen)])


func test_a_first_load_shows_placeholders_and_a_refresh_keeps_the_rows_until_the_page_arrives() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row(_bytes(), "Old favourite")])
	net.held = true
	var screen := await _community()
	check(screen._rows.get_child_count() == 3 and _buttons(screen, "Play").is_empty(), "a first load shows three placeholder rows")
	net.release()
	await frames(2)
	check(screen._rows.get_child_count() == 1 and _buttons(screen, "Play").size() == 1, "the page replaces the placeholders")
	net.answer("GET", "/levels", 200, [_row(_bytes(), "Fresh one")])
	net.held = true
	_buttons(screen, "New")[0].pressed.emit()
	await frames(2)
	var titles := _texts(screen)
	check("Old favourite" in titles and not "Fresh one" in titles and screen._rows.get_child_count() == 1, "a refresh keeps the rows meanwhile: %s" % [titles])
	net.release()
	await frames(2)
	titles = _texts(screen)
	check("Fresh one" in titles and not "Old favourite" in titles, "the new page replaces them: %s" % [titles])


func test_a_long_title_is_trimmed_and_a_row_without_a_chip_leaves_no_gap() -> void:
	var net := _fake()
	await _signed_in(net)
	var row := _row(_bytes(), "An exceedingly long level title that keeps going and going well past the end of the row")
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	var title: Label = screen.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == row.title)[0]
	var heart: Label = screen.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "♥ 7")[0]
	var font := title.get_theme_font("font")
	check(title.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and title.size.x < font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x, "the long title must be trimmed, not widen the row: %s" % title.size)
	check(heart.get_global_rect().position.x == title.get_global_rect().position.x, "without a chip the meta line starts at the text edge: %s vs %s" % [heart.global_position, title.global_position])
	check(screen.find_children("*", "DifficultyChip", true, false).is_empty(), "no chip for a level without a difficulty")
	var play: Button = _buttons(screen, "Play")[0]
	check(play.get_global_rect().end.x <= screen.get_viewport_rect().size.x, "Play must stay on screen: %s" % play.get_global_rect())


func test_a_row_shows_the_players_own_tries_and_clear() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := _bytes()
	var row := _row(bytes)
	net.answer("GET", "/levels", 200, [row])
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	check(await Community.download(row) == "", "setup: the level is downloaded")
	Community.record_play_start(row.sha256)
	Community.record_play_start(row.sha256)
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	check("2 tries" in _texts(screen), "two starts show as tries: %s" % [_texts(screen)])
	screen.free()
	Community.record_play_finish(Community.record_play_start(row.sha256), "cleared")
	net.answer("GET", "/levels", 200, [row])
	screen = await _community()
	check("Cleared" in _texts(screen) and not _texts(screen).any(func(t: String) -> bool: return t.ends_with("tries")), "a clear shows Cleared: %s" % [_texts(screen)])


func test_the_gear_opens_community_settings_and_replaces_the_settings_button() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [])
	var screen := await _community()
	var gear := _gear(screen)
	check(gear != null and gear.text == "⚙" and _buttons(screen, "Settings").is_empty(), "the gear takes the place of the Settings button")
	var settings := await _settings(screen)
	check(settings != null and "Community settings" in _texts(settings), "the gear opens Community settings: %s" % [_texts(settings) if settings else null])


func test_community_rows_show_a_sketch_thumbnail() -> void:
	var net := _fake()
	await _signed_in(net)
	var with_sketch := _row(_bytes())
	with_sketch.sketch = LevelFormat.sketch(LevelFormat.read(Progress.LEVELS_DIR + "level_01.json"))
	var without := _row(_bytes(), "Bare")
	without.sketch = null
	net.answer("GET", "/levels", 200, [with_sketch, without])
	var screen := await _community()
	var thumbnails := screen.find_children("*", "Thumbnail", true, false)
	check(thumbnails.size() == 2, "every row carries a thumbnail: %d" % thumbnails.size())
	check(not thumbnails[0].sketch.is_empty() and thumbnails[1].sketch.is_empty(), "the sketch reaches the first row only")
	check(_texts(screen).any(func(t: String) -> bool: return t.contains("Bare")), "a row without a sketch keeps its title")


func test_community_row_shows_a_medal_for_a_local_best() -> void:
	var net := _fake()
	await _signed_in(net)
	var row := _row(_bytes())
	row.par = 1000
	net.answer("GET", "/levels", 200, [row])
	Progress.record_win(Community.STAGE_PREFIX + row.sha256, 800, 20.0)  # 800 of par 1000 is silver: at least 70%
	var screen := await _community()
	check(medal_tiers(screen) == [Progress.Medal.SILVER], "a best of 800 on par 1000 shows one silver medal: %s" % [medal_tiers(screen)])


func test_community_row_without_best_or_par_shows_no_medal() -> void:
	var net := _fake()
	await _signed_in(net)
	var row := _row(_bytes())
	row.par = 1000
	net.answer("GET", "/levels", 200, [row])
	var screen := await _community()
	check(medal_tiers(screen).is_empty(), "a par without a best shows no medal: %s" % [medal_tiers(screen)])
	screen.free()
	Progress.record_win(Community.STAGE_PREFIX + row.sha256, 800, 20.0)
	row.par = null  # the server's answer for a level without a par
	net.answer("GET", "/levels", 200, [row])
	screen = await _community()
	check(medal_tiers(screen).is_empty(), "a best without a par shows no medal: %s" % [medal_tiers(screen)])


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
	check(net.requests[-1].url.ends_with("/levels?sort=popular&page=1"), "More must ask for page 1: %s" % net.requests[-1].url)
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
	await Community.list("popular", 0)
	net.answer("GET", "/levels", 0)
	var screen := await _community()
	check("Offline: showing saved levels" in _texts(screen), "the banner: %s" % [_texts(screen)])
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
	check(tree.root.gui_get_focus_owner() == _gear(screen), "focus must return to the gear")
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


func test_my_levels_offers_publish_for_a_draft_that_was_never_tested() -> void:
	var net := _fake()
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var screen := await _my_levels()
	check(not MyLevels.is_completed(id) and MyLevels.demo(id) == null, "control: the draft was never finished in Test")
	var actions := await _actions(screen)
	check("Publish" in actions, "a draft with no run must still offer Publish: %s" % [actions])
	check(not "Submit" in actions, "the old Submit entry point must be gone")
	check(_posts(net) == 0, "listing the drafts uploads nothing")


func test_tapping_a_row_opens_its_sheet_with_edit_first_and_delete_last_in_danger() -> void:
	_fake()
	var id := _finished_draft()  # a run, so Watch as well
	var screen := await _my_levels()
	check(_sheets(screen).is_empty(), "control: no sheet before the tap")
	await _open_row(screen)
	var sheets := _sheets(screen)
	check(sheets.size() == 1, "the row opens one sheet: %d" % sheets.size())
	var sheet: Overlay = sheets.back()
	var actions: Array = sheet.body.find_children("*", "Button", true, false)
	check(actions.map(func(b: Button) -> String: return b.text) == ["Edit", "Play", "Watch", "Publish", "Export", "Delete"], "actions: %s" % [actions.map(func(b: Button) -> String: return b.text)])
	check(sheet.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == MyLevels.load_level(id).title), "the sheet is titled with the level")
	var edit: Button = actions[0]
	check(edit.get_theme_stylebox("normal") == edit.get_theme_stylebox("pressed"), "Edit is the primary action")
	check(actions.back().get_theme_color("font_color") == Hud.WARNING, "Delete is in the danger colour")
	var width := screen.get_viewport_rect().size.x
	check(actions.all(func(b: Button) -> bool: return b.get_global_rect().end.x <= width), "no button runs off the screen")


func test_the_level_sheet_closes_before_an_action_and_delete_still_confirms() -> void:
	_fake()
	var id := _finished_draft()
	var screen := await _my_levels()
	await _open_row(screen)
	_buttons(screen, "Delete")[0].pressed.emit()
	await frames(2)
	var sheets := _sheets(screen)
	check(sheets.size() == 1 and "“Untitled” will be gone for good.".replace("Untitled", MyLevels.load_level(id).title) in _texts(sheets[0]), "Delete asks first: %s" % [sheets.map(_texts)])
	check(MyLevels.ids().has(id), "nothing is deleted before the confirmation")
	_buttons(screen, "Delete")[0].pressed.emit()
	await frames(2)
	check(not MyLevels.ids().has(id) and _sheets(screen).is_empty(), "the confirmation deletes the level")


func test_the_level_sheet_shows_the_whole_moderator_comment_the_row_cuts() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	MyLevels.set_level_id(id, LEVEL_ID)
	MyLevels.set_submitted(id, LevelFormat.sha256(MyLevels.load_level(id)))
	var comment := "Too easy. ".repeat(30).strip_edges()  # 299 characters: the server keeps up to 500
	net.answer("GET", "/me/submissions", 200, [{"level_id": LEVEL_ID, "version": 1, "status": "rejected", "comment": comment}])
	var screen := await _my_levels()
	await _open_row(screen)
	var shown: Array = _texts(_sheets(screen).back())
	var line: Array = shown.filter(func(t: String) -> bool: return t.begins_with("Rejected: "))
	check(line.size() == 1 and line[0] == "Rejected: " + comment, "the sheet shows the full status: %s" % [shown])
	var label: Label = _sheets(screen).back().find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text.begins_with("Rejected: "))[0]
	check(label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "the paragraph wraps instead of trimming")


func test_a_row_is_one_status_per_the_spec() -> void:
	var net := _fake()
	await _signed_in(net)
	var broken := LevelDoc.blank()
	broken.goal.position = [0, 0]
	var fix_id := MyLevels.new_id()
	MyLevels.save(fix_id, broken)
	var untested := MyLevels.new_id()
	MyLevels.save(untested, LevelDoc.blank())
	var ready := _finished_draft()
	var review := _finished_draft()
	var rejected := _finished_draft()
	var published := _finished_draft()
	var edited := _finished_draft()
	for pair in [[review, "lvl_aaaaaaaaaa"], [rejected, "lvl_bbbbbbbbbb"], [published, "lvl_cccccccccc"], [edited, "lvl_dddddddddd"]]:
		MyLevels.set_level_id(pair[0], pair[1])
		MyLevels.set_submitted(pair[0], LevelFormat.sha256(MyLevels.load_level(pair[0])))
	var sha := LevelFormat.sha256(MyLevels.load_level(published))
	net.answer("GET", "/me/submissions", 200, [
		{"level_id": "lvl_aaaaaaaaaa", "version": 1, "status": "open", "comment": null},
		{"level_id": "lvl_bbbbbbbbbb", "version": 1, "status": "rejected", "comment": "Too easy."},
		{"level_id": "lvl_cccccccccc", "version": 2, "status": "approved", "comment": null, "sha256": sha, "rated": "hard", "starters": 64, "likes": 42},
		{"level_id": "lvl_dddddddddd", "version": 3, "status": "approved", "comment": null, "sha256": "%064x" % 5, "rated": "hard", "starters": 64, "likes": 42},
	])
	var screen := await _my_levels()
	var statuses: Array = screen._list.get_children().map(func(row: Button) -> String: return row.find_children("*", "Label", true, false)[1].text)
	statuses.sort()
	var expected := ["Needs fixes: " + LevelFormat.validate(broken)[0], "Not tested yet", "Ready to publish", "In review", "Rejected: Too easy.", "Published v2 · Hard · 64 players · ♥ 42", "Published v3 · edited since"]
	expected.sort()
	check(statuses == expected, "status lines: %s" % [statuses])
	check(screen._list.get_child_count() == 7, "one row per level")


func test_the_publish_sheet_shows_three_steps_names_the_level_and_submits_only_with_a_difficulty() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var screen := await _my_levels()
	await _open_publish(screen)
	var sheets := _sheets(screen)
	check(sheets.size() == 1, "one Publish sheet replaces the level's sheet: %d" % sheets.size())
	var words: Array = _texts(sheets.back())
	check(words.has("1. Prove it can be finished") and words.has("2. Suggest a difficulty") and words.has("3. Submit for review"), "the three steps: %s" % [words])
	check(words.has("“%s”" % MyLevels.load_level(id).title), "the sheet names the level: %s" % [words])
	check(" ".join(words).contains("A moderator chooses the reviewed difficulty"), "the moderator note stays")
	check(_buttons(screen, "Use previous run").size() == 1 and not words.has("✓ Saved run"), "an unconfirmed run is offered, not yet saved")
	var submit: Button = _buttons(screen, "Submit for review")[0]
	check(submit.disabled, "Submit waits for the run and a difficulty")
	_buttons(screen, "Use previous run")[0].grab_focus()  # as a tap or the pad leaves it
	_buttons(screen, "Use previous run")[0].pressed.emit()
	await frames(2)
	check(_texts(screen).has("✓ Saved run") and _buttons(screen, "Use previous run").is_empty() and _buttons(screen, "Play again").size() == 1, "the run is saved: %s" % [_texts(screen)])
	var focus := screen.get_viewport().gui_get_focus_owner()
	check(focus != null and sheets.back().is_ancestor_of(focus), "focus must stay in the Publish sheet after Use previous run: %s" % focus)
	check(_buttons(screen, "Submit for review")[0].disabled, "a saved run alone does not enable Submit")
	_suggest(screen)
	check(not _buttons(screen, "Submit for review")[0].disabled, "run and difficulty enable Submit")
	check(_posts(net) == 0, "nothing uploads before Submit")


func test_publish_without_a_run_asks_for_a_proof_and_sends_nothing() -> void:
	var net := _fake()
	await _signed_in(net)
	MyLevels.save(MyLevels.new_id(), LevelDoc.blank())
	var screen := await _my_levels()
	await _open_publish(screen)
	check(_sheets(screen).size() == 1 and _buttons(screen, "Play to prove it").size() == 1, "a draft with no run must be asked to prove it: %s" % [_sheets(screen).map(_texts)])
	check(_buttons(screen, "Use previous run").is_empty() and _buttons(screen, "Play again").is_empty(), "there is no previous run to offer")
	check(_posts(net) == 0, "opening Publish must upload nothing")


func test_publish_offers_the_previous_run_only_while_it_matches_the_draft() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var screen := await _my_levels()
	await _open_publish(screen)
	check(_buttons(screen, "Use previous run").size() == 1 and _buttons(screen, "Play again").size() == 1, "an unchanged draft with its run offers both")
	check(_buttons(screen, "Play to prove it").is_empty(), "a current run needs no proof")
	screen.free()
	var edited := MyLevels.load_level(id)
	edited.title = "Edited"
	MyLevels.save(id, edited)  # the run was of the draft as it was
	screen = await _my_levels()
	await _open_publish(screen)
	check(_buttons(screen, "Play to prove it").size() == 1, "an edited draft must prove itself again")
	check(_buttons(screen, "Use previous run").is_empty() and _buttons(screen, "Play again").is_empty(), "the stale run must not be offered")
	check(_posts(net) == 0, "choosing nothing uploads nothing")


func test_publish_requires_a_decodable_previous_run_not_just_its_header() -> void:
	var net := _fake()
	var id := _finished_draft()
	var bytes := FileAccess.get_file_as_bytes(MyLevels.demo_path(id)).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	bytes.resize(bytes.size() - 3)
	var file := FileAccess.open(MyLevels.demo_path(id), FileAccess.WRITE)
	file.store_buffer(bytes.compress(FileAccess.COMPRESSION_GZIP))
	file.close()
	check(MyLevels.has_demo(id) and MyLevels.demo(id) == null, "control: the header matches, but the recording cannot decode")
	var screen := await _my_levels()
	await _open_publish(screen)
	check(_buttons(screen, "Use previous run").is_empty() and _buttons(screen, "Play to prove it").size() == 1, "a broken recording needs a new proof flight")
	check(_posts(net) == 0, "opening Publish sends nothing")


func test_publish_refuses_a_draft_that_breaks_the_level_rules_and_names_why() -> void:
	var net := _fake()
	await _signed_in(net)
	var data := LevelDoc.blank()
	data.goal.position = [0, 0]  # the ship would start inside the goal
	MyLevels.save(MyLevels.new_id(), data)
	var problems := LevelFormat.validate(data)
	check(not problems.is_empty(), "control: the draft is invalid")
	var screen := await _my_levels()
	await _open_publish(screen)
	var sheets := _sheets(screen)
	check(sheets.size() == 1 and problems[0] in _texts(sheets[0]), "the sheet must name the problem: %s" % [sheets.map(_texts)])
	check(_buttons(screen, "Play to prove it").is_empty() and _buttons(screen, "Use previous run").is_empty(), "an invalid draft offers no proof")
	check(tree.current_scene == null and _posts(net) == 0, "nothing may fly or upload")


func test_use_previous_run_asks_for_the_final_confirmation_before_anything_is_sent() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var screen := await _my_levels()
	await _confirmation(screen)
	var sheets := _sheets(screen)
	check(sheets.size() == 1 and _buttons(screen, "Submit for review").size() == 1, "one sheet with Submit for review: %s" % [sheets.map(_texts)])
	var words := " ".join(_texts(sheets.back()))
	check(words.contains("moderator") and words.contains("recording"), "the sheet must say the level and its recording go to moderators: %s" % words)
	check(_posts(net) == 0, "the confirmation alone must send nothing")
	sheets[0].close()
	await frames(2)
	check(_sheets(screen).is_empty() and _posts(net) == 0 and not MyLevels.is_submitted(id), "closing the confirmation sends nothing")
	check("Publish" in await _actions(screen), "the draft is still unpublished")


func test_my_levels_shows_nothing_of_community_on_desktop() -> void:
	var net := FakeTransport.new()
	world.add_child(net)
	Community.transport = net
	var id := _finished_draft()
	MyLevels.set_level_id(id, LEVEL_ID)
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	var actions := await _actions(screen)
	check(not "Publish" in actions and not "In review" in _texts(screen) and not "Submitted" in _texts(screen), "desktop shows neither Publish nor submission statuses: %s %s" % [actions, _texts(screen)])
	check(_texts(screen).has("Ready to publish"), "desktop still shows the draft statuses: %s" % [_texts(screen)])
	check(net.requests.is_empty(), "desktop must not reach the server: %s" % [net.requests])


func test_submit_for_review_sends_the_draft_and_the_row_then_shows_pending() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var screen := await _my_levels()
	check(not _texts(screen).has("In review"), "control: nothing is in review yet")
	await _confirmation(screen)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	_suggest(screen)
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(3)
	check(net.count("POST", "/submissions") == 1 and Community.level_id_of(id) == LEVEL_ID, "the draft must be sent and its level id kept")
	check(_texts(screen).has("In review"), "the row must show In review: %s" % [_texts(screen)])
	check(not "Publish" in await _actions(screen), "a submitted draft offers no second Publish")
	check(_sheets(screen).is_empty(), "the confirmation closes once the server took the level")


func test_submit_for_review_signs_in_first_when_signed_out() -> void:
	var net := _fake()
	_finished_draft()
	var screen := await _my_levels()
	await _confirmation(screen)
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	_suggest(screen)
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(2)
	check(Community.signed_in() and net.count("POST", "/submissions") == 1, "Submit for review must sign in and send")


func test_a_failed_submit_shows_the_sentence_and_no_status() -> void:
	var net := _fake()
	await _signed_in(net)
	_finished_draft()
	var screen := await _my_levels()
	await _confirmation(screen)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 429, {"error": "At most 5 submissions are accepted per day."})
	_suggest(screen)
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(2)
	var sheets := _sheets(screen)
	check(sheets.size() == 2 and "At most 5 submissions are accepted per day." in _texts(sheets.back()), "the server's sentence must show above the confirmation: %s" % [sheets.map(_texts)])
	check(not _texts(screen).has("In review"), "a refused submission is not in review")
	sheets.back().close()
	sheets[0].close()
	await frames(2)
	check("Publish" in await _actions(screen), "a refused draft is still offered")


func test_android_back_closes_publish_sheets_without_leaving_or_submitting() -> void:
	var net := _fake()
	_finished_draft()
	var screen := await _my_levels()
	await _open_publish(screen)
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(_sheets(screen).is_empty() and tree.current_scene == null, "Back closes the proof choice and stays in My levels")
	await _confirmation(screen)
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(_sheets(screen).is_empty() and tree.current_scene == null and _posts(net) == 0, "Back closes the confirmation without submitting")


func test_submit_for_review_rechecks_the_draft_after_the_confirmation_opened() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var screen := await _my_levels()
	await _confirmation(screen)
	var edited := MyLevels.load_level(id)
	edited.title = "Changed after confirmation"
	MyLevels.save(id, edited)
	_suggest(screen)
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(2)
	var sheets := _sheets(screen)
	check(sheets.size() == 2 and Community.NOT_SUBMITTABLE in _texts(sheets.back()), "the stale proof must be refused with the existing error")
	check(_posts(net) == 0 and not MyLevels.is_submitted(id), "a stale confirmation must upload nothing")


func test_play_to_prove_it_flies_this_draft_as_a_test_flight_with_publish_intent() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var stage := await _fly_proof(await _my_levels(), "Play to prove it")
	check(stage != null and stage.level_id == id and stage.testing, "the proof must be a test flight of this draft: %s" % stage)
	check(_posts(net) == 0, "starting the flight uploads nothing")
	_leave_scene()


func test_play_again_flies_the_draft_with_publish_intent() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var stage := await _fly_proof(await _my_levels(), "Play again")
	check(stage != null and stage.level_id == id and stage.testing, "Play again must be a test flight of this draft: %s" % stage)
	check(_posts(net) == 0, "starting the flight uploads nothing")
	_leave_scene()


func test_a_won_proof_flight_offers_publish_and_opens_the_confirmation_even_after_a_retry() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var stage := await _fly_proof(await _my_levels(), "Play to prove it")
	if stage == null:
		check(false, "the proof flight must open")
		return
	var first := stage.get_instance_id()
	stage.finish(false)
	await frames(2)
	_buttons(stage.hud, "Retry")[0].pressed.emit()
	await frames(2)
	var again := tree.current_scene as Level
	check(again != null and again.get_instance_id() != first and again.level_id == id and again.testing, "Retry must reopen this draft's test flight: %s" % again)
	if again == null or again.get_instance_id() == first:
		return
	again.finish(true)
	await frames(2)
	check(MyLevels.demo(id) != null and _posts(net) == 0, "the win keeps the run and sends nothing")
	check(_buttons(again.hud, "Publish").size() == 1, "a win must offer Publish")
	_buttons(again.hud, "Publish")[0].pressed.emit()
	await frames(3)
	var list := tree.current_scene
	check(list is MyLevelsScreen and _buttons(list, "Submit for review").size() == 1, "Publish must open the final confirmation in My levels: %s" % list)
	check(_posts(net) == 0, "the confirmation alone must send nothing")
	if not list is MyLevelsScreen:
		return
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 201, {"level_id": LEVEL_ID, "version": 1, "pull_request": 7})
	_suggest(list)
	_buttons(list, "Submit for review")[0].pressed.emit()
	await frames(3)
	check(net.count("POST", "/submissions") == 1 and MyLevels.is_submitted(id), "Submit for review must send the proven draft")
	_leave_scene()


func test_a_lost_proof_flight_offers_no_publish_and_sends_nothing() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var stage := await _fly_proof(await _my_levels(), "Play again")
	if stage == null:
		check(false, "the proof flight must open")
		return
	stage.finish(false)
	await frames(2)
	check(_buttons(stage.hud, "Publish").is_empty(), "a loss must not offer Publish")
	check(MyLevels.demo(id) != null, "a loss must not throw the earlier run away")
	stage.hud.menu_requested.emit()
	await frames(2)
	var list := tree.current_scene
	check(list is MyLevelsScreen and _sheets(list).is_empty(), "leaving a lost run returns to My levels with nothing open: %s" % list)
	check(_posts(net) == 0 and not MyLevels.is_submitted(id), "a lost run must upload nothing")
	_leave_scene()


func test_abandoning_a_proof_flight_or_leaving_after_a_win_confirms_and_sends_nothing() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var stage := await _fly_proof(await _my_levels(), "Play to prove it")
	if stage == null:
		check(false, "the proof flight must open")
		return
	stage.hud.menu_requested.emit()  # before the run ends
	await frames(2)
	var list := tree.current_scene
	check(list is MyLevelsScreen and _sheets(list).is_empty() and "Publish" in await _actions(list), "abandoning returns to My levels with nothing open: %s" % list)
	check(MyLevels.demo(id) == null and _posts(net) == 0, "an abandoned run keeps nothing and sends nothing")
	_leave_scene()
	stage = await _fly_proof(await _my_levels(), "Play to prove it")
	stage.finish(true)
	await frames(2)
	stage.hud.menu_requested.emit()  # the player won but did not press Publish
	await frames(3)
	list = tree.current_scene
	check(list is MyLevelsScreen and _sheets(list).is_empty(), "leaving a won run by Menu opens no confirmation: %s" % list)
	check(_posts(net) == 0 and not MyLevels.is_submitted(id), "nothing is sent without Submit for review")
	check("Publish" in await _actions(list) and MyLevels.demo(id) != null, "the proven run stays for the next Publish")
	_leave_scene()


func test_my_levels_maps_submission_statuses_to_row_text() -> void:
	var net := _fake()
	await _signed_in(net)
	var open := _finished_draft()
	var approved := _finished_draft()
	var rejected := _finished_draft()
	MyLevels.set_level_id(open, "lvl_aaaaaaaaaa")
	MyLevels.set_level_id(approved, "lvl_bbbbbbbbbb")
	MyLevels.set_level_id(rejected, "lvl_cccccccccc")
	for id in [open, approved, rejected]:
		MyLevels.set_submitted(id, LevelFormat.sha256(MyLevels.load_level(id)))
	net.answer("GET", "/me/submissions", 200, [
		{"level_id": "lvl_aaaaaaaaaa", "version": 1, "status": "open", "comment": null, "pull_request": 5, "title": "A"},
		{"level_id": "lvl_bbbbbbbbbb", "version": 2, "status": "approved", "comment": null, "pull_request": 6, "title": "B"},
		{"level_id": "lvl_cccccccccc", "version": 1, "status": "rejected", "comment": "Too easy.", "pull_request": 7, "title": "C"},
	])
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	var texts := _texts(screen)
	check("In review" in texts and "Published v2" in texts and "Rejected: Too easy." in texts, "status lines: %s" % [texts])
	for index in 3:
		check(not "Publish" in await _actions(screen, index), "unchanged in-review, published and rejected drafts must offer no repeat Publish")


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
	check("Published v3" in _texts(screen), "offline must show the last known status: %s" % [_texts(screen)])


func test_my_levels_shows_submitted_for_an_unchanged_draft_until_it_is_edited() -> void:
	_fake()
	var id := _finished_draft()
	MyLevels.set_submitted(id, LevelFormat.sha256(MyLevels.load_level(id)))
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check(not "Publish" in await _actions(screen) and _texts(screen).has("Submitted"), "an unchanged submitted draft shows Submitted and no Publish: %s" % [_texts(screen)])
	screen.free()
	var edited := MyLevels.load_level(id)
	edited.title = "Edited"
	MyLevels.save(id, edited)
	screen = MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	check("Publish" in await _actions(screen) and not _texts(screen).has("Submitted"), "an edited draft offers Publish again: %s" % [_texts(screen)])


func test_the_community_button_says_signing_in_and_is_off_while_it_waits() -> void:
	var net := _fake()
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	net.answer("GET", "/levels", 200, [])
	net.held = true
	var main := _menu()
	var button: Button = _buttons(main, "Community levels")[0]
	button.pressed.emit()
	check(button.text == "Signing in…" and button.disabled, "while it waits: %s, disabled %s" % [button.text, button.disabled])
	net.release()
	await frames(2)
	check(button.text == "Community levels" and not button.disabled, "afterwards the button is as before: %s" % button.text)
	check(tree.current_scene is CommunityScreen, "Community must open: %s" % tree.current_scene)
	_leave_scene()


func test_submit_for_review_says_submitting_and_is_off_while_it_waits_then_comes_back_after_a_refusal() -> void:
	var net := _fake()
	await _signed_in(net)
	_finished_draft()
	var screen := await _my_levels()
	await _confirmation(screen)
	net.answer("GET", "/nonce", 200, {"nonce": "n2"})
	net.answer("POST", "/submissions", 429, {"error": "At most 5 submissions are accepted per day."})
	net.held = true
	var submit: Button = _buttons(screen, "Submit for review")[0]
	_suggest(screen)
	submit.pressed.emit()
	check(submit.text == "Submitting…" and submit.disabled, "while it waits: %s, disabled %s" % [submit.text, submit.disabled])
	net.release()
	await frames(2)
	check(submit.text == "Submit for review" and not submit.disabled, "a refused submission gives the button back: %s" % submit.text)


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
