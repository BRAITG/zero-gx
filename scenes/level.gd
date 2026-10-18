class_name Level
extends Node2D
## Root script of every level: the Ship child is point A, the Goal child is point B.

signal finished(won: bool)

const MENU := "res://scenes/main.tscn"

var ship: Ship
var goal: Goal
var hud: Hud
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


func _ready() -> void:
	for child in get_children():
		if child is Ship: ship = child
		elif child is Goal: goal = child
	assert(ship != null and goal != null, "%s needs one Ship and one Goal child" % name)
	if level_id == "":
		level_id = scene_file_path.get_file().get_basename()
	add_child(Starfield.new())
	if level_sha256 != "":
		_recorder = DemoRecorder.new(self)
		demo = _recorder.demo
		add_child(_recorder)
	hud = Hud.new()
	hud.ship = ship
	hud.menu_text = "Edit" if testing else "Menu"
	hud.can_replay = demo != null
	ship.show_velocity = show_velocity or Settings.show_velocity
	hud.goal = goal
	add_child(hud)
	if Tuning.tours and not testing and has_node("Tour") and Progress.best_points(level_id) < 0 and not Progress.toured.has(level_id):
		Progress.toured[level_id] = true
		hud.visible = false
		tour = Tour.new(self)
		tour.finished.connect(_end_tour)
		add_child(tour)
	else:
		_show_intro()
	hud.retry_requested.connect(func(): Progress.open(level_id, testing))
	hud.menu_requested.connect(_to_menu)
	hud.replay_requested.connect(_replay)
	hud.next_requested.connect(func(): Progress.open(Progress.next_level(level_id)))
	goal.reached.connect(finish.bind(true))
	ship.destroyed.connect(_ship_lost)
	ship.stranded.connect(_ship_stranded)


## Losing the ship ends the level; tutorials override these to retry the current step instead.
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
	var number := level_id.get_slice("_", 1).to_int()
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
	leave_to(get_tree(), level_id, testing)


## Where leaving stage `level_id` goes: the editor after a test flight, else the screen it came from.
static func leave_to(tree: SceneTree, level_id: String, testing: bool) -> void:
	if testing:
		tree.change_scene_to_node(LevelEditor.create(level_id))
	elif level_id.begins_with(MyLevels.PREFIX):
		tree.change_scene_to_node(MyLevelsScreen.new())
	elif level_id.begins_with("tutorial_"):
		tree.change_scene_to_node(load("res://scenes/main.gd").menu(true))
	else:
		tree.change_scene_to_file(MENU)


func _replay() -> void:
	get_tree().change_scene_to_node(DemoViewer.create(level_data, demo, leave_to.bind(get_tree(), level_id, testing)))


## Ends the level once; later calls (a hit and the goal on one frame) are ignored.
func finish(won: bool) -> void:
	if _done:
		return
	_done = true
	ship.thrusting = false
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
	if demo and result.get("new_best", false):
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
		"has_next": level_id != "" and Progress.next_level(level_id) != "",
	}
