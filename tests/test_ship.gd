extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"


func counter(sig: Signal) -> Dictionary:
	var hits := {"count": 0, "frame": -1}
	sig.connect(func(): hits.count += 1)
	return hits


func test_fuel_burns_at_rate() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"thrusting": true, "aim_point": Vector2(1000, 0)})
	await frames(60)
	check(abs(ship.fuel - 90.0) < 0.5, "fuel after 1 s of thrust = %f, expected 90" % ship.fuel)
	check(ship.linear_velocity.x > 0, "thrust must accelerate toward the aim: %s" % ship.linear_velocity)


func test_no_thrust_without_fuel() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"thrusting": true, "aim_point": Vector2(1000, 0), "fuel": 0.0})
	await frames(30)
	check(ship.linear_velocity.length() < 0.01, "moved without fuel: %s" % ship.linear_velocity)


func test_empty_tank_times_out() -> void:
	# Moving or not, an empty ship has Ship.EMPTY_TIMEOUT (5 s) left.
	var ship = spawn(SHIP, Vector2.ZERO, {"fuel": 0.0, "linear_velocity": Vector2(100, 0)})
	var stranded := counter(ship.stranded)
	await frames(60)
	check(absf(ship.empty_seconds_left() - 4.0) < 0.05, "%f s left after 1 s, expected 4" % ship.empty_seconds_left())
	await frames(230)
	check(stranded.count == 0, "timed out before 5 s")
	await frames(20)
	check(stranded.count == 1, "stranded emitted %d times by 5.2 s, expected 1" % stranded.count)


func test_no_countdown_with_fuel() -> void:
	var ship = spawn(SHIP, Vector2.ZERO)
	var stranded := counter(ship.stranded)
	await frames(400)
	check(stranded.count == 0 and ship.empty_seconds_left() < 0.0, "countdown ran with fuel in the tank")


func test_boost_pauses_empty_countdown() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"fuel": 0.0})
	var stranded := counter(ship.stranded)
	ship.start_boost()  # 1.5 s on which the countdown must not run
	await frames(380)
	check(stranded.count == 0, "timed out at 6.3 s despite a 1.5 s boost")
	await frames(20)
	check(stranded.count == 1, "not stranded by 6.7 s")


func test_turns_toward_aim() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"aim_point": Vector2(0, 1000), "thrusting": true})
	await frames(30)
	check(abs(wrapf(ship.rotation - PI / 2, -PI, PI)) < 0.05, "rotation %f, expected PI/2" % ship.rotation)


func test_coasting_holds_heading() -> void:
	# Released finger: the old aim point is now behind the ship, which must not turn back to it.
	var ship = spawn(SHIP, Vector2.ZERO, {"aim_point": Vector2(100, 0), "linear_velocity": Vector2(300, 0)})
	await frames(90)
	check(absf(ship.rotation) < 0.01, "rotation %f while coasting, expected 0" % ship.rotation)


func test_destroyed_once() -> void:
	var ship = spawn(SHIP, Vector2.ZERO)
	var destroyed := counter(ship.destroyed)
	ship.take_damage(60)
	ship.take_damage(60)
	check(ship.health == 0.0, "health %f, expected 0" % ship.health)
	check(destroyed.count == 1, "destroyed emitted %d times" % destroyed.count)


func test_held_finger_keeps_steering_as_the_camera_follows() -> void:
	var ship = spawn(SHIP, Vector2.ZERO)
	await frames(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(940, 360)  # Right of screen centre; the finger then stays still.
	ship._unhandled_input(press)
	await frames(150)
	check(ship.position.x > 400, "ship should keep flying right, at %s" % ship.position)
	check(abs(wrapf(ship.rotation, -PI, PI)) < 0.3, "ship turned to %f rad instead of following the held finger" % ship.rotation)


func test_engine_waits_until_aligned() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"thrusting": true, "aim_point": Vector2(-1000, 0)})
	await frames(6)  # a 180° turn at 15 rad/s takes about 13 frames
	check(ship.fuel == Ship.MAX_FUEL and ship.linear_velocity.length() < 0.01, "engine fired while still turning (fuel %f, v %s)" % [ship.fuel, ship.linear_velocity])
	await frames(30)
	check(ship.linear_velocity.x < -50.0 and ship.fuel < Ship.MAX_FUEL, "no thrust after aligning: v %s" % ship.linear_velocity)


func test_engine_stays_on_while_dragging() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"thrusting": true, "aim_point": Vector2(1000, 0)})
	await frames(10)
	check(ship.firing, "engine should fire when the press starts aligned")
	ship.aim_point = Vector2(-1000, 0)  # the finger swings behind the ship without lifting
	for i in 8:
		await frames(1)
		check(ship.firing, "engine cut out on frame %d of a drag (rotation %f)" % [i, ship.rotation])
	ship.thrusting = false
	await frames(2)
	ship.rotation = 0.0
	ship.angular_velocity = 0.0
	ship.thrusting = true  # a new press behind the ship must wait for the turn again
	await frames(2)
	check(not ship.firing, "a new press must not fire before the nose catches up")


func test_shake_kicks_then_settles() -> void:
	var ship = spawn(SHIP, Vector2.ZERO)
	var camera: Camera2D = ship.find_children("*", "Camera2D", true, false)[0]
	await frames(2)
	ship.shake(1.0)
	var widest := 0.0
	for i in 5:  # the jitter is random each frame, so look at a few
		await frames(1)
		widest = maxf(widest, camera.offset.length())
	check(widest > 4.0, "shake moved the camera only %f px" % widest)
	await frames(60)
	check(camera.offset.length() < 0.5, "camera still shaking after 1 s: %s" % camera.offset)
