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
	for bad in [null, {}, {"bounds": "x"}, {"bounds": [0, 0, 0, 0], "walls": [{"kind": 3, "points": "no"}]}, "text"]:
		var thumbnail := Thumbnail.of_sketch(bad)
		thumbnail.size = Thumbnail.CANVAS
		world.add_child(thumbnail)
		await frames(1)
		thumbnail.free()
	check(true, "no script error above")  # run_tests.gd fails the test on any logged script error


func test_sketch_bounds_fill_the_canvas_inside_its_margin() -> void:
	var thumbnail := Thumbnail.of_sketch({"bounds": [-500, 0, 1000, 500]})
	world.add_child(thumbnail)
	var low: Vector2 = thumbnail._fit([-500, 0])
	var high: Vector2 = thumbnail._fit([500, 500])
	check(low.is_equal_approx(Vector2(12, 16)), "the box's corner must sit at the margin: %s" % low)
	check(high.is_equal_approx(Vector2(308, 164)), "the opposite corner must sit at the opposite margin: %s" % high)
