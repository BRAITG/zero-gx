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
	hud.next_requested.connect(_next)
	goal.reached.connect(finish.bind(true))
	ship.destroyed.connect(_ship_lost)
	ship.stranded.connect(_ship_stranded)


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
		hud.show_intro(display_name(), hint)


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
		_to_menu()


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
	elif level_id.begins_with("tutorial_"):
		tree.change_scene_to_node(load("res://scenes/main.gd").menu(true))
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
	hud.show_result(won, result)
	finished.emit(won)


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
		"new_best": level_id != "" and not testing and Progress.record_win(level_id, points, seconds),
		"has_next": publishing or (level_id != "" and (Progress.next_level(level_id) != "" or _ends_training())),
	}
