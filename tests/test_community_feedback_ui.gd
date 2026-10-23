extends "res://tests/test_case.gd"
## Task 8: the community sheet (voting, Reviewed and Community difficulty, sample counts), the catalogue's Details, the
## result card's Rate level, focus and Back, and the Publish suggestion. The real Community (history on disk, sync) runs
## against a fake server and a fake Play Games device (tests/support/fake_*.gd); nothing mocks the forwarding.
##
## The sheet, `scenes/community_level_details.gd`, is reached by path so this file compiles before it exists: a missing
## piece fails the check that names it. The contract the tests drive:
## - `CommunityLevelDetails.open(parent, row, on_play) -> Overlay`. Play: a Button "Play", present only with a callback.
## - Like: the sheet's one toggle Button. Pressed = you.liked. Disabled unless like_eligible or already liked.
## - Difficulty: the sheet's one OptionButton. Item 0 is the unselected placeholder (metadata ""); items 1-4 carry the
##   wire values easy, normal, hard, expert as metadata. Disabled unless difficulty_eligible.
## - Remove: a Button whose text contains "remove". Enabled while there is a vote; needs no eligibility.
## - Pending: a visible Label containing "pending" while a choice is queued. A refusal: its sentence in a visible Label.
## - Hud: `signal rate_requested`; a "Rate level" Button on the result card, visible only when result.can_rate.
## - Level: result.can_rate = Community.play_progress(sha).can_offer_rating on a community stage; Rate opens the sheet.
## - CommunityScreen: each row has a "Details" Button. MyLevelsScreen: Submit for review waits for a Suggested difficulty.

const SHEET := "res://scenes/community_level_details.gd"
const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"
const LEVEL_ID := "lvl_abcdefghij"
const SHA := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const FEEDBACK := "/levels/lvl_abcdefghij/feedback"
const LIKE := "/levels/lvl_abcdefghij/like"
const DIFFICULTY := "/levels/lvl_abcdefghij/difficulty"
const REFUSAL := "Ratings open after five counted tries on this version."
const DIFFICULTIES := ["easy", "normal", "hard", "expert"]
const SESSION := {"token": "tok1", "player": {"id": "p_1", "name": "Pilot"}}
const SESSION_TWO := {"token": "tok2", "player": {"id": "p_2", "name": "Scout"}}

var pilot := FakePlatform.new()
var _feedback_body := {}  # the answer to every feedback read, until a test changes it
var _put_status := 200  # the answer to a difficulty vote; 400 and up answer `_put_error`
var _put_error := ""
var _nonces := 0


# --- the fake server -------------------------------------------------------------------------------------------------


## Feedback reads and votes answer from the variables above; sign-ins answer from each test's queue.
func _fake() -> FakeTransport:
	var net := FakeTransport.new()
	world.add_child(net)  # freed with the world
	Community.transport = net
	Community.platform = pilot
	net.respond("GET", "/nonce", _nonce_reply)
	net.respond("GET", FEEDBACK, _feedback_reply)
	net.respond("POST", LIKE, _like_reply)
	net.respond("DELETE", LIKE, _unlike_reply)
	net.respond("PUT", DIFFICULTY, _vote_reply)
	net.respond("DELETE", DIFFICULTY, _remove_reply)
	return net


func _nonce_reply(_request: Dictionary) -> Dictionary:
	_nonces += 1
	return {"status": 200, "body": {"nonce": "n%d" % _nonces}}


func _feedback_reply(_request: Dictionary) -> Dictionary:
	return {"status": 200, "body": _feedback_body}


func _like_reply(_request: Dictionary) -> Dictionary:
	_record_you("liked", true)
	return {"status": 200, "body": {"likes": 8}}


func _unlike_reply(_request: Dictionary) -> Dictionary:
	_record_you("liked", false)
	return {"status": 200, "body": {"likes": 7}}


## The server's state after a like or an unlike, as the next feedback read reports it.
func _record_you(key: String, value: Variant) -> void:
	if _feedback_body.has("you"):
		_feedback_body["you"][key] = value


func _vote_reply(request: Dictionary) -> Dictionary:
	if _put_status >= 400:
		return {"status": _put_status, "body": {"error": _put_error}}
	var difficulty: Variant = _json(request.body).get("difficulty")
	_record_you("difficulty", difficulty)
	return {"status": 200, "body": {"difficulty": difficulty}}


func _remove_reply(_request: Dictionary) -> Dictionary:
	_record_you("difficulty", null)
	return {"status": 200, "body": {"difficulty": null}}


## Signs in as `session` with the sign-in's own answers, and forgets the requests that took.
func _signed_in(net: FakeTransport, session: Dictionary = SESSION) -> void:
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, session)
	var error: String = await Community.sign_in()
	check(error == "", "setup: sign-in failed: '%s'" % error)
	net.requests.clear()


## Answers every feedback read with `reply` from now on.
func _serve(reply: Dictionary) -> void:
	_feedback_body = reply


## The payload the server sends for one version. `you` and `stats` override the defaults; every field is present.
func _reply(you := {}, stats := {}, reviewed = null, community := {}, sha := SHA) -> Dictionary:
	var mine := {"liked": false, "like_eligible": false, "difficulty": null, "difficulty_eligible": false, "attempts": 0, "cleared": false}
	mine.merge(you, true)
	var labels := {"value": null, "votes": 0}
	labels.merge(community, true)
	return {"level_id": LEVEL_ID, "sha256": sha, "reviewed_difficulty": reviewed, "community_difficulty": labels, "stats": _stats(stats), "you": mine}


func _stats(overrides := {}) -> Dictionary:
	var stats := {"players_started": 0, "players_cleared": 0, "total_attempts": 0, "clear_rate": null, "attempts_per_first_clear": null, "median_tries": null, "unbeaten_5": 0, "unbeaten_10": 0, "unbeaten_20": 0}
	stats.merge(overrides, true)
	return stats


## A catalogue row (the list's own fields) for the version `SHA` unless overridden.
func _row(overrides := {}) -> Dictionary:
	var row := {"level_id": LEVEL_ID, "title": "Loop", "author": "Nova", "latest": 2, "sha256": SHA, "likes": 7, "players": 3, "reviewed_difficulty": null, "community_difficulty": {"value": null, "votes": 0}}
	row.merge(overrides, true)
	return row


func _level(overrides := {}) -> Dictionary:
	var data := {"format": LevelFormat.FORMAT, "version": LevelFormat.VERSION, "title": "Loop", "ship": {"position": [0, 0]}, "goal": {"position": [3000, 0]}}
	data.merge(overrides, true)
	return data


## Coroutine: downloads `data` as version `latest` through the fake CDN, as a list's Play does.
func _download(net: FakeTransport, data: Dictionary, latest := 1) -> Dictionary:
	var bytes := JSON.stringify(data).to_utf8_buffer()
	var row := _row({"sha256": CommunityWire.sha256_hex(bytes), "latest": latest})
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	var error: String = await Community.download(row)
	check(error == "" and LevelFormat.validate(LevelFormat.read(Community.level_path(row.sha256))).is_empty(), "setup: the level must download as a playable file: '%s'" % error)
	net.requests.clear()
	return row


func _stage(row: Dictionary) -> String:
	return Community.STAGE_PREFIX + row.sha256


# --- screens, sheets and levels ----------------------------------------------------------------------------------------


func _community() -> CommunityScreen:
	var screen := CommunityScreen.new()
	world.add_child(screen)
	await frames(2)
	return screen


func _my_levels() -> MyLevelsScreen:
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	return screen


## The shared sheet over `parent`, with its feedback loaded. Null after a failed check while the component is missing.
func _open(parent: Node, row: Dictionary, on_play: Callable) -> Overlay:
	var script: Variant = load(SHEET) if ResourceLoader.exists(SHEET) else null
	if script == null or not _declares(script, "open"):
		check(false, "missing %s: CommunityLevelDetails.open(parent, row, on_play)" % SHEET)
		return null
	var sheet: Overlay = script.open(parent, row, on_play)
	await frames(3)
	return sheet


## The sheet for an ended run or a test: over the test's world, without Play.
func _sheet(row: Dictionary) -> Overlay:
	return await _open(world, row, Callable())


func _declares(script: Variant, name: String) -> bool:
	return script.get_script_method_list().any(func(method: Dictionary) -> bool: return method.name == name)


## Coroutine: a community stage built as the game builds it, played and lost: the ship destroyed two live frames in.
## The level is returned, not freed.
func _lose(stage: String) -> Level:
	var lvl: Level = Progress.build(stage)
	world.add_child(lvl)
	await frames(2)
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	return lvl


## A level with a ship and a far goal: the Level's own result card and Rate wiring, not a stage.
func _plain_level() -> Level:
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	root.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(3000, 0)
	root.add_child(goal)
	world.add_child(root)
	return root as Level


## Publish, then Use previous run: the final confirmation, which only Submit for review leaves.
func _confirmation(screen: MyLevelsScreen) -> void:
	_buttons(screen, "Publish")[0].pressed.emit()
	await frames(1)
	_buttons(screen, "Use previous run")[0].pressed.emit()
	await frames(2)


## A draft with a winning run that matches it, as a won test flight leaves it. Returns its id.
func _finished_draft() -> String:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var run := Demo.new()
	run.add_frame({"position": Vector2(100, 100), "rotation": 0.0, "firing": false, "fuel": 10.0, "hull": 10.0}, {})
	run.level_sha256 = LevelFormat.sha256(MyLevels.load_level(id))
	MyLevels.save_demo(id, run)
	MyLevels.mark_completed(id)
	return id


func _leave_scene() -> void:
	if tree.current_scene:
		tree.current_scene.free()
		tree.current_scene = null


# --- reading and driving the screens -------------------------------------------------------------------------------------


func _sheets(node: Node) -> Array:
	return node.find_children("*", "Overlay", true, false)


func _buttons(node: Node, text: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())


## Visible buttons whose text contains `word`, ignoring case.
func _containing(node: Node, word: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.to_lower().contains(word) and b.is_visible_in_tree())


func _toggles(node: Node) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.toggle_mode and not (b is OptionButton))


func _options(node: Node) -> Array:
	return node.find_children("*", "OptionButton", true, false)


## The sheet's controls by role. A role the node does not show is null.
func _controls(node: Node) -> Dictionary:
	var toggles := _toggles(node)
	var options := _options(node)
	var removes := _containing(node, "remove")
	return {
		"like": toggles[0] if toggles.size() == 1 else null,
		"difficulty": options[0] if options.size() == 1 else null,
		"remove": removes[0] if removes.size() == 1 else null,
	}


func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.is_visible_in_tree()).map(func(l: Label) -> String: return l.text)


## Whether any of `texts` contains any of `words`, ignoring case.
func _mentions(texts: Array, words: Array) -> bool:
	for text: String in texts:
		for word: String in words:
			if text.to_lower().contains(word):
				return true
	return false


func _lines_with(texts: Array, word: String) -> Array:
	return texts.filter(func(t: String) -> bool: return t.to_lower().contains(word))


## A choice in a difficulty OptionButton, made as a player makes it: selected, then its selection signal.
func _pick(option: OptionButton, value: String) -> void:
	for i in option.item_count:
		if option.get_item_metadata(i) == value:
			option.select(i)
			option.item_selected.emit(i)
			return
	check(false, "the difficulty choice has no %s" % value)


## The wire value of the chosen difficulty; "" for the placeholder or no choice.
func _choice(option: OptionButton) -> String:
	var value: Variant = option.get_item_metadata(option.selected) if option.selected >= 0 else ""
	return value if value is String else ""


## One tap on a toggle: it flips as a press flips it, then the press itself is reported.
func _tap_toggle(button: Button) -> void:
	button.button_pressed = not button.button_pressed
	button.pressed.emit()


func _requests(net: FakeTransport, method: String, prefix: String) -> Array:
	return net.requests.filter(func(r: Dictionary) -> bool: return r.method == method and String(r.url).contains(prefix))


func _json(bytes: PackedByteArray) -> Dictionary:
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return data if data is Dictionary else {}


func _focus_in(node: Node) -> bool:
	var focus := tree.root.gui_get_focus_owner()
	return focus != null and node.is_ancestor_of(focus)


## Whether a sheet is gone: freed, or queued to be.
func _closed(sheet: Variant) -> bool:
	return not is_instance_valid(sheet) or sheet.is_queued_for_deletion()


func _send_action(action: StringName, pressed := true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap_action(action: StringName) -> void:
	_send_action(action, true)
	_send_action(action, false)


# --- the catalogue -----------------------------------------------------------------------------------------------------


func test_each_row_offers_details_and_both_difficulty_labels_but_no_vote_buttons() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row({"reviewed_difficulty": "expert", "community_difficulty": {"value": "hard", "votes": 6}})])
	var screen: CommunityScreen = await _community()
	check(_buttons(screen, "Details").size() == 1, "each row offers Details: %s" % [_texts(screen)])
	var vote_buttons := screen.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.to_lower() in DIFFICULTIES)
	check(vote_buttons.is_empty(), "the list must not show a row of difficulty buttons")
	var texts := _texts(screen)
	check(_mentions(texts, ["expert"]) and _mentions(texts, ["hard"]), "the list shows the Reviewed and the Community labels: %s" % [texts])
	check(_lines_with(texts, "6").size() > 0, "the list shows the community voter count: %s" % [texts])


func test_details_opens_one_sheet_and_back_returns_focus_to_its_row() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row()])
	var screen: CommunityScreen = await _community()
	_serve(_reply())
	var details := _buttons(screen, "Details")
	check(details.size() == 1, "each row offers Details: %s" % [_texts(screen)])
	if details.is_empty():
		return
	details[0].grab_focus()
	details[0].pressed.emit()
	await frames(3)
	var sheets := _sheets(screen)
	check(sheets.size() == 1, "Details opens one sheet: %d" % sheets.size())
	if sheets.size() != 1:
		return
	check(_buttons(sheets[0], "Play").size() == 1, "the catalogue's sheet offers Play")
	check(_focus_in(sheets[0]), "focus must move into the sheet, not %s" % [tree.root.gui_get_focus_owner()])
	_send_action(&"ui_cancel")
	await frames(2)
	check(_closed(sheets[0]) and _sheets(screen).is_empty(), "Back closes the sheet")
	check(screen.is_inside_tree(), "Back over a sheet must keep the catalogue open")
	check(tree.root.gui_get_focus_owner() == details[0], "focus returns to the row's Details")


func test_the_sheets_play_plays_the_stage_the_list_plays() -> void:
	var net := _fake()
	await _signed_in(net)
	var bytes := JSON.stringify(_level()).to_utf8_buffer()
	var sha := CommunityWire.sha256_hex(bytes)
	net.answer("GET", "/levels", 200, [_row({"sha256": sha})])
	var screen: CommunityScreen = await _community()
	_serve(_reply({}, {}, null, {}, sha))
	var details := _buttons(screen, "Details")
	if details.is_empty():
		check(false, "each row offers Details")
		return
	details[0].pressed.emit()
	await frames(3)
	var sheets := _sheets(screen)
	if sheets.size() != 1 or _buttons(sheets[0], "Play").size() != 1:
		check(false, "the sheet must offer Play: %d sheets" % sheets.size())
		return
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	_buttons(sheets[0], "Play")[0].pressed.emit()
	await frames(2)
	var stage: Variant = tree.current_scene
	check(stage is Level and stage.level_id == "community_" + sha, "Play must open the stage the list plays: %s" % [stage])
	_leave_scene()


# --- what the sheet shows -------------------------------------------------------------------------------------------------


func test_reviewed_and_community_difficulties_are_separate_values() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 12, "players_cleared": 3, "total_attempts": 30}, "expert", {"value": "hard", "votes": 6}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var lines := _texts(sheet)
	var reviewed := _lines_with(lines, "expert").filter(func(t: String) -> bool: return not t.to_lower().contains("hard"))
	var community := _lines_with(lines, "hard").filter(func(t: String) -> bool: return not t.to_lower().contains("expert"))
	check(not reviewed.is_empty() and not community.is_empty(), "Reviewed and Community show on their own lines, never one grade: %s" % [lines])


func test_four_voters_show_no_community_grade() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 4, "players_cleared": 1, "total_attempts": 9}, null, {"value": null, "votes": 4}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var lines := _texts(sheet)
	check(not _mentions(lines, DIFFICULTIES), "four voters show no grade: %s" % [lines])
	check(_mentions(lines, ["4"]), "the voter count shows: %s" % [lines])


func test_nine_starters_show_their_count_and_no_ratio() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 9, "players_cleared": 1, "total_attempts": 17}, null, {"value": null, "votes": 0}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var lines := _texts(sheet)
	check(_mentions(lines, ["9"]), "the starter count shows: %s" % [lines])
	check(not _mentions(lines, ["%", "null", "nan", "inf"]), "nine starters show no ratio and no null: %s" % [lines])


func test_ten_starters_without_a_clear_show_a_zero_rate_and_no_null() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 10, "players_cleared": 0, "total_attempts": 55, "clear_rate": 0}, null, {"value": null, "votes": 0}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	check(not _mentions(texts, ["null", "nan", "inf"]), "unset values show no null or nan: %s" % [texts])
	var zero := RegEx.create_from_string("(^|[^0-9.])0([^0-9.]|$)")
	check(texts.any(func(t: String) -> bool: return zero.search(t) != null), "no clears show a zero rate: %s" % [texts])


func test_ratios_and_the_finishers_median_are_shown_as_the_server_sends_them() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 10, "players_cleared": 4, "total_attempts": 16, "clear_rate": 0.4, "attempts_per_first_clear": 4, "median_tries": 2.5}, null, {"value": null, "votes": 0}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	check(_mentions(texts, ["40"]), "a clear rate of 0.4 shows as 40: %s" % [texts])
	check(_mentions(texts, ["2.5"]), "the finishers' median of 2.5 shows: %s" % [texts])


func test_only_this_players_selections_and_progress_are_shown() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"liked": true, "like_eligible": true, "difficulty": "hard", "difficulty_eligible": true, "attempts": 3}, {"players_started": 12}, "expert", {"value": "normal", "votes": 6}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(c.like.button_pressed, "your own Like shows as on")
	check(_choice(c.difficulty) == "hard", "your own vote shows, not the community's normal: '%s'" % _choice(c.difficulty))


# --- eligibility -----------------------------------------------------------------------------------------------------------


func test_four_counted_tries_leave_voting_unavailable() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"attempts": 4}, {"players_started": 12, "total_attempts": 40}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(c.like.disabled, "four tries: Like is unavailable")
	check(c.difficulty.disabled, "four tries: the difficulty is unavailable")
	check(c.remove == null or c.remove.disabled, "four tries: there is no vote to remove")


func test_a_fifth_counted_try_or_a_clear_makes_voting_available() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"attempts": 5, "like_eligible": true, "difficulty_eligible": true}))
	var fifth: Overlay = await _sheet(_row())
	if fifth == null:
		return
	var c := _controls(fifth)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(not c.like.disabled and not c.difficulty.disabled, "five counted tries open voting")
	fifth.close()
	await frames(2)
	_serve(_reply({"attempts": 1, "cleared": true, "like_eligible": true, "difficulty_eligible": true}))
	var cleared: Overlay = await _sheet(_row())
	if cleared == null:
		return
	c = _controls(cleared)
	if c.like == null or c.difficulty == null:
		check(false, "the cleared sheet needs one Like toggle and one difficulty choice")
		return
	check(not c.like.disabled and not c.difficulty.disabled, "a clear opens voting")


func test_stage_wide_likes_do_not_unlock_another_versions_difficulty() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"like_eligible": true, "difficulty_eligible": false, "attempts": 0}, {"players_started": 40, "players_cleared": 10, "total_attempts": 300}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(not c.like.disabled, "a like earned on the stage unlocks Like here")
	check(c.difficulty.disabled, "another version's experience must not unlock this version's difficulty")


func test_local_tries_alone_do_not_enable_a_vote_before_the_server_agrees() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	for i in 5:
		var lost: Level = await _lose(_stage(row))
		lost.free()
	_serve(_reply({"attempts": 0}, {}, null, {}, row.sha256))
	var sheet: Overlay = await _open(world, _row({"sha256": row.sha256}), Callable())
	if sheet == null:
		return
	var c := _controls(sheet)
	check(c.difficulty != null and c.difficulty.disabled, "five tries on this device are not the server's eligibility: the vote stays closed")
	check(net.count("PUT", DIFFICULTY) == 0 and net.count("POST", LIKE) == 0, "nothing is voted before the server agrees")


# --- Like and difficulty -----------------------------------------------------------------------------------------------------


func test_a_like_toggles_on_and_off_through_the_server() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"like_eligible": true}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var like: Button = _controls(sheet).like
	if like == null:
		check(false, "the sheet needs one Like toggle")
		return
	_tap_toggle(like)
	await frames(3)
	check(net.count("POST", LIKE) == 1 and like.button_pressed, "a like is sent once and stays on: POST %d" % net.count("POST", LIKE))
	_tap_toggle(like)
	await frames(3)
	check(net.count("DELETE", LIKE) == 1 and not like.button_pressed, "removing the like is sent once and clears it")


func test_removing_a_like_needs_no_new_play() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"liked": true, "like_eligible": false, "attempts": 1}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var like: Button = _controls(sheet).like
	if like == null:
		check(false, "the sheet needs one Like toggle")
		return
	check(not like.disabled, "a liked stage can always be unliked")
	_tap_toggle(like)
	await frames(3)
	check(net.count("DELETE", LIKE) == 1 and net.count("POST", LIKE) == 0 and not like.button_pressed, "the unlike is sent with no play")


func test_changing_a_difficulty_replaces_the_one_vote() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	_pick(option, "easy")
	await frames(2)
	_pick(option, "hard")
	await frames(3)
	var puts := _requests(net, "PUT", DIFFICULTY)
	check(puts.size() == 2, "each choice is one vote request: %d" % puts.size())
	check(not puts.is_empty() and _json(puts[-1].body) == {"sha256": SHA, "difficulty": "hard"}, "the last vote replaces the first: %s" % [puts])
	check(_choice(option) == "hard", "the choice stays hard: '%s'" % _choice(option))


func test_removing_a_difficulty_needs_no_eligibility() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty": "hard", "difficulty_eligible": false, "attempts": 1}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.difficulty == null or c.remove == null:
		check(false, "the sheet needs one difficulty choice and one Remove button")
		return
	check(c.difficulty.disabled, "without eligibility the difficulty stays closed")
	check(not c.remove.disabled, "the vote can be removed without a new play")
	c.remove.pressed.emit()
	await frames(3)
	check(net.count("DELETE", DIFFICULTY) == 1 and net.count("PUT", DIFFICULTY) == 0, "the removal is one DELETE")
	check(_choice(c.difficulty) == "", "the choice goes back to none: '%s'" % _choice(c.difficulty))


# --- pending, failure and staleness -------------------------------------------------------------------------------------------


func test_a_vote_still_syncing_stays_selected_and_says_pending() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	net.hold("PUT", DIFFICULTY)
	_pick(option, "hard")
	await frames(2)
	check(net.count("PUT", DIFFICULTY) == 1, "the vote goes out: %d" % net.count("PUT", DIFFICULTY))
	check(_choice(option) == "hard" and _mentions(_texts(sheet), ["pending"]), "a vote in flight stays selected and says pending: %s" % [_texts(sheet)])
	net.release_hold("PUT", DIFFICULTY)
	await frames(3)
	check(_choice(option) == "hard" and not _mentions(_texts(sheet), ["pending"]), "once accepted the choice stays and pending clears: %s" % [_texts(sheet)])


func test_a_failed_vote_stays_pending_for_a_later_sync() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	_put_status = 503
	_put_error = "The server is busy."
	_pick(option, "hard")
	await frames(3)
	check(_choice(option) == "hard" and _mentions(_texts(sheet), ["pending"]), "a server failure keeps the choice and says pending: %s" % [_texts(sheet)])


func test_a_refused_vote_restores_the_confirmed_choice_and_says_why() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty": "normal", "difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	_put_status = 422
	_put_error = REFUSAL
	_pick(option, "hard")
	await frames(3)
	check(_choice(option) == "normal", "the confirmed normal comes back: '%s'" % _choice(option))
	check(REFUSAL in _texts(sheet), "the server's sentence shows: %s" % [_texts(sheet)])
	check(not _mentions(_texts(sheet), ["pending"]), "a refused vote is no longer pending: %s" % [_texts(sheet)])


func test_an_older_answer_does_not_undo_a_newer_choice() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	net.hold("PUT", DIFFICULTY)
	_pick(option, "hard")
	await frames(2)
	_pick(option, "easy")
	await frames(2)
	net.release_hold("PUT", DIFFICULTY)
	await frames(4)
	var puts := _requests(net, "PUT", DIFFICULTY)
	check(_choice(option) == "easy", "an older answer must not restore hard: '%s'" % _choice(option))
	check(not puts.is_empty() and _json(puts[-1].body).get("difficulty") == "easy", "the newest choice is the one sent last: %d votes" % puts.size())
	check(not _mentions(_texts(sheet), ["pending"]), "nothing is left pending: %s" % [_texts(sheet)])


func test_closing_the_sheet_while_a_vote_is_out_touches_no_freed_control() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	net.hold("PUT", DIFFICULTY)
	_pick(option, "hard")
	await frames(2)
	check(net.count("PUT", DIFFICULTY) == 1, "the vote is out before the sheet closes")
	_buttons(sheet, "Close")[0].pressed.emit()
	await frames(2)
	net.release_hold("PUT", DIFFICULTY)
	await frames(4)
	check(_closed(sheet), "the sheet stays closed when the vote answers")


func test_another_account_never_sees_the_prior_owners_feedback() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"liked": true, "like_eligible": true, "difficulty": "hard", "difficulty_eligible": true, "attempts": 5}))
	var first: Overlay = await _sheet(_row())
	if first == null:
		return
	var first_controls := _controls(first)
	if first_controls.like == null or first_controls.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(first_controls.like.button_pressed and _choice(first_controls.difficulty) == "hard", "control: the first account sees its own vote")
	first.close()
	await frames(2)
	# The session ends and the device signs in as another Play Games account.
	var saved := ConfigFile.new()
	saved.load(Community.session_path)
	saved.erase_section("session")
	saved.save(Community.session_path)
	pilot.account = "p2"
	net.answer("GET", "/nonce", 200, {"nonce": "n3"})
	net.answer("POST", "/session", 200, SESSION_TWO)
	_serve(_reply({}, {"players_started": 12}))  # the second account has no like, vote or tries here
	net.hold("GET", FEEDBACK)
	var second: Overlay = await _sheet(_row())
	if second == null:
		return
	var c := _controls(second)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(_choice(c.difficulty) == "" and not c.like.button_pressed and not _mentions(_texts(second), ["hard"]), "while the answer is out, the first account's vote must not show: %s" % [_texts(second)])
	net.release_hold("GET", FEEDBACK)
	await frames(3)
	check(_choice(c.difficulty) == "" and not c.like.button_pressed, "the second account sees only its own feedback: %s" % [_texts(second)])


# --- the result card, focus and Back ---------------------------------------------------------------------------------------------


func test_rate_level_is_a_result_button_only_when_the_result_can_rate() -> void:
	var lvl := _plain_level()
	await frames(2)
	var hud: Variant = lvl.hud
	hud.show_result(false, {"name": "Loop", "cause": "Hull destroyed", "can_rate": true})
	var rate := _buttons(hud, "Rate level")
	check(rate.size() == 1, "a community result that can rate offers Rate level")
	if not hud.has_signal("rate_requested"):
		check(false, "the Hud needs `signal rate_requested`")
		return
	var asked := []
	hud.rate_requested.connect(func() -> void: asked.append(true))
	if rate.size() == 1:
		rate[0].pressed.emit()
	check(asked.size() == 1, "Rate level requests the sheet once: %d" % asked.size())
	hud.show_result(false, {"name": "Loop", "cause": "Hull destroyed"})
	check(_buttons(hud, "Rate level").is_empty() and _buttons(hud, "Retry").size() == 1, "without can_rate there is no Rate level, and Retry stays")


func test_a_sheet_opened_inside_the_result_focus_delay_keeps_focus() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var lvl := _plain_level()
	await frames(2)
	var hud: Variant = lvl.hud
	hud.show_result(false, {"name": "Loop", "cause": "Hull destroyed", "can_rate": true})
	var sheet: Overlay = await _open(lvl, _row(), Callable())
	if sheet == null:
		return
	check(_buttons(sheet, "Play").is_empty(), "an ended run's sheet has no Play")
	await frames(40)  # past the Hud's result focus delay: 0.4 s at 60 FPS
	check(_focus_in(sheet), "the result card must not take focus from a sheet opened within its delay: %s" % [tree.root.gui_get_focus_owner()])


func test_back_closes_the_sheet_before_a_finished_level_leaves() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var lvl := _plain_level()
	await frames(2)
	lvl.hud.show_result(false, {"name": "Loop", "cause": "Hull destroyed", "can_rate": true})
	var before := tree.current_scene
	var sheet: Overlay = await _open(lvl, _row(), Callable())
	if sheet == null:
		return
	lvl.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(_closed(sheet), "Back must close the sheet first")
	check(tree.current_scene == before, "Back over a sheet must not leave the finished level: %s" % [tree.current_scene])
	_leave_scene()


func test_keys_and_pad_cannot_move_focus_out_of_the_sheet() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row()])
	var screen: CommunityScreen = await _community()
	_serve(_reply({"like_eligible": true, "difficulty_eligible": true, "attempts": 5}))
	var details := _buttons(screen, "Details")
	if details.is_empty():
		check(false, "each row offers Details")
		return
	details[0].grab_focus()
	details[0].pressed.emit()
	await frames(3)
	var sheets := _sheets(screen)
	if sheets.size() != 1:
		check(false, "Details opens one sheet: %d" % sheets.size())
		return
	var sheet: Overlay = sheets[0]
	check(_focus_in(sheet), "control: focus starts inside the sheet")
	var escaped := ""
	for action in [&"ui_down", &"ui_down", &"ui_down", &"ui_down", &"ui_right", &"ui_up", &"ui_left", &"ui_down", &"ui_down", &"ui_down", &"ui_down", &"ui_down", &"ui_down"]:
		_tap_action(action)
		await frames(1)
		if escaped == "" and not _focus_in(sheet):
			escaped = String(action)
	check(escaped == "", "focus left the sheet on %s: %s" % [escaped, tree.root.gui_get_focus_owner()])


# --- results that can rate, and where they cannot -----------------------------------------------------------------------------------


func test_a_fifth_failed_result_offers_rate_and_a_fourth_does_not() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	for i in 3:
		var early: Level = await _lose(stage)
		early.free()
	var fourth: Level = await _lose(stage)
	check(_buttons(fourth.hud, "Rate level").is_empty(), "the fourth counted failure offers no rating")
	fourth.free()
	var fifth: Level = await _lose(stage)
	check(_buttons(fifth.hud, "Rate level").size() == 1, "the fifth counted failure offers Rate level")


func test_another_versions_tries_do_not_offer_rate_on_this_version() -> void:
	var net := _fake()
	await _signed_in(net)
	var first: Dictionary = await _download(net, _level({"title": "One"}), 1)
	var second: Dictionary = await _download(net, _level({"title": "Two"}), 2)
	for i in 5:
		var lost: Level = await _lose(_stage(first))
		lost.free()
	var fresh: Level = await _lose(_stage(second))
	check(_buttons(fresh.hud, "Rate level").is_empty(), "five tries on version 1 must not rate version 2")


func test_desktop_results_offer_no_rating_and_send_nothing() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	Community.platform = CommunityPlatform.new()  # this device has no Play Games
	net.requests.clear()
	var lvl: Level = await _lose(_stage(row))
	check(_buttons(lvl.hud, "Rate level").is_empty(), "desktop offers no rating")
	check(net.requests.is_empty(), "desktop must not reach the server: %s" % [net.requests])
	lvl.free()


# --- Publish ---------------------------------------------------------------------------------------------------------------------


func test_submit_for_review_needs_an_explicit_suggested_difficulty() -> void:
	var net := _fake()
	await _signed_in(net)
	_finished_draft()
	var screen: MyLevelsScreen = await _my_levels()
	await _confirmation(screen)
	var sheets := _sheets(screen)
	if sheets.size() != 1 or _buttons(screen, "Submit for review").size() != 1:
		check(false, "one confirmation with Submit for review: %s" % [sheets.map(_texts)])
		return
	var options := _options(sheets[0])
	check(options.size() == 1, "the confirmation asks for a Suggested difficulty")
	if options.size() != 1:
		return
	check(_buttons(screen, "Submit for review")[0].disabled, "Submit for review stays off until a difficulty is chosen")
	_pick(options[0], "hard")
	await frames(1)
	check(not _buttons(screen, "Submit for review")[0].disabled, "a chosen difficulty turns Submit on")
	check(net.count("POST", "/submissions") == 0, "choosing uploads nothing")
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(3)
	var posts := _requests(net, "POST", "/submissions")
	check(posts.size() == 1 and String(posts[0].body.get_string_from_utf8()).contains("hard"), "Submit sends the chosen difficulty once: %d" % posts.size())


func test_a_new_proof_run_uploads_only_after_submit_with_the_same_bytes() -> void:
	var net := _fake()
	await _signed_in(net)
	var id := _finished_draft()
	var level := LevelFormat.to_json(MyLevels.load_level(id)).to_utf8_buffer()
	var demo := FileAccess.get_file_as_bytes(MyLevels.demo_path(id))
	var screen := MyLevelsScreen.new()
	screen.confirm_publish_id = id  # what a won proof flight leaves behind
	world.add_child(screen)
	await frames(2)
	var sheets := _sheets(screen)
	if sheets.size() != 1 or _buttons(screen, "Submit for review").size() != 1:
		check(false, "a won proof flight opens one confirmation: %s" % [sheets.map(_texts)])
		return
	var options := _options(sheets[0])
	check(options.size() == 1, "the confirmation asks for a Suggested difficulty")
	if options.size() != 1:
		return
	check(net.count("POST", "/submissions") == 0 and not MyLevels.is_submitted(id), "the confirmation alone uploads nothing")
	_pick(options[0], "expert")
	await frames(1)
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(3)
	var posts := _requests(net, "POST", "/submissions")
	check(posts.size() == 1, "Submit uploads the proven draft once: %d" % posts.size())
	if posts.size() != 1:
		return
	var sent: PackedByteArray = posts[0].body
	check(sent.hex_encode().contains(level.hex_encode()) and sent.hex_encode().contains(demo.hex_encode()), "the level and its recording go up as they are")
	check(LevelFormat.to_json(MyLevels.load_level(id)).to_utf8_buffer().hex_encode() == level.hex_encode(), "the suggestion must not edit the draft")


## Coroutine: runs the clock fast for a few process frames, so the 30 s retry gap after a failed vote or upload has passed, then puts it back.
func _cooldown() -> void:
	Engine.time_scale = 100.0  # at 60 FPS a frame spans about 1.7 s: 24 frames pass the gap
	for _frame in 24:
		await tree.process_frame
	Engine.time_scale = 1.0


# --- follow-up: a background report, and a like that flushes a refused difficulty ------------------------------------


func test_a_background_report_that_earns_the_rating_enables_the_difficulty_without_reopening_the_sheet() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	_serve(_reply({"attempts": 4}, {"players_started": 4}, null, {}, row.sha256))
	for i in 5:  # five counted starts that this device has not sent yet
		check(Community.record_play_start(row.sha256) != "", "setup: start %d must be recorded" % (i + 1))
	var progress: Dictionary = Community.play_progress(row.sha256)
	check(int(progress.get("local_attempts", 0)) == 5 and progress.get("can_offer_rating") == true, "control: this device counts five tries and offers the rating locally: %s" % [progress])
	var sheet: Overlay = await _open(world, row, Callable())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.difficulty == null:
		check(false, "the sheet needs one difficulty choice")
		return
	var option: OptionButton = c.difficulty
	check(option.disabled, "control: the server counts four tries, so the choice stays closed")
	check(net.count("POST", "/plays") == 0, "control: nothing is sent before the community is entered")
	net.respond("POST", "/plays", func(request: Dictionary) -> Dictionary:
		var attempts: Array = _json(request.body).get("attempts", [])
		var acks := []
		for attempt: Dictionary in attempts:
			acks.append({"id": attempt.id, "revision": int(attempt.revision)})
		_serve(_reply({"attempts": 5, "like_eligible": true, "difficulty_eligible": true}, {"players_started": 5}, null, {}, row.sha256))
		return {"status": 200, "body": {"acknowledged": acks, "discarded": [], "cleared": []}})
	Community.activate_feedback()  # entering the community lets this device report by itself
	await frames(3)
	check(net.count("POST", "/plays") == 1, "the background flush sends the five starts in one report: %d" % net.count("POST", "/plays"))
	check(not _closed(sheet), "the same sheet is still open: nothing was closed or reopened")
	check(not option.disabled, "the server now counts five tries, so the choice must enable by itself, with no refresh and no reopening")


func test_a_like_that_flushes_a_refused_difficulty_keeps_the_liked_state_and_restores_the_confirmed_choice() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty": "normal", "like_eligible": true, "difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	var like: Button = c.like
	var option: OptionButton = c.difficulty
	check(_choice(option) == "normal" and not like.button_pressed, "control: the confirmed choice is normal and the stage is not liked")
	net.answer("PUT", DIFFICULTY, 0)  # offline: the choice is kept on the device
	_pick(option, "hard")
	await frames(3)
	check(Community.pending_feedback(LEVEL_ID, SHA).get("difficulty") == "hard" and _mentions(_texts(sheet), ["pending"]), "offline, the choice stays selected and queued: %s" % [_texts(sheet)])
	await _cooldown()  # the retry gap after the failed vote passes, as it would in real time
	_put_status = 403  # back online, the server refuses the difficulty ...
	_put_error = REFUSAL
	var puts := net.count("PUT", DIFFICULTY)
	var likes := net.count("POST", LIKE)
	_tap_toggle(like)  # ... and accepts the Like, in the same flush
	await frames(3)
	check(net.count("PUT", DIFFICULTY) - puts == 1 and net.count("POST", LIKE) - likes == 1, "one flush sends the queued difficulty once and the Like once: PUT %d, POST like %d" % [net.count("PUT", DIFFICULTY) - puts, net.count("POST", LIKE) - likes])
	check(like.button_pressed, "the Like the server accepted stays on, whatever the refused vote said")
	check(_choice(option) == "normal", "the refused difficulty returns to the confirmed normal: '%s'" % _choice(option))
	check(REFUSAL in _texts(sheet), "the server's refusal shows: %s" % [_texts(sheet)])
	check(not _mentions(_texts(sheet), ["pending"]), "nothing is left pending: %s" % [_texts(sheet)])
	check(Community.pending_feedback(LEVEL_ID, SHA).is_empty(), "nothing stays queued: %s" % [Community.pending_feedback(LEVEL_ID, SHA)])


# --- follow-up 2: an explicit Refresh adopts a selection another device changed after our vote settled ---------------


func test_an_explicit_refresh_adopts_a_server_selection_another_device_changed_after_our_own_vote_settled() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: OptionButton = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	# Recover an offline read through the sheet's existing Refresh action, without adding a new UI feature.
	net.answer("GET", FEEDBACK, 0)
	_pick(option, "hard")
	await frames(3)
	check(net.count("PUT", DIFFICULTY) == 1, "control: our vote goes out once: %d" % net.count("PUT", DIFFICULTY))
	check(_feedback_body.get("you", {}).get("difficulty") == "hard", "control: the server now holds our hard vote: %s" % [_feedback_body])
	check(_choice(option) == "hard" and Community.pending_feedback(LEVEL_ID, SHA).is_empty() and not _mentions(_texts(sheet), ["pending"]), "control: our vote is confirmed and nothing is pending: '%s' %s" % [_choice(option), _texts(sheet)])
	var refresh := _containing(sheet, "refresh")
	if refresh.size() != 1:
		check(false, "the sheet needs one Refresh button: %s" % [_texts(sheet)])
		return
	# Another device changes this vote on the server; the fake's persistent payload is the server's state.
	_feedback_body["you"]["difficulty"] = "easy"
	net.requests.clear()
	refresh[0].pressed.emit()
	await frames(3)
	check(net.count("GET", FEEDBACK) >= 1, "Refresh must read the server again: %d" % net.count("GET", FEEDBACK))
	check(_choice(option) == "easy", "Refresh must adopt the server's selection, not keep our settled hard: '%s'" % _choice(option))
	check(not _mentions(_texts(sheet), ["pending"]) and Community.pending_feedback(LEVEL_ID, SHA).is_empty(), "nothing is pending after the refresh: %s" % [_texts(sheet)])
