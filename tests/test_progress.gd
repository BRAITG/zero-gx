extends "res://tests/test_case.gd"


func test_points_formula() -> void:
	check(Progress.points(40, 80, 30) == 1780, "example run scored %d, expected 1780" % Progress.points(40, 80, 30))
	check(Progress.points(0, 1, 10000) == Progress.MIN_POINTS, "points must not drop below %d" % Progress.MIN_POINTS)


func test_record_and_reload() -> void:
	check(Progress.record_win("level_01", 1500, 30.0), "a first win must be a new best")
	Progress.load_file()  # read back what was saved
	check(Progress.best_points("level_01") == 1500, "best %d after reload, expected 1500" % Progress.best_points("level_01"))
	check(is_equal_approx(Progress.best_time("level_01"), 30.0), "best time %f after reload" % Progress.best_time("level_01"))


func test_lower_score_keeps_best() -> void:
	Progress.record_win("level_01", 1500, 30.0)
	check(not Progress.record_win("level_01", 1200, 20.0), "a lower score must not be a new best")
	check(Progress.best_points("level_01") == 1500, "best %d, expected 1500" % Progress.best_points("level_01"))


func test_corrupt_file_is_no_progress() -> void:
	var file := FileAccess.open(Progress.path, FileAccess.WRITE)
	file.store_string("[level_01\nbest_points = = {")
	file.close()
	Progress.load_file()
	check(Progress.best_points("level_01") == -1, "a corrupt file must mean no progress")
	check(Progress.is_unlocked("level_01") and not Progress.is_unlocked("level_02"), "only level 1 open after a corrupt file")


func test_training_and_levels_unlock_separately() -> void:
	var trainings := Progress.trainings()
	var levels := Progress.levels()
	check(Progress.is_unlocked("tutorial_1") and Progress.is_unlocked("level_01"), "each track's first stage must always be open")
	check(not Progress.is_unlocked("tutorial_2") and not Progress.is_unlocked("level_02"), "second stages open before any win")
	Progress.record_win("tutorial_1", 1000, 10.0)
	check(Progress.is_unlocked("tutorial_2") and not Progress.is_unlocked("tutorial_3"), "winning training 1 must open training 2 only")
	check(not Progress.is_unlocked("level_02"), "training wins must not open levels")
	Progress.record_win("level_01", 1000, 10.0)
	check(Progress.is_unlocked("level_02") and not Progress.is_unlocked("tutorial_3"), "level wins open levels only")
	check(Progress.next_level(trainings[-1]) == "", "the last training has no next stage")
	check(Progress.next_level("level_01") == "level_02" and Progress.next_level(levels[-1]) == "", "levels follow each other, then end")
	Progress.unlock_all = true
	check(Progress.is_unlocked(levels[-1]) and Progress.is_unlocked(trainings[-1]), "unlock all must open every stage")
	Progress.reset()
	check(Progress.best_points("tutorial_1") == -1, "reset must clear bests")
	check(Progress.unlock_all, "reset must not touch the session unlock switch")
