extends "res://scenes/tutorial.gd"
## Training 6: black holes. Lethal to touch, and close in, no engine can pull away.

const CLOSE_CALL := 70.0  # px above the surface where the scripted fall stops, short of the touch
const LATE := 0.05  # s past the tipping point the turned-around ship is: it loses, but slowly
const AROUND := Vector2(900, -1000)  # a point well above the hole to steer for after the rescue

@onready var _hole: GravityBody = find_children("*", "GravityBody", false, false)[0]


func lesson() -> void:
	var start: Vector2 = ship.global_position  # outside the hole's reach: safe to rest at
	await say("Black holes pull far harder than planets, and anything that touches one is gone. Don't touch anything: watch your arrow.")
	# Pause so the tipping point falls inside the half turn to face away: once turned, it's too late.
	await until(func() -> bool: return _doomed_after(PI / Tuning.turn_rate - LATE), "Watch the black hole pull you in.")
	ship.invulnerable = true  # the fall below must end in the rescue, never in a death
	var falling := for_seconds(8.0)  # a backstop, should the ship ever hang at the tipping point
	await touch_target(_away, func() -> bool: return not waiting() and (falling.call() or _distance() < _hole.radius + CLOSE_CALL),
		"Too close! Turn your engine around: tap and hold the ring behind you!", true)
	await say("Your engine can't win: this close to a black hole, its pull is stronger than any engine, and nothing gets out. Stay well clear of them. Hold on, we'll beam you back.")
	await beam_to(start)
	ship.respawn(start, Vector2.ZERO, Ship.MAX_FUEL)
	Sfx.play("power_up")
	for i in 2:
		await get_tree().physics_frame  # the respawn lands on the next physics step
	ship.invulnerable = false
	await touch_target(func() -> Vector2: return AROUND - ship.global_position, held(1.0), "Now fly up and around it, wide of its pull. Hold the ring.")
	await say("Keep wide of the black hole and fly on to the green ring.")


## Whether the ship, coasting `seconds` more and then thrusting straight away from the hole at
## full power, would still fall in. A radial fall: the thrust works like a potential -a·r on top
## of gravity's -mu/r, so the ship escapes only while its energy stays below the peak of
## -mu/r - a·r, which sits where gravity equals thrust.
func _doomed_after(seconds: float) -> bool:
	var mu: float = _hole._surface_pull() * _hole.radius * _hole.radius
	var a := Tuning.thrust
	var r := _distance()
	var v_in := -ship.linear_velocity.dot(_away().normalized())
	var g := mu / (r * r)
	r -= v_in * seconds + 0.5 * g * seconds * seconds
	v_in += g * seconds
	var balance := sqrt(mu / a)  # where gravity equals thrust
	return r <= balance or 0.5 * v_in * v_in - mu / r - a * r >= -2.0 * sqrt(mu * a)


func _distance() -> float:
	return ship.global_position.distance_to(_hole.global_position)


func _away() -> Vector2:
	return ship.global_position - _hole.global_position
