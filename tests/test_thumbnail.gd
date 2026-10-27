extends "res://tests/test_case.gd"


func test_every_official_sketch_draws() -> void:
	for id in Array(Progress.levels()) + Array(Progress.trainings()):
		var dir: String = Progress.TUTORIALS_DIR if id.begins_with("tutorial_") else Progress.LEVELS_DIR
		var thumbnail := Thumbnail.of_sketch(LevelFormat.sketch(LevelFormat.read(dir + id + ".json")))
		thumbnail.size = Thumbnail.CANVAS
		world.add_child(thumbnail)
		await frames(1)
		check(thumbnail.stage_id == "" and not thumbnail.sketch.is_empty(), "%s sketch thumbnail" % id)
		thumbnail.free()


func test_sketch_thumbnail_survives_bad_input() -> void:
	var mistyped := {
		"bounds": [0, 0, 100, 50], "ship": "here", "goal": [50], "asteroids": 5,
		"walls": [5, {"kind": "blue", "points": [[0, 0], "x", [100, 50]], "closed": "yes"}, {"kind": "red", "points": [[0, 0], [10, 10]], "closed": 1}],
		"bodies": [{"kind": "planet", "position": [10, 10], "radius": "big"}],
		"pickups": [5, {"kind": "thrust_sideways", "position": [1, 1]}],
	}
	# A star's flares are drawn per 24 canvas units of its radius, and a tiny box scales a small radius up: both must stay cheap.
	var star := [{"kind": "star", "position": [0, 0], "radius": 1e9}]
	var huge_radius := {"bounds": [0, 0, 1, 1], "bodies": star}
	var tiny_box := {"bounds": [0, 0, 1e-300, 1e-300], "bodies": star}
	var started := Time.get_ticks_msec()
	for bad in [null, {}, {"bounds": "x"}, {"bounds": [0, 0, 0, 0], "walls": [{"kind": 3, "points": "no"}]}, "text", mistyped, huge_radius, tiny_box, {"bounds": [0, 0, 100, 50], "par": "x"}]:
		var thumbnail := Thumbnail.of_sketch(bad)
		thumbnail.size = Thumbnail.CANVAS
		world.add_child(thumbnail)
		await frames(1)
		thumbnail.free()
	check(Time.get_ticks_msec() - started < 2000, "hostile sketches must draw at once")
	var refused := Thumbnail.of_sketch(tiny_box)
	check(refused.sketch.is_empty(), "bounds under 1 are refused")
	refused.free()
	var drawn := Thumbnail.of_sketch(huge_radius)
	check(not drawn.sketch.is_empty(), "bounds of exactly 1 are drawn")
	drawn.free()
	check(true, "no script error above")  # run_tests.gd fails the test on any logged script error


func test_sketch_bounds_fill_the_canvas_inside_its_margin() -> void:
	var thumbnail := Thumbnail.of_sketch({"bounds": [-500, 0, 1000, 500]})
	world.add_child(thumbnail)
	var low: Vector2 = thumbnail._fit([-500, 0])
	var high: Vector2 = thumbnail._fit([500, 500])
	check(low.is_equal_approx(Vector2(12, 16)), "the box's corner must sit at the margin: %s" % low)
	check(high.is_equal_approx(Vector2(308, 164)), "the opposite corner must sit at the opposite margin: %s" % high)
