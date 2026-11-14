extends "res://tests/test_case.gd"
## Task 8: the community sheet (voting, Reviewed and Community difficulty, sample counts), the catalogue's Details, the
## result card's Rate level, focus and Back, and the Publish suggestion. The real Community (history on disk, sync) runs
## against a fake server and a fake Play Games device (tests/support/fake_*.gd); nothing mocks the forwarding.
##
## The sheet, `scenes/community_level_details.gd`, is reached by path so this file compiles before it exists: a missing
## piece fails the check that names it. The contract the tests drive:
## - `CommunityLevelDetails.open(parent, row, on_play) -> Overlay`. Play: a Button "Play", present only with a callback.
## - Like: the sheet's one toggle Button. Pressed = you.liked. Disabled unless like_eligible or already liked.
## - Difficulty: four toggle Buttons (Easy, Normal, Hard, Expert), shown only while the player may vote (or already holds a
##   vote). Pressing the selected one removes the vote; there is no Remove button and no dropdown on this sheet.
## - Hero, Rated sentence, vote bars, curve, You: see the details-sheet tests below.
## - Pending: a visible Label containing "pending" while a choice is queued. A refusal: its sentence in a visible Label.
## - Hud: `signal rate_requested`; a "Rate level" Button on the result card, visible only when result.can_rate.
## - Level: result.can_rate = Community.play_progress(sha).can_offer_rating on a community stage; Rate opens the sheet.
## - CommunityScreen: each row is a button that opens Details. MyLevelsScreen: Submit for review waits for a Suggested difficulty.

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
func _reply(you := {}, stats := {}, reviewed = null, community := {}, sha := SHA, extra := {}) -> Dictionary:
	var mine := {"liked": false, "like_eligible": false, "difficulty": null, "difficulty_eligible": false, "attempts": 0, "cleared": false}
	mine.merge(you, true)
	var labels := {"value": null, "votes": 0}
	labels.merge(community, true)
	var reply := {"level_id": LEVEL_ID, "sha256": sha, "reviewed_difficulty": reviewed, "community_difficulty": labels, "stats": _stats(stats), "you": mine}
	reply.merge(extra, true)
	return reply


## The extra feedback fields of a well-played version: Rated Normal–Hard at 35–55%, a curve, four vote counts, 64 starters.
func _rich(overrides := {}) -> Dictionary:
	var curve := []
	for i in 30:
		curve.append(0.01 * (i + 5))
	var extra := {"rated": "normal", "rated_high": "hard", "p10_low": 0.35, "p10_high": 0.55, "curve": curve, "not_cleared_20": 9, "audience": null, "starters": 64, "clears": 22, "votes": {"easy": 3, "normal": 5, "hard": 11, "expert": 2}}
	extra.merge(overrides, true)
	return extra


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
func _open(parent: Node, row: Dictionary, on_play: Callable, to_you := false) -> Overlay:
	var script: Variant = load(SHEET) if ResourceLoader.exists(SHEET) else null
	if script == null or not _declares(script, "open"):
		check(false, "missing %s: CommunityLevelDetails.open(parent, row, on_play)" % SHEET)
		return null
	var sheet: Overlay = script.open(parent, row, on_play, to_you)
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
	screen._list.get_child(0).pressed.emit()
	await frames(2)
	_buttons(screen, "Publish")[0].pressed.emit()
	await frames(2)
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


## The sheet's controls by role: the Like toggle, and the four vote toggles by wire value (hidden until the player may vote).
func _controls(node: Node) -> Dictionary:
	var toggles: Array = node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.toggle_mode and not (b is OptionButton))
	var like := toggles.filter(func(b: Button) -> bool: return b.text.contains("Like"))
	var votes := {}
	for b: Button in toggles:
		if b.text.to_lower() in DIFFICULTIES:
			votes[b.text.to_lower()] = b
	return {"like": like[0] if like.size() == 1 else null, "difficulty": votes}


func _options(node: Node) -> Array:
	return node.find_children("*", "OptionButton", true, false)


## Whether every vote toggle can be pressed.
func _vote_open(votes: Dictionary) -> bool:
	return votes.size() == 4 and votes.values().all(func(b: Button) -> bool: return b.is_visible_in_tree() and not b.disabled)


## Whether no vote toggle can be pressed (hidden or disabled).
func _vote_closed(votes: Dictionary) -> bool:
	return votes.values().all(func(b: Button) -> bool: return not b.is_visible_in_tree() or b.disabled)


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


## A choice in a difficulty control, made as a player makes it: a vote toggle is pressed; a dropdown selects, then signals.
func _pick(control: Variant, value: String) -> void:
	if control is Dictionary:
		control[value].pressed.emit()
		return
	var option: OptionButton = control
	for i in option.item_count:
		if option.get_item_metadata(i) == value:
			option.select(i)
			option.item_selected.emit(i)
			return
	check(false, "the difficulty choice has no %s" % value)


## The wire value of the chosen difficulty; "" for none.
func _choice(control: Variant) -> String:
	if control is Dictionary:
		for value: String in control:
			if control[value].button_pressed:
				return value
		return ""
	var option: OptionButton = control
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


func test_each_row_opens_details_and_shows_one_difficulty_label_but_no_vote_buttons_or_counts() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row({"reviewed_difficulty": "expert", "community_difficulty": {"value": "hard", "votes": 6}})])
	var screen: CommunityScreen = await _community()
	check(screen.find_children("Row", "Button", true, false).size() == 1, "each row is a button that opens Details: %s" % [_texts(screen)])
	var vote_buttons := screen._rows.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.to_lower() in DIFFICULTIES)
	check(vote_buttons.is_empty(), "the rows must not show a row of difficulty buttons")
	var texts := _texts(screen)
	check("Reviewed Expert" in texts and not _mentions(texts, ["voted", "votes"]), "the list shows the one chip with its source and no vote count: %s" % [texts])


func test_details_opens_one_sheet_and_back_returns_focus_to_its_row() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", "/levels", 200, [_row()])
	var screen: CommunityScreen = await _community()
	_serve(_reply())
	var details := screen.find_children("Row", "Button", true, false)
	check(details.size() == 1, "each row opens Details: %s" % [_texts(screen)])
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
	var details := screen.find_children("Row", "Button", true, false)
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


func test_hero_shows_thumbnail_byline_with_version_chip_and_play() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64, "players_cleared": 22}, null, {}, SHA, _rich()))
	var sheet: Overlay = await _open(world, _row({"likes": 42}), func() -> void: pass)
	if sheet == null:
		return
	var texts := _texts(sheet)
	check(not sheet.find_children("*", "Thumbnail", true, false).is_empty(), "the hero shows the thumbnail")
	check("by Nova · version 2" in texts, "the byline names the author and the version: %s" % [texts])
	check(sheet.find_children("*", "DifficultyChip", true, false).size() >= 1 and "Rated Normal–Hard" in texts, "the chip shows with its source: %s" % [texts])
	check("♥ 42 · 64 players" in texts, "likes and players: %s" % [texts])
	check(_buttons(sheet, "Play").size() == 1, "Play is in the hero")


func test_the_rated_sentence_shows_the_p10_interval() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64}, null, {}, SHA, _rich()))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	check("A typical player clears it within 10 tries 35–55% of the time" in texts, "the sentence shows the interval with an en dash: %s" % [texts])
	check(not _mentions(texts, ["settles"]), "a fresh label adds no settling note: %s" % [texts])


func test_a_held_label_says_the_estimate_is_settling() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64}, null, {}, SHA, _rich({"rated": "hard", "rated_high": "hard", "p10_low": 0.3, "p10_high": 0.52})))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	check("A typical player clears it within 10 tries 30–52% of the time (the label updates once the estimate settles)" in texts, "an interval reaching past the band says so: %s" % [texts])


func test_estimating_shows_the_starter_count_below_the_gates() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 4}, null, {}, SHA, {"rated": null, "starters": 4}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	check("Estimating · 4 players" in texts, "below the gates: %s" % [texts])
	check(not _mentions(texts, ["a typical player"]), "no Rated sentence while estimating: %s" % [texts])


func test_the_sheet_says_when_rated_and_reviewed_differ_by_two_steps() -> void:
	var net := _fake()
	await _signed_in(net)
	var cases := [
		["hard", "hard", "easy", "Players find it harder than the moderator rated it"],
		["easy", "easy", "hard", "Players find it easier than the moderator rated it"],
		["easy", "normal", "expert", "Players find it easier than the moderator rated it"],
		["hard", "hard", "normal", ""],
		["normal", "hard", "expert", ""],
	]
	for c: Array in cases:
		_serve(_reply({}, {"players_started": 64}, c[2], {}, SHA, _rich({"rated": c[0], "rated_high": c[1]})))
		var sheet: Overlay = await _sheet(_row())
		if sheet == null:
			return
		var lines := _lines_with(_texts(sheet), "than the moderator")
		check(lines == ([c[3]] if c[3] != "" else []), "rated %s–%s, reviewed %s: %s" % [c[0], c[1], c[2], lines])
		sheet.close()
		await frames(2)


func test_the_vote_distribution_shows_four_counts_and_the_total() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64}, null, {"value": "hard", "votes": 21}, SHA, _rich()))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	for pair: Array in [["Easy", "3"], ["Normal", "5"], ["Hard", "11"], ["Expert", "2"]]:
		check(pair[0] in texts and pair[1] in texts, "%s and its count %s show: %s" % [pair[0], pair[1], texts])
	check("21 voters · Voted Hard" in texts, "the total and the upper median show at 5 or more voters: %s" % [texts])


func test_four_voters_show_their_count_and_no_voted_label() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 4}, null, {"value": null, "votes": 4}, SHA, {"starters": 4, "votes": {"easy": 1, "normal": 2, "hard": 1, "expert": 0}}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var texts := _texts(sheet)
	check("4 voters" in texts and not _mentions(texts, ["voted"]), "four voters show no label: %s" % [texts])


func test_the_vote_buttons_appear_only_when_eligible_and_the_selected_one_removes_the_vote() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"attempts": 3}, {"players_started": 64}, null, {}, SHA, _rich()))
	var closed: Overlay = await _sheet(_row())
	if closed == null:
		return
	var c := _controls(closed)
	check(c.difficulty.size() == 4 and _vote_closed(c.difficulty), "before eligibility there are no vote buttons")
	check(_mentions(_texts(closed), ["clear it or try 2 more times to vote"]), "one progress line takes their place: %s" % [_texts(closed)])
	closed.close()
	await frames(2)
	_serve(_reply({"attempts": 5, "difficulty_eligible": true, "difficulty": "hard"}, {"players_started": 64}, null, {}, SHA, _rich()))
	var open: Overlay = await _sheet(_row())
	if open == null:
		return
	c = _controls(open)
	check(_vote_open(c.difficulty) and _choice(c.difficulty) == "hard", "eligible: four buttons, the vote selected")
	check(not _mentions(_texts(open), ["to vote"]), "no progress line once eligible: %s" % [_texts(open)])
	_pick(c.difficulty, "hard")
	await frames(3)
	check(net.count("DELETE", DIFFICULTY) == 1 and net.count("PUT", DIFFICULTY) == 0, "tapping the selected vote removes it")
	check(_choice(c.difficulty) == "", "no vote is selected after removing it")


func test_like_keeps_its_own_progress_line() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"like_eligible": false, "attempts": 0}, {"players_started": 64}, null, {}, SHA, _rich()))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	check(_lines_with(_texts(sheet), "likes open").size() == 1 and _lines_with(_texts(sheet), "to vote").size() == 1, "each locked control has its own line: %s" % [_texts(sheet)])
	sheet.close()
	await frames(2)
	_serve(_reply({"like_eligible": true, "attempts": 3}, {"players_started": 64}, null, {}, SHA, _rich()))  # earlier versions unlocked Like only
	var liked: Overlay = await _sheet(_row())
	if liked == null:
		return
	check(_lines_with(_texts(liked), "likes open").is_empty() and _lines_with(_texts(liked), "to vote").size() == 1, "an unlocked Like loses its line while the vote keeps its own: %s" % [_texts(liked)])


func test_the_curve_and_the_cleared_percentage_need_ten_starters() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 9, "players_cleared": 1, "clear_rate": null}, null, {}, SHA, _rich({"starters": 9, "clears": 1, "curve": null})))
	var few: Overlay = await _sheet(_row())
	if few == null:
		return
	var texts := _texts(few)
	check(few.find_children("*", "ClearCurve", true, false).is_empty(), "nine starters draw no curve")
	check("Players: 9" in texts and "Cleared: 1" in texts and _lines_with(texts, "cleared:").all(func(t: String) -> bool: return not t.contains("%")), "the counts show without a percentage: %s" % [texts])
	few.close()
	await frames(2)
	_serve(_reply({}, {"players_started": 10, "players_cleared": 4, "clear_rate": 0.4}, null, {}, SHA, _rich({"starters": 10, "clears": 4})))
	var ten: Overlay = await _sheet(_row())
	if ten == null:
		return
	texts = _texts(ten)
	check(ten.find_children("*", "ClearCurve", true, false).size() == 1, "ten starters draw the curve")
	check("Cleared: 4 (40%)" in texts, "the percentage shows at ten: %s" % [texts])
	check(not _mentions(texts, ["attempts per", "median", "unbeaten", "total attempts"]), "the removed statistics stay removed: %s" % [texts])


func test_not_cleared_names_those_who_tried_twenty_times() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64, "players_cleared": 22, "clear_rate": 0.34}, null, {}, SHA, _rich()))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	check("42 not cleared, 9 of them after 20+ tries" in _texts(sheet), "not cleared: %s" % [_texts(sheet)])


func test_the_counts_and_the_curve_come_from_one_source() -> void:
	var net := _fake()
	await _signed_in(net)
	# The cron's row is behind the live stats: 64 starters and 22 clears against 70 and 30 now.
	_serve(_reply({}, {"players_started": 70, "players_cleared": 30, "unbeaten_20": 15, "clear_rate": 0.43}, null, {}, SHA, _rich()))
	var behind: Overlay = await _sheet(_row())
	if behind == null:
		return
	var texts := _texts(behind)
	check("Players: 64" in texts and "Cleared: 22 (34%)" in texts and "42 not cleared, 9 of them after 20+ tries" in texts, "the three numbers come from the row the curve comes from: %s" % [texts])
	check(not _mentions(texts, ["after more than 30"]), "a clear the cron has not counted yet is no late clear: %s" % [texts])
	behind.close()
	await frames(2)
	# A new version has no row yet: the live counts, and no curve or late-clear caption.
	_serve(_reply({}, {"players_started": 3, "players_cleared": 1, "unbeaten_20": 1}, null, {}, SHA, {"starters": null, "clears": null, "curve": null, "not_cleared_20": 0}))
	var fresh: Overlay = await _sheet(_row())
	if fresh == null:
		return
	texts = _texts(fresh)
	check("Players: 3" in texts and "Cleared: 1" in texts and "2 not cleared, 1 of them after 20+ tries" in texts and "Estimating · 3 players" in texts, "without a row the live stats show: %s" % [texts])
	check(fresh.find_children("*", "ClearCurve", true, false).is_empty() and not _mentions(texts, ["after more than 30"]), "and no curve: %s" % [texts])


func test_the_curve_caption_counts_clears_after_thirty_tries() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64, "players_cleared": 22, "clear_rate": 0.34}, null, {}, SHA, _rich()))
	var plain: Overlay = await _sheet(_row())
	if plain == null:
		return
	check(not _mentions(_texts(plain), ["after more than 30"]), "no caption when the curve reaches the clears: %s" % [_texts(plain)])
	plain.close()
	await frames(2)
	_serve(_reply({}, {"players_started": 64, "players_cleared": 30, "clear_rate": 0.47}, null, {}, SHA, _rich({"clears": 30})))
	var late: Overlay = await _sheet(_row())
	if late == null:
		return
	check("8 cleared after more than 30 tries" in _texts(late), "the caption names the late clears: %s" % [_texts(late)])


func test_the_audience_line_needs_a_difference_of_half_a_point() -> void:
	var net := _fake()
	await _signed_in(net)
	var cases := [[0.5, "Players so far were stronger than typical"], [-0.7, "Players so far were weaker than typical"], [0.49, ""], [null, ""]]
	for c: Array in cases:
		_serve(_reply({}, {"players_started": 64}, null, {}, SHA, _rich({"audience": c[0]})))
		var sheet: Overlay = await _sheet(_row())
		if sheet == null:
			return
		var lines := _lines_with(_texts(sheet), "than typical")
		check(lines == ([c[1]] if c[1] != "" else []), "audience %s: %s" % [c[0], lines])
		sheet.close()
		await frames(2)


func test_the_sheet_ends_its_difficulty_section_with_the_known_limits() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({}, {"players_started": 64}, null, {}, SHA, _rich()))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	check(_mentions(_texts(sheet), ["android play audience, not desktop players", "previous version's label is not carried over"]), "the help text states the limits once: %s" % [_texts(sheet)])


func test_the_sheet_has_an_opaque_backdrop() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply())
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	check((sheet.get_child(0) as ColorRect).color.a == 1.0, "the list must not show through the details sheet")
	var other := Overlay.open(world, "Other")
	check((other.get_child(0) as ColorRect).color.a < 1.0, "other overlays keep their translucent backdrop")


func test_rate_level_opens_scrolled_to_you() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"attempts": 5, "difficulty_eligible": true, "like_eligible": true}, {"players_started": 64, "players_cleared": 22, "clear_rate": 0.34}, "hard", {"value": "hard", "votes": 21}, SHA, _rich()))
	var top: Overlay = await _sheet(_row())
	if top == null:
		return
	check(top.scroll.scroll_vertical == 0, "the catalogue's sheet opens at the top")
	top.close()
	await frames(2)
	var sheet: Overlay = await _open(world, _row(), Callable(), true)
	if sheet == null:
		return
	await frames(4)
	var heading: Label = sheet.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "You")[0]
	check(sheet.scroll.scroll_vertical > 0, "the sheet scrolled down")
	check(sheet.scroll.get_global_rect().encloses(heading.get_global_rect()), "the You heading is in view: %s in %s" % [heading.get_global_rect(), sheet.scroll.get_global_rect()])


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
	check(_vote_closed(c.difficulty), "four tries: the difficulty is unavailable")


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
	check(not c.like.disabled and _vote_open(c.difficulty), "five counted tries open voting")
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
	check(not c.like.disabled and _vote_open(c.difficulty), "a clear opens voting")


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
	check(_vote_closed(c.difficulty), "another version's experience must not unlock this version's difficulty")


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
	check(_vote_closed(c.difficulty), "five tries on this device are not the server's eligibility: the vote stays closed")
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
	var option: Variant = _controls(sheet).difficulty
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
	check(_choice(c.difficulty) == "hard" and c.difficulty.hard.is_visible_in_tree() and not c.difficulty.hard.disabled, "the held vote shows and can be pressed")
	check(c.difficulty.easy.disabled, "without eligibility no other vote can be chosen")
	_pick(c.difficulty, "hard")
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
	var option: Variant = _controls(sheet).difficulty
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
	var option: Variant = _controls(sheet).difficulty
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
	var option: Variant = _controls(sheet).difficulty
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
	var option: Variant = _controls(sheet).difficulty
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
	var option: Variant = _controls(sheet).difficulty
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
	var details := screen.find_children("Row", "Button", true, false)
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
	check(_choice(options[0]) == "", "A new publish confirmation must not preselect a difficulty: '%s'" % _choice(options[0]))
	check(_buttons(screen, "Submit for review")[0].disabled, "Submit for review stays off until a difficulty is chosen")
	_pick(options[0], "hard")
	await frames(1)
	check(not _buttons(screen, "Submit for review")[0].disabled, "a chosen difficulty turns Submit on")
	check(net.count("POST", "/submissions") == 0, "choosing uploads nothing")
	_buttons(screen, "Submit for review")[0].pressed.emit()
	await frames(3)
	var posts := _requests(net, "POST", "/submissions")
	check(posts.size() == 1 and posts[0].body.get_string_from_ascii().contains("hard"), "Submit sends the chosen difficulty once: %d" % posts.size())


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
	var option: Variant = c.difficulty
	check(_vote_closed(option), "control: the server counts four tries, so the choice stays closed")
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
	check(_vote_open(option), "the server now counts five tries, so the choice must enable by itself, with no refresh and no reopening")


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
	var option: Variant = c.difficulty
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
	var option: Variant = _controls(sheet).difficulty
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


# --- review: ownership of a held read, the newest choice's durability, and same-value acknowledgments --------------------


func test_a_read_held_across_a_sign_in_is_never_shown_as_the_new_accounts_and_the_new_account_is_read() -> void:
	var net := _fake()
	await _signed_in(net)
	net.answer("GET", FEEDBACK, 200, _reply({"liked": true, "like_eligible": true, "difficulty": "hard", "difficulty_eligible": true, "attempts": 5}))  # the first account's answer, fixed before the hold
	net.hold("GET", FEEDBACK)
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(net.count("GET", FEEDBACK) == 1, "setup: the first account's read is held: %d" % net.count("GET", FEEDBACK))
	pilot.account = "p2"
	await _signed_in(net, SESSION_TWO)  # the same open sheet is now another account's
	_serve(_reply({}, {"players_started": 12}))  # what the second account has: no like, no vote
	net.hold("GET", FEEDBACK)  # the second account's read is held too, so nothing but the first answer can be on screen
	net.release_hold("GET", FEEDBACK)
	await frames(3)
	var texts := _texts(sheet)
	check(not c.like.button_pressed and _choice(c.difficulty) == "" and not _mentions(texts, ["hard"]), "the first account's Like and vote must not show as the second account's: liked %s, '%s' %s" % [c.like.button_pressed, _choice(c.difficulty), texts])
	check(net.count("GET", FEEDBACK) == 1, "the sheet reads again for the signed-in account (the sign-in cleared the log of the held read): %d" % net.count("GET", FEEDBACK))
	net.release_hold("GET", FEEDBACK)
	await frames(3)
	check(not c.like.button_pressed and _choice(c.difficulty) == "" and _mentions(_texts(sheet), ["12"]), "the second account's own answer shows: liked %s, '%s' %s" % [c.like.button_pressed, _choice(c.difficulty), _texts(sheet)])


func test_a_newer_choice_made_while_an_older_request_is_out_survives_closing_and_applies_later() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: Variant = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	net.hold("PUT", DIFFICULTY)
	_pick(option, "hard")
	await frames(2)
	check(net.count("PUT", DIFFICULTY) == 1, "setup: the first vote is out: %d" % net.count("PUT", DIFFICULTY))
	_pick(option, "easy")
	await frames(2)
	check(Community.pending_feedback(LEVEL_ID, SHA).get("difficulty") == "easy", "the newest choice is durable in Community's queue as soon as it is made, not kept by the sheet: %s" % [Community.pending_feedback(LEVEL_ID, SHA)])
	_buttons(sheet, "Close")[0].pressed.emit()
	await frames(2)
	net.release_hold("PUT", DIFFICULTY)
	await frames(4)
	check(_closed(sheet), "setup: the sheet stays closed when the older vote answers")
	check(Community.pending_feedback(LEVEL_ID, SHA).get("difficulty") == "easy", "the older answer leaves the newer choice queued: %s" % [Community.pending_feedback(LEVEL_ID, SHA)])
	var again: Overlay = await _sheet(_row())
	if again == null:
		return
	var reopened: Variant = _controls(again).difficulty
	if reopened == null:
		check(false, "the reopened sheet needs one difficulty choice")
		return
	check(_choice(reopened) == "easy" and _mentions(_texts(again), ["pending"]), "reopened, the last choice shows as easy and pending: '%s' %s" % [_choice(reopened), _texts(again)])
	await _cooldown()  # the retry gap after the older vote passes
	var refresh := _containing(again, "refresh")
	if refresh.size() != 1:
		check(false, "the reopened sheet needs one Refresh button: %s" % [_texts(again)])
		return
	refresh[0].pressed.emit()
	await frames(4)
	var puts := _requests(net, "PUT", DIFFICULTY)
	check(puts.size() == 2 and _json(puts[-1].body).get("difficulty") == "easy", "the newest choice is sent after the older one: %d votes" % puts.size())
	check(_choice(reopened) == "easy" and not _mentions(_texts(again), ["pending"]) and Community.pending_feedback(LEVEL_ID, SHA).is_empty(), "the newest choice ends up applied and nothing is pending: '%s' %s" % [_choice(reopened), _texts(again)])


func test_an_older_same_value_acknowledgment_leaves_a_newer_queued_revision_pending() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	net.hold("PUT", DIFFICULTY)
	var background := func() -> void: await Community.set_difficulty(LEVEL_ID, SHA, "hard")  # an earlier flush, not this sheet's
	background.call()
	await frames(3)
	check(net.count("PUT", DIFFICULTY) == 1, "setup: the earlier hard vote is out: %d" % net.count("PUT", DIFFICULTY))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var option: Variant = _controls(sheet).difficulty
	if option == null:
		check(false, "the sheet needs one difficulty choice")
		return
	_pick(option, "easy")
	await frames(2)
	_pick(option, "hard")  # a newer hard, queued behind the one that is out
	await frames(2)
	check(net.count("PUT", DIFFICULTY) == 1 and Community.pending_feedback(LEVEL_ID, SHA).get("difficulty") == "hard", "setup: the newer hard is queued behind the one in flight: %s" % [Community.pending_feedback(LEVEL_ID, SHA)])
	net.hold("GET", FEEDBACK)  # the read that follows the old acknowledgment stays out
	net.release_hold("PUT", DIFFICULTY)
	await frames(3)
	check(Community.pending_feedback(LEVEL_ID, SHA).get("difficulty") == "hard", "the old acknowledgment leaves the newer hard queued: %s" % [Community.pending_feedback(LEVEL_ID, SHA)])
	check(_choice(option) == "hard" and _mentions(_texts(sheet), ["pending"]), "the sheet still says pending while the newer revision is queued: '%s' %s" % [_choice(option), _texts(sheet)])
	net.release_hold("GET", FEEDBACK)
	await frames(3)
	check(Community.pending_feedback(LEVEL_ID, SHA).get("difficulty") == "hard" and _mentions(_texts(sheet), ["pending"]), "the read does not end pending either while the revision is queued: %s" % [_texts(sheet)])


# --- final review: the account a settled sheet shows, and rating discovery that spans devices ----------------------------


func test_a_settled_sheet_drops_the_prior_accounts_private_state_when_a_background_sign_in_changes_the_player() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	_serve(_reply({"liked": true, "like_eligible": true, "difficulty": "hard", "difficulty_eligible": true, "attempts": 5}, {"players_started": 12}, null, {}, row.sha256))
	check(Community.record_play_start(row.sha256) != "", "setup: the first account has a report waiting")
	var sheet: Overlay = await _open(world, row, Callable())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(c.like.button_pressed and _choice(c.difficulty) == "hard" and not c.like.disabled and _vote_open(c.difficulty) and _mentions(_texts(sheet), ["counted tries: 5"]), "control: the loaded sheet shows the first account's like, vote, eligibility and tries: %s" % [_texts(sheet)])
	# Nothing is in flight on the sheet. The report goes out in the background, the server answers 401 and the silent sign-in is another Play Games account.
	pilot.account = "p2"
	_serve(_reply({}, {"players_started": 12}, null, {}, row.sha256))  # what the second account has: no like, no vote, no tries
	net.hold("GET", FEEDBACK)  # its read stays out, so only the first account's old answer could be what is on screen
	net.answer("POST", "/plays", 401, {"error": "Sign in again."})
	net.answer("POST", "/session", 200, SESSION_TWO)
	Community.activate_feedback()
	await frames(4)
	check(Community.player_id() == "p_2" and net.count("POST", "/plays") == 1, "setup: the background report was refused and the device is the second account now: '%s', %d reports" % [Community.player_id(), net.count("POST", "/plays")])
	var texts := _texts(sheet)
	check(not c.like.button_pressed and _choice(c.difficulty) == "" and not _mentions(texts, ["hard", "counted tries: 5"]), "the first account's like, vote and tries must vanish at once, without a refresh or reopening: liked %s, '%s' %s" % [c.like.button_pressed, _choice(c.difficulty), texts])
	_tap_toggle(c.like)  # a tap that still reaches the first account's controls ...
	_pick(c.difficulty, "easy")
	await frames(4)
	check(net.count("POST", LIKE) + net.count("DELETE", LIKE) + net.count("PUT", DIFFICULTY) == 0, "... must not send a choice for the second account: %s" % [net.requests.map(func(r: Dictionary) -> String: return "%s %s" % [r.method, r.url])])
	check(Community.pending_feedback(LEVEL_ID, row.sha256).is_empty(), "... nor queue one for it: %s" % [Community.pending_feedback(LEVEL_ID, row.sha256)])
	net.release_hold("GET", FEEDBACK)
	await frames(4)
	check(not c.like.button_pressed and _choice(c.difficulty) == "" and c.like.disabled and _vote_closed(c.difficulty) and _mentions(_texts(sheet), ["counted tries: 0"]), "the second account's own answer shows, with its own closed choices: %s" % [_texts(sheet)])


func test_a_settled_sheet_drops_the_accounts_private_state_when_its_account_is_deleted() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"liked": true, "like_eligible": true, "difficulty": "hard", "difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	if sheet == null:
		return
	var c := _controls(sheet)
	if c.like == null or c.difficulty == null:
		check(false, "the sheet needs one Like toggle and one difficulty choice")
		return
	check(c.like.button_pressed and _choice(c.difficulty) == "hard" and _mentions(_texts(sheet), ["counted tries: 5"]), "control: the loaded sheet shows the account's own state")
	net.answer("DELETE", "/me", 204)
	var error: String = await Community.delete_account()
	check(error == "", "setup: the account is deleted and erased here: '%s'" % error)
	await frames(4)
	var texts := _texts(sheet)
	check(not c.like.button_pressed and _choice(c.difficulty) == "" and not _mentions(texts, ["hard", "counted tries: 5"]), "an erased account's like, vote and tries must not stay on the open sheet: liked %s, '%s' %s" % [c.like.button_pressed, _choice(c.difficulty), texts])


## A server that counts each attempt id once, as the real one does, and answers the feedback read with that count on top of `others` attempts made elsewhere. `ids` is id → the highest revision it has seen; `lose` makes it count a report and then not answer it.
func _counting_server(net: FakeTransport, row: Dictionary, others: int) -> Dictionary:
	var server := {"ids": {}, "lose": false}
	var serve := func() -> void:
		var total: int = others + server.ids.size()
		_serve(_reply({"attempts": total, "like_eligible": total >= 5, "difficulty_eligible": total >= 5}, {"players_started": 12}, null, {}, row.sha256))
	serve.call()
	net.respond("POST", "/plays", func(request: Dictionary) -> Dictionary:
		var acks := []
		for attempt: Dictionary in _json(request.body).get("attempts", []):
			server.ids[attempt.id] = maxi(int(server.ids.get(attempt.id, 0)), int(attempt.revision))
			acks.append({"id": attempt.id, "revision": int(attempt.revision)})
		serve.call()
		if server.lose:
			return {"status": 0}
		return {"status": 200, "body": {"acknowledged": acks, "discarded": [], "cleared": []}})
	return server


## Details of `row` opened and closed again, as a player who looks at their tries and leaves: what the server says then is the confirmed progress.
func _observe(row: Dictionary) -> void:
	var sheet: Overlay = await _open(world, row, Callable())
	if sheet != null:
		sheet.close()
		await frames(2)


func test_a_fifth_try_split_with_another_device_offers_rate_while_this_devices_report_is_pending() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	_counting_server(net, row, 4)  # four counted tries from another device or an earlier install
	await _observe(row)
	var seen: Dictionary = Community.play_progress(row.sha256)
	check(seen.confirmed_attempts == 4 and seen.local_attempts == 0 and seen.can_offer_rating == false, "setup: Details confirmed four tries and this device has none: %s" % [seen])
	var lost: Level = await _lose(_stage(row))
	check(net.count("POST", "/plays") == 0 and Community.play_progress(row.sha256).pending == true, "setup: nothing is sent before the community is entered, so the new try is still pending")
	check(_buttons(lost.hud, "Rate level").size() == 1, "four tries elsewhere and this failed run are the fifth: Rate level is offered")


func test_a_fifth_try_split_with_another_device_offers_rate_after_this_devices_reports_were_acknowledged() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	var server := _counting_server(net, row, 3)
	await _observe(row)
	Community.activate_feedback()
	var first: Level = await _lose(stage)
	check(_buttons(first.hud, "Rate level").is_empty(), "three tries elsewhere and this one are four: no rating yet")
	first.free()
	await _cooldown()  # the first run's finish goes out ...
	await _cooldown()  # ... and the gap after it passes
	var second: Level = await _lose(stage)
	check(server.ids.size() == 2 and server.ids.values().count(2) == 1, "setup: the first run's start and finish and the second run's start were acknowledged before its result: %s" % [server.ids])
	check(_buttons(second.hud, "Rate level").size() == 1, "three tries elsewhere and two acknowledged ones here are the fifth: Rate level is offered")


func test_tries_the_server_already_counted_are_not_counted_twice_when_looking_for_the_fifth() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	var server := _counting_server(net, row, 2)
	Community.activate_feedback()
	var first: Level = await _lose(stage)
	first.free()
	await _cooldown()
	await _cooldown()
	check(server.ids.size() == 1 and server.ids.values() == [2], "setup: the first run's start and finish are acknowledged: %s" % [server.ids])
	await _observe(row)  # the server's three now include the first run
	check(Community.play_progress(row.sha256).confirmed_attempts == 3, "setup: Details confirmed three tries")
	var second: Level = await _lose(stage)
	check(_buttons(second.hud, "Rate level").is_empty(), "two tries elsewhere and two here are four: a try the server already counted is not counted again")
	second.free()
	await _cooldown()
	await _cooldown()
	check(not Community.play_progress(row.sha256).can_offer_rating, "a start's acknowledgment and its finish's are one try, so four is still not five")
	var third: Level = await _lose(stage)
	check(_buttons(third.hud, "Rate level").size() == 1, "the fifth try offers Rate level")


func test_a_start_whose_report_answer_was_lost_still_counts_toward_the_fifth_try() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	var server := _counting_server(net, row, 3)
	await _observe(row)
	Community.activate_feedback()
	server.lose = true  # the server counts each report, but no answer reaches this device
	var first: Level = await _lose(stage)
	check(_buttons(first.hud, "Rate level").is_empty(), "three tries elsewhere and one here are four")
	first.free()
	var second: Level = await _lose(stage)
	check(net.count("POST", "/plays") == 1, "setup: the report went out once and its answer was lost: %d" % net.count("POST", "/plays"))
	check(_buttons(second.hud, "Rate level").size() == 1, "three tries elsewhere and two here are the fifth, whatever the lost answer said")


func test_play_upload_shows_motion_then_a_brief_confirmation_without_reopening_details() -> void:
	var net := _fake()
	await _signed_in(net)
	var row: Dictionary = await _download(net, _level())
	_serve(_reply({}, {}, null, {}, row.sha256))
	var id := Community.record_play_start(row.sha256)
	Community.record_play_finish(id, "cleared")
	var sheet: Overlay = await _sheet(row)
	var icon: Control = sheet.find_child("SyncIndicator", true, false)
	check(icon != null, "pending play history needs a visual sync indicator")
	if icon == null:
		return
	check(icon.is_visible_in_tree() and icon.is_processing(), "the queued clear visibly animates while voting waits")
	var turn := icon.rotation
	await frames(4)
	check(icon.rotation != turn, "the pending indicator must move, not merely exist")
	net.hold("POST", "/plays")
	Community.activate_feedback()
	await frames(3)
	check(icon.is_visible_in_tree() and not icon.get("confirmed"), "sending is not confirmation")
	_serve(_reply({"cleared": true, "like_eligible": true, "difficulty_eligible": true}, {}, null, {}, row.sha256))
	net.answer("POST", "/plays", 200, {"acknowledged": [{"id": id, "revision": 2}], "discarded": [], "cleared": [row.sha256]})
	net.release_hold("POST", "/plays")
	await frames(4)
	check(icon.is_visible_in_tree() and icon.get("confirmed") == true and icon.rotation == 0.0, "durable acknowledgement replaces motion with the check")
	check(_vote_open(_controls(sheet).difficulty), "the same sheet unlocks voting")
	Engine.time_scale = 10.0
	await tree.create_timer(1.5).timeout
	check(icon.is_visible_in_tree() and icon.get("confirmed") == true, "confirmation remains visible before two seconds")
	await tree.create_timer(0.7).timeout
	Engine.time_scale = 1.0
	check(not icon.visible and not icon.is_processing(), "confirmation disappears after two seconds and stops processing")


func test_a_vote_error_stops_motion_without_claiming_success_and_retry_confirms() -> void:
	var net := _fake()
	await _signed_in(net)
	_serve(_reply({"difficulty_eligible": true, "attempts": 5}))
	var sheet: Overlay = await _sheet(_row())
	var icon: Control = sheet.find_child("SyncIndicator", true, false)
	check(icon != null, "the feedback sheet needs its sync indicator")
	if icon == null:
		return
	check(not icon.visible, "opening already-confirmed feedback does not invent an upload")
	net.hold("PUT", DIFFICULTY)
	_pick(_controls(sheet).difficulty, "hard")
	await frames(3)
	check(icon.is_visible_in_tree() and icon.is_processing(), "an unconfirmed choice shows motion")
	net.answer("PUT", DIFFICULTY, 0)
	net.release_hold("PUT", DIFFICULTY)
	await frames(3)
	check(icon.is_visible_in_tree() and not icon.is_processing() and not icon.get("confirmed"), "offline feedback remains visibly queued without endless motion or a success check")
	await _cooldown()
	_containing(sheet, "refresh")[0].pressed.emit()
	await frames(4)
	check(icon.is_visible_in_tree() and icon.get("confirmed") == true, "a successful retry shows confirmation")
	Community.identity_changed.emit("")
	await frames(1)
	check(not icon.visible, "account erasure clears the prior account's confirmation")
