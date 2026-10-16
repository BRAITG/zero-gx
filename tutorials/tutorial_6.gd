extends "res://scenes/tutorial.gd"
## Training 6: black holes. Lethal to touch, and close in, no engine can pull away.

const CLOSE_CALL := 70.0  # px above the surface where the scripted fall stops, short of the touch

@onready var _hole: GravityBody = find_children("*", "GravityBody", false, false)[0]


func lesson() -> void:
	var start := [ship.global_position, ship.linear_velocity, ship.fuel]
	await say("Black holes pull far harder than planets, and anything that touches one is gone. Don't touch anything: watch your arrow.")
	await until(func() -> bool: return _distance() < 260.0, "Watch the black hole pull you in.")
	ship.invulnerable = true  # the fall below is scripted: it must stop short, whatever the frame rate
	await touch_target(_away, func() -> bool: return _distance() < _hole.radius + CLOSE_CALL, "Too close! Fire away from it: hold the ring!")
	await say("You were about to fall in. This close to a black hole, its pull is stronger than any engine: nothing gets out. Stay well clear of them. We'll pull you back to the start.")
	ship.respawn(start[0], start[1], start[2])
	for i in 2:
		await get_tree().physics_frame  # the respawn lands on the next physics step
	ship.invulnerable = false
	await touch_target(_away, func() -> bool: return _distance() > 900.0, "Push away from it now, while you still can. Hold the ring.")
	await say("Out of its grip. Now go around it, wide of its pull, to the green ring.")


func _distance() -> float:
	return ship.global_position.distance_to(_hole.global_position)


func _away() -> Vector2:
	return ship.global_position - _hole.global_position
