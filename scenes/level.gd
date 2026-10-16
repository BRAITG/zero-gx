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
var _done := false


func _ready() -> void:
	for child in get_children():
		if child is Ship: ship = child
		elif child is Goal: goal = child
	assert(ship != null and goal != null, "%s needs one Ship and one Goal child" % name)
	if level_id == "":
		level_id = scene_file_path.get_file().get_basename()
	add_child(Starfield.new())
	hud = Hud.new()
	hud.ship = ship
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
		var number := level_id.get_slice("_", 1).to_int()
		hud.show_intro("Level %d · %s" % [number, title] if number > 0 else title, hint)


func _end_tour() -> void:
	tour = null
	hud.visible = true
	ship.use_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_to_menu()


func _to_menu() -> void:
	if testing:
		get_tree().change_scene_to_node(LevelEditor.create(level_id))
	elif level_id.begins_with(MyLevels.PREFIX):
		get_tree().change_scene_to_node(MyLevelsScreen.new())
	else:
		get_tree().change_scene_to_file(MENU)


## Ends the level once; later calls (a hit and the goal on one frame) are ignored.
func finish(won: bool) -> void:
	if _done:
		return
	_done = true
	ship.thrusting = false
	ship.set_deferred("freeze", true)
	if won:
		Sfx.play("goal")
		if testing:
			MyLevels.mark_completed(level_id)
	hud.show_result(won, _score() if won else {"cause": ship.death_cause})
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
