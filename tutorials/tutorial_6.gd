extends "res://scenes/tutorial.gd"
## Training 6: black holes. Lethal to touch, and close in, no engine can pull away.

@onready var _hole: Node2D = find_children("*", "GravityBody", false, false)[0]
var _start := []  # [position, velocity, fuel] as the stage began
var _doomed := false  # the ship is meant to fall in; its loss restarts the stage, not the step
var _fell_in := false


func lesson() -> void:
	_start = [ship.global_position, ship.linear_velocity, ship.fuel]
	await say("Black holes pull far harder than planets, and anything that touches one is gone. Don't touch anything: watch your arrow.")
	await until(func() -> bool: return _distance() < 260.0, "Watch the black hole pull you in.")
	_doomed = true
	await touch_target(_away, func() -> bool: return _fell_in, "Too close! Fire away from it: hold the ring!")
	await say("Too late. This close to a black hole, its pull is stronger than any engine: nothing gets out. You are back at the start. Stay well clear of them.")
	await touch_target(_away, func() -> bool: return _distance() > 900.0, "Push away from it now, while you still can. Hold the ring.")
	await say("Out of its grip. Now go around it, wide of its pull, to the green ring.")


func _distance() -> float:
	return ship.global_position.distance_to(_hole.global_position)


func _away() -> Vector2:
	return ship.global_position - _hole.global_position


func _ship_lost() -> void:
	if not _doomed:
		super._ship_lost()
		return
	_doomed = false
	await get_tree().create_timer(1.2, false, true).timeout  # let the player see the ship break up
	ship.respawn(_start[0], _start[1], _start[2])
	for i in 2:
		await get_tree().physics_frame  # the respawn lands on the next physics step
	_fell_in = true
