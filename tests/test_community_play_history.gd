extends "res://tests/test_case.gd"
## Task 7: a community play's lifecycle, read back from the play history file. A real Level opens a real published
## stage (downloaded through FakeTransport) with the real Community and CommunityHistory; only the server and the Play
## Games device are fakes (tests/support/fake_*.gd). Every check reads the saved history, the way a restart would see
## it, never the wiring between Level and Community.
##
## The Task 6 seam (`Community.history_path`) is reached through a Variant, so this file compiles without it: `_boot`
## names what is missing and the test fails there, instead of playing against the real user history.

const PREVIEW := preload("res://scenes/level_preview.gd")
const DIR := "user://test_community_play/"
const HISTORY := DIR + "history.json"
const OWNER := "p_1"  # the player id the session below names
const LEVEL_ID := "lvl_abcdefghij"  # the stable id the server gives the level
const SESSION := {"token": "tok1", "player": {"id": OWNER, "name": "Pilot"}}
const LESSON_FRAMES := 4800  # the cap on driving a training's guided steps (test_tutorial.gd's full run uses the same); the check after it fails when the lesson has not ended
const FAST := 100.0  # Engine.time_scale while a cooldown passes: at 60 FPS a frame then spans about 1.7 s
const COOLDOWN_FRAMES := 24  # frames at FAST: about 40 s, past the 30 s routine gap

var _c: Variant = Community  # Task 6 members go through this, so a missing one fails a check instead of the file
var _runner_scene: Variant  # the runner's current scene when the test began; this file never frees it
var pilot := FakePlatform.new()


# --- lifecycle of one play -------------------------------------------------------------------------------------------


func test_a_drifting_ship_that_dies_before_its_first_thrust_starts_and_ends_one_attempt() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var data := _level({"ship": {"position": [0, 0], "velocity": [200, 0]}})
	var row: Dictionary = await _download(net, data)
	check(row.sha256 != LevelFormat.sha256(data), "control: the stage is named by its download's bytes, not by the reserialized level")
	var lvl: Level = await _start(_stage(row))
	var results := []
	lvl.finished.connect(func(won: bool) -> void: results.append(won))
	var started := _records()
	var id := _sole_id()
	check(started.size() == 1 and _open_start(started[0]), "a drifting ship counts one start before any thrust: %s" % [started])
	check(id != "" and started[0].sha256 == row.sha256 and _raw(id).get("level") == LEVEL_ID, "the start names the download's hash and the stable level id: %s" % [started])
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	var ended := _records()
	check(ended.size() == 1 and ended[0].id == id and _ended_as(ended[0], "failed"), "the death ends that same attempt as failed: %s" % [ended])
	check(results == [false], "the level reports one loss: %s" % [results])
	_done()


func test_a_tour_and_pauses_start_nothing_until_live_then_start_one_attempt() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	Tuning.set_value("tours", true)
	var row: Dictionary = await _download(net, _level({"tour": [{"position": [1500, 0], "text": "A wall."}]}))
	var lvl: Level = await _start(_stage(row))
	check(lvl.tour != null and tree.paused, "control: the tour holds the level paused")
	check(_records().is_empty(), "a tour starts no attempt: %s" % [_records()])
	for _i in 10:
		if lvl.tour == null:
			break
		lvl.tour.next()
	await frames(2)
	var id := _sole_id()
	check(id != "" and _open_start(_find(_records(), id)), "the first live tick after the tour starts one attempt: %s" % [_records()])
	lvl.hud.toggle_pause()
	await frames(2)
	check(tree.paused and _ids(_records()) == [id], "the pause card starts no other attempt: %s" % [_records()])
	lvl.hud.toggle_pause()
	lvl.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)  # sent to the app in the background
	await frames(2)
	check(not tree.paused and _ids(_records()) == [id], "resuming or going to the background starts no other attempt: %s" % [_records()])
	lvl.finish(true)
	await frames(2)
	var rows := _records()
	check(rows.size() == 1 and rows[0].id == id and _ended_as(rows[0], "cleared"), "the one attempt ends as the clear: %s" % [rows])
	_done()


func test_a_level_built_while_paused_starts_only_on_its_first_live_tick() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	tree.paused = true
	await _start(_stage(row))
	check(_records().is_empty(), "a paused level is not live yet, so it starts nothing: %s" % [_records()])
	tree.paused = false
	await frames(2)
	var rows := _records()
	check(rows.size() == 1 and _open_start(rows[0]), "the first live tick starts one attempt: %s" % [rows])
	_done()


# --- leaving: Retry, Menu, Back, teardown ---------------------------------------------------------------------------


func test_retry_abandons_the_live_attempt_and_opens_one_new_one() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var first: Level = await _open(_stage(row))
	var old_id := _sole_id()
	check(old_id != "", "opening a stage starts one attempt: %s" % [_records()])
	first.hud.retry_requested.emit()
	await frames(3)
	var second := tree.current_scene as Level
	check(second != null and second.level_id == _stage(row) and not is_instance_valid(first), "the retry opens the stage again and the old level leaves")
	var rows := _records()
	var fresh := _others(rows, old_id)
	check(rows.size() == 2 and _ended_as(_find(rows, old_id), "abandoned") and fresh.size() == 1 and _open_start(fresh[0]), "the retry abandons the live attempt once and starts one new one: %s" % [rows])
	_done()


func test_retry_abandons_the_old_attempt_even_when_the_new_level_is_ready_first() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	var first: Level = await _open(stage)
	var old_id := _sole_id()
	check(old_id != "", "opening a stage starts one attempt: %s" % [_records()])
	var second := Progress.build(stage)
	world.add_child(second)  # the new level is ready and live while the old one still runs
	await frames(2)
	first.free()
	tree.current_scene = null
	await frames(2)
	var rows := _records()
	var fresh := _others(rows, old_id)
	check(rows.size() == 2 and _ended_as(_find(rows, old_id), "abandoned") and fresh.size() == 1 and _open_start(fresh[0]), "the old attempt ends once, whichever level is ready first: %s" % [rows])
	_done()


func test_retry_after_a_loss_keeps_the_finished_attempt() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var first: Level = await _open(_stage(row))
	var old_id := _sole_id()
	first.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	first.hud.retry_requested.emit()
	await frames(3)
	var rows := _records()
	var fresh := _others(rows, old_id)
	check(rows.size() == 2 and _ended_as(_find(rows, old_id), "failed") and fresh.size() == 1 and _open_start(fresh[0]), "a retry after a loss keeps the failure and opens one new attempt: %s" % [rows])
	_done()


func test_menu_abandons_the_live_attempt_once() -> void:
	await _leave_live(false)


func test_android_back_abandons_the_live_attempt_once() -> void:
	await _leave_live(true)


func test_freeing_a_live_level_abandons_once_and_a_finished_one_keeps_its_result() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	var live: Level = await _start(stage)
	var live_id := _sole_id()
	live.free()  # the scene is torn down while the attempt is live
	var rows := _records()
	check(live_id != "" and rows.size() == 1 and rows[0].id == live_id and _ended_as(rows[0], "abandoned"), "tearing down a live level abandons its attempt once: %s" % [rows])
	var lost: Level = await _start(stage)
	var fresh := _others(_records(), live_id)
	var lost_id: String = fresh[0].id if fresh.size() == 1 else ""
	lost.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	lost.free()
	rows = _records()
	check(rows.size() == 2 and _ended_as(_find(rows, live_id), "abandoned") and _ended_as(_find(rows, lost_id), "failed"), "tearing down a finished level keeps its outcome: %s" % [rows])
	_done()


# --- results: one terminal result, persisted before the card, clears ---------------------------------------------


func test_a_win_and_a_death_in_one_frame_leave_one_result_either_way() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	# A death, then the goal, on the same frame.
	var lost: Level = await _start(stage)
	var lost_id := _sole_id()
	var lost_results := []
	lost.finished.connect(func(won: bool) -> void: lost_results.append(won))
	lost.ship.take_damage(Ship.MAX_HEALTH)
	lost.finish(true)
	await frames(2)
	lost.free()
	# The goal, then the death, on the same frame.
	var won: Level = await _start(stage)
	var fresh := _others(_records(), lost_id)
	var won_id: String = fresh[0].id if fresh.size() == 1 else ""
	var won_results := []
	won.finished.connect(func(clear: bool) -> void: won_results.append(clear))
	won.finish(true)
	won.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	var rows := _records()
	check(lost_results == [false] and won_results == [true], "each level reports one result: %s, %s" % [lost_results, won_results])
	check(rows.size() == 2 and _ended_as(_find(rows, lost_id), "failed") and _ended_as(_find(rows, won_id), "cleared"), "each attempt keeps its first terminal result: %s" % [rows])
	_done()


func test_the_clear_is_on_disk_when_the_result_card_shows() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var lvl: Level = await _start(_stage(row))
	var id := _sole_id()
	var card: PanelContainer = lvl.hud._result  # the end panel: it shows when the result is set
	var at_card := {"shown": false, "outcome": "the card never showed"}
	card.visibility_changed.connect(func() -> void:
		if card.is_visible_in_tree() and not at_card.shown:
			at_card.shown = true
			var rows := _records()
			at_card.outcome = rows[0].get("outcome") if rows.size() == 1 else "not one record"
	)
	lvl.finish(true)
	await frames(2)
	check(at_card.shown and at_card.outcome == "cleared", "the clear must be saved before the card shows: %s" % [at_card])
	check(id != "" and _ended_as(_find(_records(), id), "cleared"), "the clear is saved: %s" % [_records()])
	_done()


func test_practice_after_a_clear_is_not_counted_and_a_local_best_alone_is_no_clear() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var stage := _stage(row)
	Progress.record_win(stage, 1000, 20.0)  # a best saved on this device before any history existed: no clear
	var first: Level = await _start(stage)
	var id := _sole_id()
	check(id != "" and _open_start(_find(_records(), id)), "a local best fabricates no clear: %s" % [_records()])
	first.finish(true)
	await frames(2)
	check(id != "" and _ended_as(_find(_records(), id), "cleared"), "the clear is saved: %s" % [_records()])
	first.free()
	var practice: Level = await _start(stage)
	practice.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	var rows := _records()
	check(rows.size() == 1 and rows[0].id == id and _ended_as(rows[0], "cleared"), "practice after the clear is not counted: %s" % [rows])
	_done()


func test_an_interrupted_start_is_one_counted_start_after_a_restart() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	await _start(_stage(row))  # the app is killed here: the level never ends and nothing more is written
	var id := _sole_id()
	var restarted := _records()  # a new launch reads the saved file alone
	check(id != "" and _ids(restarted) == [id] and _open_start(_find(restarted, id)), "the start survives a restart as one unfinished attempt: %s" % [restarted])
	_done()


# --- what creates no report -----------------------------------------------------------------------------------------


func test_campaign_and_training_plays_create_no_report() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var control: String = await _control_play(row)
	await _idle(Progress.build("level_01"))
	var training: Tutorial = Progress.build("tutorial_1")  # the real training 1, with its lesson script
	world.add_child(training)
	check(training.level_id == "tutorial_1", "training 1 must be the real training stage, not '%s'" % training.level_id)
	var lesson_ended: bool = await _finish_lesson(training)
	check(lesson_ended, "training 1's lesson must end before its stage is torn down, so no caption is left waiting")
	check(control != "" and _ids(_records()) == [control], "campaign and training plays must add no report: %s" % [_records()])
	_done()


func test_an_editor_test_and_a_publish_proof_create_no_report() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var control: String = await _control_play(row)
	var draft := MyLevels.new_id()
	MyLevels.save(draft, LevelDoc.blank())
	var flight := Progress.build(draft, true)
	check(flight.testing and not flight.publishing, "control: an editor test flight")
	await _idle(flight)
	var proof := Progress.build(draft, true, true)
	check(proof.publishing, "control: a Publish proof, with Play Games available")
	await _idle(proof)
	check(control != "" and _ids(_records()) == [control], "an editor test or a Publish proof must add no report: %s" % [_records()])
	_done()


func test_a_demo_replay_and_a_disabled_preview_create_no_report() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var control: String = await _control_play(row)
	var data := LevelFormat.read(Community.level_path(row.sha256))
	var run := Demo.new()
	for _i in 2:
		run.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 100.0, "hull": 100.0}, {})
	await _idle(DemoViewer.create(data, run, func() -> void: pass))
	var preview: Level = LevelFormat.build(data, PREVIEW)
	preview.level_id = _stage(row)
	world.add_child(preview)
	await frames(3)
	check(preview.process_mode == Node.PROCESS_MODE_DISABLED, "control: a preview is frozen")
	check(control != "" and _ids(_records()) == [control], "a demo replay or a disabled preview must add no report: %s" % [_records()])
	_done()


func test_a_cached_stage_played_on_desktop_creates_no_report() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	var control: String = await _control_play(row)  # the same account, on a device with Play Games
	Community.platform = CommunityPlatform.new()  # the desktop build: no Play Games, so nothing is collected
	check(not Community.available(), "control: this platform has no community")
	await _start(_stage(row))
	check(control != "" and _ids(_records()) == [control], "a desktop play must add no report: %s" % [_records()])
	_done()


# --- leaving a live run, and a run begun without a player -------------------------------------------------------------


func test_leaving_a_live_level_persists_the_abandonment_and_starts_no_request_before_the_next_frame() -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	_answer_uploads(net)
	_c.activate_feedback()
	var lvl: Level = await _start(_stage(row))
	var ids := _attempt_ids()
	if ids.size() != 1:
		check(false, "setup: the live level records one attempt, not %d: %s" % [ids.size(), _file_json()])
		_done()
		return
	var live: String = ids[0]
	await _cooldown()  # a gap that an earlier upload starts runs out
	await _c.sync_feedback()  # the initial start goes up and is acknowledged
	await _cooldown()  # the gap that upload starts runs out: an exit may now flush at once
	check(_raw(live).get("acked") == 1 and _records().is_empty(), "setup: the initial start is acknowledged and nothing is queued: %s" % [_file_json()])
	var before := net.requests.size()
	lvl.free()  # the level leaves the tree: the exit persists the abandonment and must not start a request
	check(net.requests.size() == before, "leaving a live level must start no request before the next frame: %s" % [_urls(net).slice(before)])
	var queued := _records()
	check(queued.size() == 1 and queued[0].id == live and _ended_as(queued[0], "abandoned"), "the abandonment is persisted as revision 2 at once: %s" % [queued])
	# Positive control, same state: a fresh failed attempt reaches the server once frames pass. Without it the empty
	# count above could only mean that nothing is ever sent here.
	var fresh_lvl: Level = await _start(_stage(row))
	var fresh_ids := _attempt_ids().filter(func(id: String) -> bool: return id != live)
	check(fresh_ids.size() == 1, "control: the fresh run records its own attempt: %s" % [_file_json()])
	if fresh_ids.size() == 1:
		var fresh: String = fresh_ids[0]
		fresh_lvl.ship.take_damage(Ship.MAX_HEALTH)
		await frames(2)
		await _cooldown()  # the upload gap that the fresh run's first upload started runs out
		var sent: bool = await _until(func() -> bool: return _uploaded(net, fresh, 2), 300)
		check(sent, "control: a fresh failed attempt reaches the server after frames: %s" % [_urls(net)])
	_done()


func test_a_run_begun_without_a_player_never_reaches_an_account_that_signs_in_later_and_the_next_run_records() -> void:
	var net := _boot()
	if net == null:
		return
	_answer_uploads(net)
	var legacy := ConfigFile.new()  # a session saved before the player id was stored: still valid, and it names no player
	legacy.set_value("session", "token", "legacy")
	legacy.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
	legacy.save(Community.session_path)
	check(Community.signed_in() and _c.player_id() == "", "setup: the legacy token is valid and names no player")
	var row: Dictionary = await _download(net, _level())
	_c.activate_feedback()
	var early: Level = await _start(_stage(row))
	await frames(30)  # live with no player: a start retried on every tick would be tried here
	check(_attempt_total() == 0, "a run begun without a player records nothing: %s" % [_file_json()])
	await _sign_in(net)  # the player signs in while that same run is still live
	check(_c.player_id() == OWNER, "setup: the player is known after the sign-in")
	await frames(30)  # the same run, now with a player: a start retried on every tick would attach it here
	early.ship.take_damage(Ship.MAX_HEALTH)  # the run ends; nothing was recorded for it, so nothing is sent
	await frames(2)
	check(_attempt_total() == 0 and _plays(net).is_empty(), "a run begun before the sign-in is never attached to the account, nor sent: %s" % [_file_json()])
	var fresh: Level = await _start(_stage(row))  # a new run after the sign-in records normally
	var ids := _attempt_ids()
	if ids.size() != 1 or _attempt_total() != 1:
		check(false, "a run begun after the sign-in records one attempt for the player, not %d: %s" % [ids.size(), _file_json()])
		_done()
		return
	var mine: String = ids[0]
	fresh.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	await _cooldown()  # the upload gap the new run started runs out
	var sent: bool = await _until(func() -> bool: return _uploaded(net, mine, 2), 300)
	check(sent and _raw(mine).get("outcome") == "failed", "the new run's failure reaches the server for the player: %s" % [_urls(net)])
	_done()



# --- helpers ----------------------------------------------------------------------------------------------------------


## Coroutine: the fake world for one test, with the play history in this test's folder and the fakes in place. Null, with
## one failed check, when the Task 6 seam is missing or the runner has not redirected Community's files.
func _boot() -> FakeTransport:
	if not ("history_path" in _c):
		check(false, "Community.history_path is missing (the Task 6 seam): without it a play would write the real user history")
		return null
	if not (Community.dir.begins_with("user://test_") and Community.session_path.begins_with("user://test_")):
		check(false, "the runner must redirect Community's files to user://test_ paths")
		return null
	_runner_scene = tree.current_scene
	tree.paused = false
	Engine.time_scale = 1.0  # a test that failed mid-cooldown must not leave the clock fast
	DirAccess.remove_absolute(Community.session_path)  # a session an earlier test saved must not sign this one in
	_wipe()
	Community.use_defaults()
	_c.history_path = HISTORY
	var net := FakeTransport.new()
	world.add_child(net)  # freed with the world
	Community.transport = net
	Community.platform = pilot
	return net


## The end of every test: what it opened is freed while the history path is still this test's, then the runner's reset.
func _done() -> void:
	_release()
	tree.paused = false
	Community.use_defaults()
	_wipe()


## Frees what this test opened: the current scene when it is not the runner's (Progress.open makes it current), and every
## node in `world`. A level that is still live leaves here the way a real exit does, so it is abandoned now, not later.
func _release() -> void:
	var opened = tree.current_scene
	if is_instance_valid(opened) and opened != _runner_scene:
		opened.free()
	tree.current_scene = _runner_scene if is_instance_valid(_runner_scene) else null
	for node in world.get_children():
		node.free()


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for file in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR + file)


## Coroutine: signs in as `OWNER` and forgets the requests that took.
func _sign_in(net: FakeTransport) -> void:
	net.answer("GET", "/nonce", 200, {"nonce": "n1"})
	net.answer("POST", "/session", 200, SESSION)
	var error: String = await Community.sign_in()
	check(error == "", "setup: sign-in failed: '%s'" % error)
	net.requests.clear()


## A playable published level: a ship at the origin and a goal 3000 px on. `overrides` replace whole top-level keys.
func _level(overrides := {}) -> Dictionary:
	var data := {"format": LevelFormat.FORMAT, "version": LevelFormat.VERSION, "title": "Loop", "ship": {"position": [0, 0]}, "goal": {"position": [3000, 0]}}
	data.merge(overrides, true)
	return data


## Coroutine: downloads `data` through the fake CDN, as a list's Play does. The file is compact JSON, not the stable layout,
## so the stage is named by these bytes and not by the level's reserialized hash.
func _download(net: FakeTransport, data: Dictionary) -> Dictionary:
	var bytes := JSON.stringify(data).to_utf8_buffer()
	var row := {"level_id": LEVEL_ID, "title": "Loop", "author": "Pilot", "latest": 1, "sha256": CommunityWire.sha256_hex(bytes), "likes": 0, "players": 0}
	net.answer("GET", "/index", 200, {"commit": "abc123"})
	net.answer("GET", "/gh/", 200, bytes)
	var error: String = await Community.download(row)
	check(error == "" and LevelFormat.validate(LevelFormat.read(Community.level_path(row.sha256))).is_empty(), "setup: the level must download as a playable file: '%s'" % error)
	net.requests.clear()
	return row


## The stage id a downloaded level plays as: `community_` and the hash of the downloaded bytes.
func _stage(row: Dictionary) -> String:
	return Community.STAGE_PREFIX + row.sha256


## Coroutine: builds `stage` as Progress does, adds it to the world and runs two frames, so a live level has started.
func _start(stage: String) -> Level:
	var lvl := Progress.build(stage)
	world.add_child(lvl)
	await frames(2)
	return lvl


## Coroutine: opens `stage` as the game does (Progress.open); the new level becomes the runner's current scene.
func _open(stage: String) -> Level:
	Progress.open(stage)
	await frames(3)
	return tree.current_scene as Level


## Coroutine: runs a level or preview in the world for a few frames, then frees it. Not for a training: freeing one while a
## caption waits resumes its lesson on a freed instance (`_finish_lesson` runs a training to its end first).
func _idle(node: Node) -> void:
	world.add_child(node)
	await frames(3)
	node.free()


## Coroutine: plays training `lvl` through its guided steps as a player does: OK on each caption, and the ring held while it
## shows (the driver test_tutorial.gd's full run uses). Valid for training 1, whose lesson never reveals the goal itself, so
## `_run` reveals it only when `lesson()` returns: then no caption or ring wait is left. False if the goal is not shown
## within LESSON_FRAMES.
func _finish_lesson(lvl: Tutorial) -> bool:
	for _frame in LESSON_FRAMES:
		await frames(1)
		if lvl.goal_revealed():
			return true
		if lvl.card_waiting():
			lvl.press_ok()
		lvl.hold_ring(lvl.ring_active())
	return false


## Coroutine: a live level left by the Menu button or by the Android Back gesture. It must abandon the attempt once and
## open the community list.
func _leave_live(by_back: bool) -> void:
	var net := _boot()
	if net == null:
		return
	await _sign_in(net)
	var row: Dictionary = await _download(net, _level())
	net.answer("GET", "/levels", 200, [])  # the community list that opens behind Menu and Back
	var lvl: Level = await _open(_stage(row))
	var id := _sole_id()
	if by_back:
		lvl.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	else:
		lvl.hud.menu_requested.emit()
	await frames(3)
	check(tree.current_scene is CommunityScreen, "leaving goes to the community list: %s" % [tree.current_scene])
	var rows := _records()
	check(id != "" and rows.size() == 1 and rows[0].id == id and _ended_as(rows[0], "abandoned"), "leaving abandons the live attempt exactly once: %s" % [rows])
	_done()


## Coroutine: one community play that does record, so a "no report" check after it cannot pass by accident. Returns its id.
func _control_play(row: Dictionary) -> String:
	var lvl: Level = await _start(_stage(row))
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	lvl.free()
	return _sole_id()


## The account's pending attempt snapshots as a restart reads them from the file, oldest first. Nothing is acknowledged
## in these tests, so every attempt is pending.
func _records() -> Array:
	var history := CommunityHistory.new()
	history.path = HISTORY
	if history.load_file() != OK:
		check(false, "the saved history must load")
		return []
	return history.batch(OWNER)


## The id of the only attempt on file, "" when there is not exactly one.
func _sole_id() -> String:
	var rows := _records()
	return rows[0].id if rows.size() == 1 else ""


## The whole history file as it reads back, {} when there is none. The instance parse does not log a bad file.
func _file_json() -> Dictionary:
	if not FileAccess.file_exists(HISTORY):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(HISTORY)) != OK or not json.data is Dictionary:
		return {}
	return json.data


## Attempt `id` as the file stores it, with its stable level id, which the pending snapshots do not carry.
func _raw(id: String) -> Dictionary:
	var attempts: Variant = _file_json().get("owners", {}).get(OWNER, {}).get("attempts", {})
	return attempts.get(id, {}) if attempts is Dictionary else {}


## The record of attempt `id`, {} when there is none.
func _find(rows: Array, id: String) -> Dictionary:
	for rec: Dictionary in rows:
		if rec.get("id") == id:
			return rec
	return {}


## The records of every attempt but `id`.
func _others(rows: Array, id: String) -> Array:
	return rows.filter(func(rec: Dictionary) -> bool: return rec.get("id") != id)


func _ids(rows: Array) -> Array:
	return rows.map(func(rec: Dictionary) -> String: return rec.get("id"))


## Whether `rec` is a start that nothing has ended yet.
func _open_start(rec: Dictionary) -> bool:
	return rec.get("revision") == 1 and rec.get("outcome") == null


## Whether `rec` is an attempt that ended with `outcome`.
func _ended_as(rec: Dictionary, outcome: String) -> bool:
	return rec.get("revision") == 2 and rec.get("outcome") == outcome


## Coroutine: lets the 30 s routine gap (a SceneTreeTimer) expire by speeding the engine clock up for a few process frames,
## then puts the clock back. Call it only where a test needs the next upload to be allowed.
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


## Persistent answers for every later request, as the server gives them: a fresh nonce each time, and each report
## acknowledged at the revision it carried.
func _answer_uploads(net: FakeTransport) -> void:
	net.respond("GET", "/nonce", func(_r: Dictionary) -> Dictionary: return {"status": 200, "body": {"nonce": "n_%d" % net.count("GET", "/nonce")}})
	net.respond("POST", "/plays", func(r: Dictionary) -> Dictionary: return {"status": 200, "body": _ack(_attempts(r).map(func(a: Dictionary) -> Array: return [a.id, int(a.revision)]))})


## The server's acknowledgment of `entries`, each `[id, revision]`.
func _ack(entries: Array) -> Dictionary:
	return {"acknowledged": entries.map(func(e: Array) -> Dictionary: return {"id": e[0], "revision": e[1]}), "discarded": [], "cleared": []}


## Every POST /plays made, in order.
func _plays(net: FakeTransport) -> Array:
	return net.requests.filter(func(r: Dictionary) -> bool: return r.method == "POST" and r.url.get_slice("?", 0).ends_with("/plays"))


## Every request made, as "METHOD url", in order.
func _urls(net: FakeTransport) -> Array:
	return net.requests.map(func(r: Dictionary) -> String: return "%s %s" % [r.method, r.url])


## A request's JSON body as a Dictionary, {} when it is not one.
func _report(request: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(request.body.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## The attempt snapshots a POST /plays carried.
func _attempts(request: Dictionary) -> Array:
	var attempts: Variant = _report(request).get("attempts")
	return attempts if attempts is Array else []


## Whether some POST /plays carried attempt `id` at `revision`.
func _uploaded(net: FakeTransport, id: String, revision: int) -> bool:
	return _plays(net).any(func(r: Dictionary) -> bool: return _attempts(r).any(func(a: Dictionary) -> bool: return a.id == id and int(a.revision) == revision))


## The ids of the attempts `owner` has on file, acknowledged or not.
func _attempt_ids(owner := OWNER) -> Array:
	var owners: Variant = _file_json().get("owners", {})
	if not (owners is Dictionary) or not owners.has(owner):
		return []
	return owners[owner].get("attempts", {}).keys()


## How many attempts every account has on file.
func _attempt_total() -> int:
	var total := 0
	var owners: Variant = _file_json().get("owners", {})
	if owners is Dictionary:
		for owner in owners:
			total += owners[owner].get("attempts", {}).size()
	return total
