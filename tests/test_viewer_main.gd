extends "res://tests/test_case.gd"

const GOOD := "https://raw.githubusercontent.com/BRAITG/zero-gx-levels/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/levels/lvl_aaaaaaaaaa/v1.json"


func test_only_commit_pinned_levels_repo_urls_are_allowed() -> void:
	check(ViewerMain.allowed_url(GOOD), "a raw URL at a commit is allowed")
	for bad in [GOOD.replace("a".repeat(40), "main"), GOOD.replace("zero-gx-levels", "zero-gx"), GOOD.replace("https", "http"), "https://evil.example/" + GOOD, GOOD.replace("levels/lvl_aaaaaaaaaa", "../../../evil/repo/main"), GOOD + "?x=1", GOOD + "\n"]:
		check(not ViewerMain.allowed_url(bad), "must refuse %s" % bad)


func test_viewer_without_a_query_shows_the_refusal() -> void:
	var viewer := ViewerMain.new()
	world.add_child(viewer)
	var labels := viewer.find_children("*", "Label", true, false)
	check(labels.size() == 1 and (labels[0] as Label).text == ViewerMain.REFUSED, "no files named: the refusal is shown")


func test_viewer_refuses_a_demo_of_another_level() -> void:
	var viewer := ViewerMain.new()
	world.add_child(viewer)
	var level_01 := FileAccess.get_file_as_bytes("res://fixtures/levels/level_01.json")
	var level_05 := FileAccess.get_file_as_bytes("res://fixtures/levels/level_05.json")
	var demo_01 := FileAccess.get_file_as_bytes("res://fixtures/demos/level_01.demo.gz")
	check(viewer.start(level_05, demo_01) == "The demo was recorded on a different level.", "hash mismatch must be refused")
	check(viewer.start(level_01, demo_01) == "", "the matching pair plays")
	check(viewer.find_children("*", "DemoViewer", true, false).size() == 1, "a DemoViewer is shown")


func test_viewer_refuses_files_that_are_not_a_level_or_a_demo() -> void:
	var viewer := ViewerMain.new()
	world.add_child(viewer)
	var level_01 := FileAccess.get_file_as_bytes("res://fixtures/levels/level_01.json")
	var demo_01 := FileAccess.get_file_as_bytes("res://fixtures/demos/level_01.demo.gz")
	check(viewer.start("not json".to_utf8_buffer(), demo_01) == "The level file is not a valid Zero-GX level.", "text is not a level")
	check(viewer.start(FileAccess.get_file_as_bytes("res://fixtures/levels/invalid.planet_radius.json"), demo_01) == "The level file is not a valid Zero-GX level.", "an invalid level is refused")
	check(viewer.start(level_01, "not a demo".to_utf8_buffer()) == "The demo file is not a valid Zero-GX demo.", "text is not a demo")
	check(viewer.find_children("*", "DemoViewer", true, false).is_empty(), "nothing plays after a refusal")


func test_viewer_refuses_oversized_bodies() -> void:
	var viewer := ViewerMain.new()
	world.add_child(viewer)
	var level_01 := FileAccess.get_file_as_bytes("res://fixtures/levels/level_01.json")
	var demo_01 := FileAccess.get_file_as_bytes("res://fixtures/demos/level_01.demo.gz")
	var padded_level := level_01.duplicate()  # still valid JSON: only the size is wrong
	padded_level.append_array(" ".repeat(LevelFormat.MAX_BYTES).to_utf8_buffer())
	check(viewer.start(padded_level, demo_01) == "The level file is not a valid Zero-GX level.", "a level over the size cap is refused")
	var padded_demo := demo_01.duplicate()
	padded_demo.resize(Demo.MAX_BYTES + 1)
	check(viewer.start(level_01, padded_demo) == "The demo file is not a valid Zero-GX demo.", "a demo over the size cap is refused")
