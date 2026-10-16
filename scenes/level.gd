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
## Progress key; defaults to the scene file's stem. Empty (a level built in code) saves nothing.
var level_id := ""
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
	hud.goal = goal
	add_child(hud)
	if Tuning.tours and has_node("Tour") and Progress.best_points(level_id) < 0 and not Progress.toured.has(level_id):
		Progress.toured[level_id] = true
		hud.visible = false
		tour = Tour.new(self)
		tour.finished.connect(_end_tour)
		add_child(tour)
	elif title != "":
		var number := level_id.get_slice("_", 1).to_int()
		hud.show_intro("Level %d · %s" % [number, title] if number > 0 else title, hint)
	hud.retry_requested.connect(func(): get_tree().reload_current_scene())
	hud.menu_requested.connect(_to_menu)
	hud.next_requested.connect(func(): get_tree().change_scene_to_file("res://levels/%s.tscn" % Progress.next_level(level_id)))
	goal.reached.connect(finish.bind(true))
	ship.destroyed.connect(finish.bind(false))
	ship.stranded.connect(func(): ship.death_cause = "Out of fuel"; finish(false))


func _end_tour() -> void:
	tour = null
	hud.visible = true
	ship.use_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_to_menu()


func _to_menu() -> void:
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
	hud.show_result(won, _score() if won else {"cause": ship.death_cause})
	finished.emit(won)


func _score() -> Dictionary:
	var seconds := ship.flight_time
	var points := Progress.points(ship.fuel, ship.health, seconds)
	return {
		"points": points,
		"fuel_points": roundi(ship.fuel * Tuning.points_fuel),
		"hull_points": roundi(ship.health * Tuning.points_hull),
		"time_points": roundi(seconds * Tuning.points_per_second),
		"new_best": level_id != "" and Progress.record_win(level_id, points, seconds),
		"has_next": level_id != "" and Progress.next_level(level_id) != "",
	}
