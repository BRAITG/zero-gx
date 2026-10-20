extends "res://tests/test_case.gd"


func test_blur_follows_speed_up_to_the_limit() -> void:
	check(Starfield.blur(0, false) == 0.0, "at rest there is no blur")
	check(is_equal_approx(Starfield.blur(Tuning.max_speed * 0.5, false), 0.5), "half speed must blur half: %f" % Starfield.blur(Tuning.max_speed * 0.5, false))
	check(Starfield.blur(Tuning.max_speed, false) == 1.0, "the speed limit must blur fully")
	check(Starfield.blur(Tuning.max_speed * 1.5, false) == 1.0, "blur must stop at 1 above the limit")
	check(Starfield.blur(0, true) == 1.0, "a boost blurs fully even from rest")
