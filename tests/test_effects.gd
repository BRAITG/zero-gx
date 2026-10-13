extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"


func ship_at_rest(props: Dictionary = {}) -> Ship:
	return spawn(SHIP, Vector2.ZERO, props)


func test_power_up_scales_thrust_and_cap() -> void:
	var ship := ship_at_rest({"thrusting": true, "aim_point": Vector2(100000, 0)})
	ship.apply_power(Tuning.power_up)
	await frames(30)
	var before := ship.linear_velocity.x
	await frames(30)  # measure a later window: force applies from the step after it is set
	var expected := Tuning.thrust * Tuning.power_up * 0.5
	var gained := ship.linear_velocity.x - before
	check(absf(gained - expected) <= expected * 0.03, "gained %f px/s in 0.5 s, expected %f" % [gained, expected])
	await frames(270)
	var speed := ship.linear_velocity.length()
	check(speed > Tuning.max_speed and speed <= Tuning.max_speed * Tuning.power_up + 1.0, "speed %f, expected above %f up to %f" % [speed, Tuning.max_speed, Tuning.max_speed * Tuning.power_up])


func test_power_expires() -> void:
	Tuning.set_value("effect_seconds", 2.0)
	var ship := ship_at_rest()
	ship.apply_power(1.5)
	await frames(130)
	check(ship.power == 1.0, "power %f after the effect, expected 1" % ship.power)
	check(ship.effect_text() == "", "effect text '%s', expected empty" % ship.effect_text())


func test_new_effect_replaces_old() -> void:
	var ship := ship_at_rest()
	ship.apply_power(1.5)
	await frames(60)
	ship.apply_power(0.6)
	check(ship.power == 0.6, "power %f, expected 0.6" % ship.power)
	await frames(450)
	check(ship.power == 0.6, "power %f at 7.5 s, expected 0.6 (timer restarted)" % ship.power)
	await frames(36)
	check(ship.power == 1.0, "power %f at 8.1 s, expected 1" % ship.power)


func test_boost_on_empty_tank() -> void:
	var ship := ship_at_rest({"fuel": 0.0})
	ship.start_boost()
	check(ship.effect_text() == "Boost", "effect text '%s'" % ship.effect_text())
	await frames(60)
	check(ship.linear_velocity.length() > 300.0, "speed %f after 1 s of boost" % ship.linear_velocity.length())
	check(ship.fuel == 0.0, "boost burned fuel")
	await frames(36)
	check(not ship.boosting, "still boosting after %f s" % Tuning.boost_seconds)
	var speed := ship.linear_velocity.length()
	await frames(30)
	check(absf(ship.linear_velocity.length() - speed) <= 1.0, "speed changed after the boost ended")


func test_boost_turn_rate_limited() -> void:
	var ship := ship_at_rest({"thrusting": true, "aim_point": Vector2(-1000, 0)})
	ship.start_boost()
	var worst := 0.0
	for i in 80:
		await frames(1)
		worst = maxf(worst, absf(ship.angular_velocity))
	check(worst <= Tuning.boost_turn_rate + Tuning.boost_wobble + 0.01, "turned at %f rad/s during a boost" % worst)


func test_dead_ship_ignores_pickups() -> void:
	var ship := ship_at_rest()
	ship.take_damage(Ship.MAX_HEALTH)
	ship.apply_power(1.5)
	ship.start_boost()
	check(ship.power == 1.0, "dead ship took power %f" % ship.power)
	check(not ship.boosting, "dead ship boosting")
