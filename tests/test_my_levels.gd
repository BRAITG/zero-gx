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


func test_a_won_publish_flight_is_a_test_flight_that_leaves_to_my_levels() -> void:
	Community.platform = FakePlatform.new()
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.new().data)
	var lvl := Progress.build(id, true, true)
	world.add_child(lvl)
	await frames(2)
	lvl.finish(true)
	await frames(2)
	check(MyLevels.is_completed(id) and MyLevels.demo(id) != null, "a publish flight keeps the test recording and completion")
	check(Progress.best_points(id) < 0, "a publish flight records no score")
	var shown: Array = lvl.hud.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)
	check("Publish" in shown and "Menu" in shown and not "Edit" in shown, "publish flight result buttons: %s" % [shown])
	lvl.hud.menu_requested.emit()
	await frames(2)
	var scene := tree.current_scene
	check(scene is MyLevelsScreen, "leaving a publish flight must return to My levels, not the editor: %s" % scene)
	if scene != null:
		scene.free()
		tree.current_scene = null


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


func test_an_invalid_draft_says_why_play_is_off() -> void:
	var draft := LevelFormat.read("res://levels/level_05.json")
	draft.title = ""  # fails validation, as a half-built level may
	MyLevels.save(MyLevels.new_id(), draft)
	var problems := LevelFormat.validate(draft)
	check(not problems.is_empty(), "control: the draft is invalid")
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	var plays: Array = screen.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Play")
	check(plays.size() == 1 and plays[0].disabled, "Play is off for the invalid draft")
	var reasons: Array = screen.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text.contains(problems[0]))
	check(not reasons.is_empty(), "the first problem is shown beside Play: %s" % [problems[0]])
	screen.queue_free()


func test_imported_invalid_level_shows_its_thumbnail_and_keeps_play_disabled() -> void:
	var draft := LevelFormat.read("res://levels/level_05.json")
	draft.title = ""
	var source := "user://invalid_thumbnail.json"
	LevelFormat.write(source, draft)
	var errors := MyLevels.import_file(source)
	DirAccess.remove_absolute(source)
	check(errors.is_empty(), "the invalid draft must import: %s" % [errors])
	if not errors.is_empty():
		return
	var id: String = MyLevels.ids()[0]
	var saved: Dictionary = MyLevels.load_level(id)
	var screen := MyLevelsScreen.new()
	world.add_child(screen)
	await frames(2)
	var thumbnails: Array = screen.find_children("*", "Thumbnail", true, false)
	check(thumbnails.size() == 1, "the imported level has a thumbnail: %d" % thumbnails.size())
	if thumbnails.size() == 1:
		var thumbnail: Thumbnail = thumbnails[0]
		check(thumbnail.sketch == LevelFormat.sketch(saved), "the thumbnail uses the imported level's saved sketch")
		check(thumbnail.custom_minimum_size.is_equal_approx(Vector2(128, 72)), "thumbnail slot is 128 × 72: %s" % thumbnail.custom_minimum_size)
		check(is_equal_approx(thumbnail.size.x / thumbnail.size.y, 16.0 / 9.0), "thumbnail stays 16:9: %s" % thumbnail.size)
		check(thumbnail.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the thumbnail ignores the mouse")
	var plays: Array = screen.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Play")
	check(plays.size() == 1 and plays[0].disabled, "Play stays off for the invalid imported level")
	var warnings: Array = screen.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.text.begins_with("⚠ Cannot play:"))
	check(warnings.size() == 1, "the invalid-level warning stays in the card")
	if thumbnails.size() == 1 and warnings.size() == 1:
		check(warnings[0].get_global_rect().position.y >= thumbnails[0].get_parent().get_global_rect().end.y, "the warning stays below the card's thumbnail and actions")
	screen.queue_free()
	MyLevels.delete(id)


func test_my_level_actions_wrap_inside_a_narrow_window_and_title_ellipsises() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	world.add_child(viewport)
	var data: Dictionary = LevelFormat.read("res://levels/level_05.json")
	var long_title := "A very long level title ".repeat(20)
	data.title = long_title
	var id := MyLevels.new_id()
	MyLevels.save(id, data)
	var demo := Demo.new()
	demo.add_frame({"position": Vector2(100, 100), "rotation": 0.0, "firing": false, "fuel": 10.0, "hull": 10.0}, {})
	demo.level_sha256 = LevelFormat.sha256(data)
	MyLevels.save_demo(id, demo)
	var screen := MyLevelsScreen.new()
	viewport.add_child(screen)
	await frames(2)
	var expected_actions := ["Edit", "Watch", "Play", "Export", "Delete"]
	var buttons: Array = screen.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text in expected_actions)
	var bounds := Rect2(Vector2.ZERO, viewport.size)
	check(buttons.size() == expected_actions.size(), "all level actions are shown: %s" % [buttons.map(func(button: Button) -> String: return button.text)])
	var first_y := -1.0
	var wraps := false
	for button: Button in buttons:
		var rect := button.get_global_rect()
		check(button.is_visible_in_tree() and bounds.encloses(rect), "%s stays visible inside the narrow screen: %s" % [button.text, rect])
		if first_y < 0.0:
			first_y = rect.position.y
		elif rect.position.y > first_y + 1.0:
			wraps = true
	check(wraps, "actions wrap to another row in the same card")
	var scrolls: Array = screen.find_children("*", "ScrollContainer", true, false)
	check(scrolls.size() == 1 and scrolls[0].horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "the level list has no horizontal scrolling")
	var titles: Array = screen.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.text.contains(long_title))
	check(titles.size() == 1 and titles[0].text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "the long level title ellipsises")
	var thumbnails: Array[Node] = screen.find_children("*", "Thumbnail", true, false)
	check(not thumbnails.is_empty(), "the wrapped card keeps its thumbnail")
	for node: Node in thumbnails:
		var thumbnail: Thumbnail = node as Thumbnail
		check(thumbnail.size.y > 0.0, "wrapped thumbnail has a laid-out height")
		if thumbnail.size.y > 0.0:
			check(is_equal_approx(thumbnail.size.x / thumbnail.size.y, 16.0 / 9.0), "wrapped thumbnail stays 16:9: %s" % thumbnail.size)
	screen.queue_free()
	viewport.queue_free()
	MyLevels.delete(id)
