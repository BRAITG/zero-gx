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


func test_test_flight_leaves_through_edit() -> void:
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.new().data)
	var lvl := Progress.build(id, true)
	world.add_child(lvl)
	await frames(1)
	var labels: Array = lvl.hud.find_children("*", "Button", true, false).map(func(b: Button): return b.text)
	check("Edit" in labels and not "Menu" in labels, "test flight buttons: %s" % [labels])


func test_official_level_round_trips_through_import_and_export() -> void:
	var source := "res://levels/level_05.json"
	var original := FileAccess.get_file_as_string(source)
	check(MyLevels.import_file(source).is_empty(), "official level must import")
	var ids := MyLevels.ids()
	check(ids.size() == 1 and ids[0].begins_with(MyLevels.PREFIX), "one new user level: %s" % ids)
	var out := "user://test_export.json"
	check(MyLevels.export_file(ids[0], out) == OK, "export must succeed")
	check(FileAccess.get_file_as_string(out) == original, "export must be byte-identical to the official file")
	check(FileAccess.get_file_as_string(source) == original, "source untouched")
	DirAccess.remove_absolute(out)


func test_import_never_overwrites() -> void:
	MyLevels.import_file("res://levels/level_05.json")
	MyLevels.import_file("res://levels/level_05.json")
	check(MyLevels.ids().size() == 2, "two imports, two levels: %s" % MyLevels.ids())


func test_import_rejects_bad_files() -> void:
	var cases := {
		"user://bad_empty.json": "",
		"user://bad_text.json": "not json",
		"user://bad_array.json": "[1, 2]",
		"user://bad_format.json": '{"format": "other-game", "version": 1}',
		"user://bad_version.json": '{"format": "zero-gx-level", "version": 999}',
		"user://bad_bare.json": '{"format": "zero-gx-level", "version": 1}',
		"user://bad_format_type.json": '{"format": 5, "version": 1}',
		"user://bad_version_type.json": '{"format": "zero-gx-level", "version": "1"}',
		"user://bad_title.json": '{"format": "zero-gx-level", "version": 1, "title": 5, "ship": {"position": [0, 0]}, "goal": {"position": [2000, 0]}}',
		"user://bad_wall.json": '{"format": "zero-gx-level", "version": 1, "title": "x", "ship": {"position": [0, 0]}, "goal": {"position": [2000, 0]}, "walls": [{"kind": "green", "points": [[0, 0], [1, 1]]}]}',
		"user://bad_big.json": "x".repeat(LevelFormat.MAX_BYTES + 1),
	}
	for path: String in cases:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(cases[path])
		f.close()
		check(not MyLevels.import_file(path).is_empty(), "%s must be rejected" % path)
		DirAccess.remove_absolute(path)
	check(MyLevels.ids().is_empty(), "nothing saved: %s" % MyLevels.ids())


func test_import_accepts_an_unfinished_draft() -> void:
	var draft := LevelFormat.read("res://levels/level_05.json")
	draft.title = ""  # fails validation, as a half-built level may
	LevelFormat.write("user://draft.json", draft)
	check(MyLevels.import_file("user://draft.json").is_empty(), "a draft must import")
	check(MyLevels.ids().size() == 1 and not LevelFormat.validate(MyLevels.load_level(MyLevels.ids()[0])).is_empty(), "saved as the invalid draft it is")
	DirAccess.remove_absolute("user://draft.json")


func test_import_reads_gzip_whatever_the_name() -> void:
	var path := "user://disguised.json"  # a content:// path from Android's picker has no extension to go by
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	file.store_string(JSON.stringify(LevelFormat.read("res://levels/level_05.json")))
	file.close()
	check(MyLevels.import_file(path).is_empty(), "a gzip level named .json must import")
	check(MyLevels.ids().size() == 1 and MyLevels.load_level(MyLevels.ids()[0]).get("title") == "Swing", "imported level: %s" % [MyLevels.ids()])
	DirAccess.remove_absolute(path)


func test_export_adds_json_extension() -> void:
	MyLevels.import_file("res://levels/level_05.json")
	check(MyLevels.export_file(MyLevels.ids()[0], "user://my level") == OK, "export")
	check(FileAccess.file_exists("user://my level.json"), "`.json` appended")
	DirAccess.remove_absolute("user://my level.json")


func test_my_levels_screen_offers_import_and_export() -> void:
	MyLevels.save(MyLevels.new_id(), LevelDoc.new().data)
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	var labels: Array = screen.find_children("*", "Button", true, false).map(func(b: Button): return b.text)
	check("Import" in labels and "Export" in labels, "buttons: %s" % [labels])
	screen.queue_free()


func test_export_dialog_suggests_a_safe_file_name() -> void:
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(1)
	screen._export("user_x", "a/b:c?")
	var dialogs := screen.find_children("*", "FileDialog", true, false)
	check(dialogs.size() == 1 and dialogs[0].current_file == "a_b_c_.json", "suggested name: %s" % [dialogs.map(func(d: FileDialog) -> String: return d.current_file)])
