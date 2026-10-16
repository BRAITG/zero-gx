extends "res://tests/test_case.gd"


func test_save_load_and_delete() -> void:
	var id := MyLevels.new_id()
	var doc := LevelDoc.new()
	doc.place("planet", Vector2(1000, 400))
	MyLevels.save(id, doc.data)
	check(MyLevels.ids() == PackedStringArray([id]), "listed: %s" % MyLevels.ids())
	var loaded := MyLevels.load_level(id)
	check(LevelDoc._v(loaded.bodies[0].position) == Vector2(1000, 400) and loaded.title == doc.data.title, "round trip: %s" % loaded)
	var level := Progress.build(id)
	check(level.level_id == id and level.find_children("*", "GravityBody", true, false).size() == 1, "a user level must build with its planet")
	level.free()
	MyLevels.delete(id)
	check(MyLevels.ids().is_empty(), "deleted")


func test_completion_lasts_until_an_edit() -> void:
	var id := MyLevels.new_id()
	var doc := LevelDoc.new()
	MyLevels.save(id, doc.data)
	check(not MyLevels.is_completed(id), "new levels are not completed")
	MyLevels.mark_completed(id)
	check(MyLevels.is_completed(id), "finished in Test: completed")
	doc.place("thrust_up", Vector2(1000, 0))
	MyLevels.save(id, doc.data)
	check(not MyLevels.is_completed(id), "an edit must clear the completion")


func test_a_won_test_flight_completes_without_a_score() -> void:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.new().data)
	var lvl := Progress.build(id, true)
	world.add_child(lvl)
	await frames(2)
	lvl.finish(true)
	await frames(2)
	check(MyLevels.is_completed(id), "finishing a test flight must complete the level")
	check(Progress.best_points(id) < 0, "a test flight must not record a best score")
