extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"


func test_reset_restores_defaults() -> void:
	for key in Tuning.RANGES:
		Tuning.set_value(key, Tuning.RANGES[key][1])
	Tuning.reset()
	for key in Tuning.DEFAULTS:
		check(Tuning.get(key) == Tuning.DEFAULTS[key], "%s = %s after reset, expected %s" % [key, Tuning.get(key), Tuning.DEFAULTS[key]])


func test_speed_capped_at_max_speed() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"thrusting": true, "aim_point": Vector2(100000, 0)})
	await frames(300)
	check(ship.linear_velocity.length() <= Tuning.max_speed + 1.0, "speed %f above cap %f" % [ship.linear_velocity.length(), Tuning.max_speed])


func test_overspeed_eases_down() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"linear_velocity": Vector2(1200, 0)})
	var last := 1200.0
	var worst := 0.0
	for i in 120:
		await frames(1)
		var speed: float = ship.linear_velocity.length()
		worst = maxf(worst, last - speed)
		last = speed
	check(worst <= 400.0 / 60.0 + 0.5, "speed dropped %f in one step" % worst)
	check(absf(last - Tuning.max_speed) <= 1.0, "speed %f after 2 s, expected %f" % [last, Tuning.max_speed])
