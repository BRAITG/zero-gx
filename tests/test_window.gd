extends "res://tests/test_case.gd"

const MAIN := preload("res://scenes/main.gd")


func test_window_is_720p_at_scale_one() -> void:
	check(MAIN.window_size(1.0, Vector2i(1920, 1080)) == Vector2i(1280, 720), "scale 1: %s" % [MAIN.window_size(1.0, Vector2i(1920, 1080))])


func test_window_doubles_on_a_retina_screen() -> void:
	check(MAIN.window_size(2.0, Vector2i(3024, 1890)) == Vector2i(2560, 1440), "scale 2: %s" % [MAIN.window_size(2.0, Vector2i(3024, 1890))])


func test_window_shrinks_to_fit_ninety_percent_of_the_screen() -> void:
	var size := MAIN.window_size(2.0, Vector2i(1440, 900))
	check(size == Vector2i(1296, 729), "capped to 0.9 x 1440x900 keeping 16:9: %s" % [size])


func test_window_keeps_sixteen_by_nine_within_a_pixel() -> void:
	for case: Array in [[1.0, Vector2i(1920, 1080)], [2.0, Vector2i(3024, 1890)], [2.0, Vector2i(1440, 900)], [1.25, Vector2i(1366, 768)], [3.0, Vector2i(1280, 800)]]:
		var size := MAIN.window_size(case[0], case[1])
		check(absf(size.x * 9.0 - size.y * 16.0) <= 16.0, "16:9 within 1 px for scale %s on %s: %s" % [case[0], case[1], size])
		check(size.x <= case[1].x * 0.9 + 1.0 and size.y <= case[1].y * 0.9 + 1.0, "fits 90%% of %s: %s" % [case[1], size])
