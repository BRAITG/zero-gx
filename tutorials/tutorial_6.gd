extends "res://scenes/tutorial.gd"
## Training 6: black holes. Lethal to touch, and close in, no engine can pull away.

const CLOSE_CALL := 70.0  # px above the surface where the scripted fall stops, short of the touch
const BITS := 48  # pixels the ship breaks into for the rescue
const BIT_SIZE := 4.0
const SCATTER := 0.35  # s the pixels burst apart before they travel
const TRAVEL := 1.2  # s for the pixels to stream back to the start

@onready var _hole: GravityBody = find_children("*", "GravityBody", false, false)[0]


func lesson() -> void:
	var start := [ship.global_position, ship.linear_velocity, ship.fuel]
	await say("Black holes pull far harder than planets, and anything that touches one is gone. Don't touch anything: watch your arrow.")
	await until(func() -> bool: return _distance() < 260.0, "Watch the black hole pull you in.")
	ship.invulnerable = true  # the fall below is scripted: it must stop short, whatever the frame rate
	await touch_target(_away, func() -> bool: return _distance() < _hole.radius + CLOSE_CALL, "Too close! Fire away from it: hold the ring!")
	await say("You were about to fall in. This close to a black hole, its pull is stronger than any engine: nothing gets out. Stay well clear of them. We'll pull you back to the start.")
	await _beam_to(start[0])
	ship.respawn(start[0], start[1], start[2])
	Sfx.play("power_up")
	for i in 2:
		await get_tree().physics_frame  # the respawn lands on the next physics step
	ship.invulnerable = false
	await touch_target(_away, func() -> bool: return _distance() > 900.0, "Push away from it now, while you still can. Hold the ring.")
	await say("Out of its grip. Now go around it, wide of its pull, to the green ring.")


func _distance() -> float:
	return ship.global_position.distance_to(_hole.global_position)


func _away() -> Vector2:
	return ship.global_position - _hole.global_position


## The rescue: the ship breaks into pixels that stream to `at` and rebuild it there. The ship
## stays hidden and frozen meanwhile; it rides along with the pixels so the camera follows.
func _beam_to(at: Vector2) -> void:
	var from := ship.global_position
	ship.freeze = true
	ship.hide()
	Sfx.play("power_down")
	var tween := create_tween().set_parallel()
	tween.tween_property(ship, "global_position", at, TRAVEL).set_delay(SCATTER).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in BITS:
		var bit := ColorRect.new()
		bit.size = Vector2.ONE * BIT_SIZE
		bit.color = Ship.HULL if i % 3 else Ship.HULL_EDGE
		bit.z_index = 20
		var home := Vector2(randf_range(-1.0, 1.4), randf_range(-0.8, 0.8)).rotated(ship.global_rotation) * Ship.RADIUS  # its spot in the ship
		bit.position = from + home
		add_child(bit)
		var burst := from + home * 2.5 + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0)
		tween.tween_property(bit, "position", burst, SCATTER).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(bit, "position", at + home, TRAVEL * randf_range(0.7, 1.0)).set_delay(SCATTER + randf() * TRAVEL * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(bit.queue_free).set_delay(SCATTER + TRAVEL * 1.3)
	await tween.finished
