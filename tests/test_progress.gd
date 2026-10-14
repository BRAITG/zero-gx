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


func test_unlock_chain() -> void:
	check(Progress.is_unlocked("level_01"), "level 1 must always be open")
	check(not Progress.is_unlocked("level_02"), "level 2 open before level 1 was won")
	Progress.record_win("level_01", 1000, 10.0)
	check(Progress.is_unlocked("level_02") and not Progress.is_unlocked("level_03"), "winning level 1 must open level 2 only")
	Progress.unlock_all = true
	check(Progress.is_unlocked(Progress.levels()[-1]), "unlock all must open the last level")
	Progress.reset()
	check(Progress.best_points("level_01") == -1, "reset must clear bests")
	check(Progress.unlock_all, "reset must not touch the session unlock switch")
	check(Progress.next_level(Progress.levels()[-1]) == "", "the last level has no next level")
