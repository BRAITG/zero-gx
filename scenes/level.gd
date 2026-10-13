class_name Level
extends Node2D
## Root script of every level: the Ship child is point A, the Goal child is point B.

signal finished(won: bool)

const MENU := "res://scenes/main.tscn"

var ship: Ship
var goal: Goal
var hud: Hud
var _done := false


func _ready() -> void:
	for child in get_children():
		if child is Ship: ship = child
		elif child is Goal: goal = child
	assert(ship != null and goal != null, "%s needs one Ship and one Goal child" % name)
	hud = Hud.new()
	hud.ship = ship
	add_child(hud)
	hud.retry_requested.connect(func(): get_tree().reload_current_scene())
	hud.menu_requested.connect(_to_menu)
	goal.reached.connect(finish.bind(true))
	ship.destroyed.connect(finish.bind(false))
	ship.stranded.connect(finish.bind(false))


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
	hud.show_result(won)
	finished.emit(won)
