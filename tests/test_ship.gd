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


func test_coasting_on_empty_is_not_stranded() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"fuel": 0.0, "linear_velocity": Vector2(100, 0)})
	var stranded := counter(ship.stranded)
	await frames(180)
	check(stranded.count == 0, "a coasting ship is not stranded")


func test_stranded_when_still_on_empty() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"fuel": 0.0})
	var stranded := counter(ship.stranded)
	await frames(110)
	check(stranded.count == 0, "stranded too early (before 2 s)")
	await frames(20)
	check(stranded.count == 1, "stranded emitted %d times by 2.2 s, expected 1" % stranded.count)


func test_turns_toward_aim() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"aim_point": Vector2(0, 1000)})
	await frames(30)
	check(abs(wrapf(ship.rotation - PI / 2, -PI, PI)) < 0.05, "rotation %f, expected PI/2" % ship.rotation)


func test_destroyed_once() -> void:
	var ship = spawn(SHIP, Vector2.ZERO)
	var destroyed := counter(ship.destroyed)
	ship.take_damage(60)
	ship.take_damage(60)
	check(ship.health == 0.0, "health %f, expected 0" % ship.health)
	check(destroyed.count == 1, "destroyed emitted %d times" % destroyed.count)
