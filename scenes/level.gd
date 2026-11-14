class_name Level
extends Node2D
## Root script of every level: the Ship child is point A, the Goal child is point B.

signal finished(won: bool)

const MENU := "res://scenes/main.tscn"

var ship: Ship
var goal: Goal
var hud: Hud
var input: ShipInput
## Shown on the intro card until the first thrust: what this level teaches, in a few words.
@export var title := ""
@export var hint := ""
## Always draw the ship's velocity arrow (tutorials). Levels follow the player's setting.
@export var show_velocity := false
## Points for a medal, from the level file: 0 when the level has no par.
@export var par := 0
## Progress key; defaults to the scene file's stem. Empty (a level built in code) saves nothing.
var level_id := ""
## An author's test flight of their own level: Menu returns to the editor, a finish marks the
## level completed, and no score is recorded.
var testing := false
## A Test started from Publish: Retry keeps the intent; only a win offers confirmation.
var publishing := false
## The running first-flight tour, or null.
var tour: Tour
## Set by Progress.build for levels that record a demo (not tutorials): the level data this run
## was built from and its hash.
var level_data := {}
var level_sha256 := ""
## This run's demo; complete once `finished` is emitted. Null when the level records none.
var demo: Demo
var _recorder: DemoRecorder
var _done := false
## The community attempt this run counts: its id, "" when none was recorded. Set once, when the run first goes live.
var _attempt := ""
## Whether the run's live-start decision was made. It is made once, even when nothing was recorded.
var _start_checked := false
var _result_generation := 0
var _result_account := ""
var _result_sha := ""
var _result_revision := 0
var _result_points := -1
var _result_board := {}
var _result_score := {}
var _result_error := ""
var _board_reading := false
var _board_again := false
var _board_force := false


func _ready() -> void:
	for child in get_children():
		if child is Ship: ship = child
		elif child is Goal: goal = child
	assert(ship != null and goal != null, "%s needs one Ship and one Goal child" % name)
	if level_id == "":
		level_id = scene_file_path.get_file().get_basename()
	var stars := Starfield.new()
	stars.ship = ship
	add_child(stars)
	if level_sha256 != "":
		_recorder = DemoRecorder.new(self)
		demo = _recorder.demo
		add_child(_recorder)
	hud = Hud.new()
	hud.ship = ship
	hud.menu_text = "Edit" if testing and not publishing else "Menu"
	if publishing:
		hud.next_text = "Publish"
	elif _ends_training():
		hud.next_text = "End training"
	hud.can_replay = demo != null
	ship.show_velocity = show_velocity or Settings.show_velocity
	hud.goal = goal
	add_child(hud)
	input = ShipInput.new(ship)
	add_child(input)
	input.scheme_changed.connect(_refresh_intro)
	if Tuning.tours and not testing and has_node("Tour") and Progress.best_points(level_id) < 0 and not Progress.toured.has(level_id):
		Progress.toured[level_id] = true
		hud.visible = false
		tour = Tour.new(self)
		tour.finished.connect(_end_tour)
		add_child(tour)
	else:
		_show_intro()
	hud.retry_requested.connect(func(): Progress.open(level_id, testing, publishing))
	hud.menu_requested.connect(_to_menu)
	hud.replay_requested.connect(_replay)
	hud.rate_requested.connect(_rate)
	hud.next_requested.connect(_next)
	hud.board_requested.connect(_open_board)
	Community.board_updated.connect(_board_updated)
	Community.identity_changed.connect(_result_identity_changed)
	goal.reached.connect(finish.bind(true))
	ship.destroyed.connect(_ship_lost)
	ship.stranded.connect(_ship_stranded)
	Settings.changed.connect(_settings_changed)


## A run goes live on its first physics tick that is not paused and has no tour: physics callbacks run before the ship's step, so nothing has moved yet.
func _physics_process(_delta: float) -> void:
	if _start_checked or _done or tour != null:
		return
	_start_checked = true
	_attempt = _begin_attempt()


## The attempt this run starts: "" for any stage that is not a community play, or when nothing could be recorded.
func _begin_attempt() -> String:
	var sha := _community_sha()
	return "" if sha == "" else Community.record_play_start(sha)


## The downloaded version this run plays, from the hash in its community stage id; "" for any other stage and a test flight.
func _community_sha() -> String:
	if testing or not level_id.begins_with(Community.STAGE_PREFIX):
		return ""
	return level_id.trim_prefix(Community.STAGE_PREFIX)


## Leaving a live run (Retry, Menu, Back, a scene change or quitting) abandons it once. Only the record is saved here: the upload waits for a later flush, so no request starts while the tree is leaving.
func _exit_tree() -> void:
	_result_generation += 1
	if _attempt != "" and not _done and is_instance_valid(Community):
		_done = true
		Community.record_play_finish(_attempt, "abandoned")


## Losing the ship ends the stage, whether a level or a training.
func _ship_lost() -> void:
	finish(false)


func _ship_stranded() -> void:
	ship.death_cause = "Out of fuel"
	finish(false)


## The title card; tutorials skip it, as their lesson is the introduction.
func _show_intro() -> void:
	if title != "":
		hud.show_intro(display_name(), _intro_text())


## The intro card's hint: level 1's names the controls in use; other levels keep their own words.
func _intro_text() -> String:
	return input.intro_hint() if level_id == "level_01" else hint


## Settings can change on the pause card: the velocity arrow and the intro's controls follow at once.
func _settings_changed() -> void:
	ship.show_velocity = show_velocity or Settings.show_velocity
	ship.queue_redraw()  # the arrow must clear when it is switched off
	_refresh_intro()


## The intro card is redrawn while shown, so the controls it names stay current.
func _refresh_intro() -> void:
	if hud.intro_text() != "":
		hud.show_intro(display_name(), _intro_text())


## How the stage is named to the player: "Level 2 · Drift", "Training 6 · Black holes", or
## just the title of one of the player's own levels.
func display_name() -> String:
	var kind: String = {"level": "Level", "tutorial": "Training"}.get(level_id.get_slice("_", 0), "")
	var number := level_id.get_slice("_", 1).to_int() if kind != "" else 0  # a community id's hash is too long to be a number
	return "%s %d · %s" % [kind, number, title] if kind != "" and number > 0 else title


func _end_tour() -> void:
	tour = null
	hud.visible = true
	ship.use_camera()


func _notification(what: int) -> void:
	# A frozen level is a preview inside the editor or the demo viewer; its host handles Back.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and process_mode != PROCESS_MODE_DISABLED:
		var sheets := find_children("*", "Overlay", true, false)  # Back closes the top sheet before it leaves
		if sheets.is_empty():
			_to_menu()
		else:
			sheets.back().close()


## Rate level on the result card: the shared details sheet of the version this run played, without Play, scrolled to the player's own section.
func _rate() -> void:
	var sha := _community_sha()
	var info := Community.level_info(sha) if sha != "" else {}
	if info.is_empty() or not find_children("*", "Overlay", true, false).is_empty():
		return
	CommunityLevelDetails.open(self, {"level_id": info.level_id, "sha256": sha, "latest": info.version, "title": display_name(), "par": par}, Callable(), true)



func _to_menu() -> void:
	leave_to(get_tree(), level_id, testing, publishing)


## A Publish test returns to My levels; a normal test returns to its editor.
static func leave_to(tree: SceneTree, level_id: String, testing: bool, publishing := false) -> void:
	if publishing:
		tree.change_scene_to_node(MyLevelsScreen.new())
	elif testing:
		tree.change_scene_to_node(LevelEditor.create(level_id))
	elif level_id.begins_with(MyLevels.PREFIX):
		tree.change_scene_to_node(MyLevelsScreen.new())
	elif level_id.begins_with(Community.STAGE_PREFIX):
		tree.change_scene_to_node(CommunityScreen.new())
	elif level_id.begins_with("tutorial_") or level_id.begins_with("level_"):
		var main := load("res://scenes/main.gd")
		tree.change_scene_to_node(main.menu(main.Page.TRAINING if level_id.begins_with("tutorial_") else main.Page.OFFICIAL))
	else:
		tree.change_scene_to_file(MENU)


## The last training stage: its Next ends the training and returns to the main menu.
func _ends_training() -> bool:
	return level_id.begins_with("tutorial_") and Progress.next_level(level_id) == ""


func _next() -> void:
	if publishing:
		var screen := MyLevelsScreen.new()
		screen.confirm_publish_id = level_id
		get_tree().change_scene_to_node(screen)
	elif _ends_training():
		get_tree().change_scene_to_file(MENU)
	else:
		Progress.open(Progress.next_level(level_id))


func _replay() -> void:
	get_tree().change_scene_to_node(DemoViewer.create(level_data, demo, leave_to.bind(get_tree(), level_id, testing, publishing)))


## Ends the level once; later calls (a hit and the goal on one frame) are ignored.
func finish(won: bool) -> void:
	if _done:
		return
	_done = true
	ship.thrusting = false
	if _attempt != "":
		Community.record_play_finish(_attempt, "cleared" if won else "failed")  # saved before the result card shows
	if _recorder:
		_recorder.finish(won)
	ship.set_deferred("freeze", true)
	if won:
		Sfx.play("goal")
		if testing:
			MyLevels.mark_completed(level_id)
			if demo:
				MyLevels.save_demo(level_id, demo)
	var result := _score() if won else {"cause": ship.death_cause}
	result.name = display_name()
	var sha := _community_sha()
	result.can_rate = sha != "" and Community.play_progress(sha).can_offer_rating
	if demo and result.get("new_best", false) and not level_id.begins_with(MyLevels.PREFIX):  # a draft's best demo would never be read
		Progress.save_best_demo(level_id, demo)
	result.can_board = won and _board_eligible()
	if result.can_board:
		_result_generation += 1
		_result_account = Community.player_id()
		_result_sha = level_sha256
		var best_run := Progress.best_demo(level_id)
		_result_points = Progress.best_points(level_id) if best_run != null and best_run.level_sha256 == _result_sha else int(result.points)
		_result_board = Community.cached_board(_result_sha)
		if result.new_best and demo != null and Community.signed_in() and _result_account != "":
			_result_error = Community.queue_score(level_id, demo)
			if _result_error == "":
				_result_score = Community.score_state(_result_sha)
				_result_revision = int(_result_score.get("revision", 0))
				Community.score_result.connect(_score_result.bind(_result_generation))
	hud.show_result(won, result)
	if result.can_board:
		_render_standing()
		if Community.signed_in() and _result_account != "":
			_read_result_board()
		if _result_revision > 0:
			Community.sync_scores()
			if _result_score.get("state") == "queued":
				_result_score = Community.score_state(_result_sha)
			_render_standing()
	finished.emit(won)


## Frozen editor/viewer previews and training/drafts have no online result surface.
func _board_eligible() -> bool:
	return Community.available() and not testing and not publishing and process_mode != PROCESS_MODE_DISABLED and level_sha256 != "" and (level_id in Progress.levels() or level_id == Community.STAGE_PREFIX + level_sha256)


func _result_alive() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _done and _result_sha != "" and _result_sha == level_sha256 and _result_points >= 0


func _open_board() -> void:
	if _result_alive() and _board_eligible() and find_children("*", "Overlay", true, false).is_empty():
		Leaderboard.open(self, _result_sha, display_name(), _result_points)


func _board_updated(sha: String) -> void:
	if _result_alive() and sha == _result_sha:
		_result_board = Community.cached_board(sha)
		_render_standing()


func _result_identity_changed(_account: String) -> void:
	if not _result_alive():
		return
	_result_generation += 1
	_result_account = Community.player_id()
	_result_revision = 0
	_result_score = {}
	_result_error = ""
	_result_board = Community.cached_board(_result_sha)
	_render_standing()


func _score_result(account: String, sha: String, revision: int, result: Dictionary, generation: int) -> void:
	if not _result_alive() or generation != _result_generation or account != _result_account or account != Community.player_id() or sha != _result_sha or revision != _result_revision or Community.score_state(sha).get("revision") != revision:
		return
	_result_score = result.duplicate(true)
	_render_standing()
	if result.get("state") == "posted":
		_read_result_board(true)


## Serialize the post-upload refresh after any older held read; never let its pre-upload row win.
func _read_result_board(force := false) -> void:
	_board_again = true
	_board_force = _board_force or force
	if _board_reading:
		return
	_board_reading = true
	var generation := _result_generation
	while _board_again and _result_alive() and generation == _result_generation:
		_board_again = false
		var fresh := _board_force
		_board_force = false
		var board := await Community.board(_result_sha, fresh)
		if not _result_alive() or generation != _result_generation:
			break
		if not _board_again:
			_result_board = board
			if fresh and not board.has("error") and not board.get("cached", true):
				_result_score = {}  # the post-upload board supersedes the provisional POST rank
			_render_standing()
	_board_reading = false


func _render_standing() -> void:
	if not _result_alive():
		return
	var board := _result_board.duplicate(true)
	var state: String = _result_score.get("state", "")
	if state == "posted" and _result_score.get("best", false):
		# POST points are submitted points; only best:true associates them with the stored-best rank.
		board["owner"] = _result_account
		board["you"] = {"rank": _result_score.rank, "points": _result_score.points, "player": {"id": _result_account}}
		board["cached"] = false
		board["offline"] = false
	var lines: Array[String] = []
	if _result_error != "":
		lines.append(_result_error)
	elif state == "posting":
		lines.append("Posting…")
	elif state == "queued":
		lines.append("Posting unavailable this launch" if _result_score.get("denied", false) else "Will post when online")
		if _result_score.get("error", "") != "":
			lines.append(_result_score.error)
	elif state == "dropped":
		lines.append(_result_score.get("error", "Run could not be posted"))
	lines.append(Leaderboard.standing(board, _result_points))
	var you: Variant = board.get("you")
	var exact := Leaderboard.standing(board, -1)
	if you is Dictionary and int(you.points) != _result_points and exact != "Not played yet":
		lines.append("%s · %d points" % [exact, you.points])
	hud.set_standing("\n".join(lines))
	hud.set_board(_result_board, _result_points)


func _score() -> Dictionary:
	var seconds := ship.flight_time
	# An unlimited resource cannot be saved, so it scores nothing.
	var fuel := 0.0 if ship.fuel_unlimited else ship.fuel
	var hull := 0.0 if ship.hull_unlimited else ship.health
	var points := Progress.points(fuel, hull, seconds)
	return {
		"points": points,
		"fuel_points": roundi(fuel * Tuning.points_fuel),
		"hull_points": roundi(hull * Tuning.points_hull),
		"time_points": roundi(seconds * Tuning.points_per_second),
		"new_best": level_id != "" and not testing and Progress.record_win(level_id, points, seconds, fuel, hull),
		"has_next": publishing or (level_id != "" and (Progress.next_level(level_id) != "" or _ends_training())),
		"has_par": par > 0,
		"par": par,
		"medal": Progress.medal(points, par),
	}
