extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"
const MAIN := preload("res://scenes/main.gd")


## A level root with a ship at the origin and a goal at `goal_at`, added to the world.
func level(goal_at: Vector2, ship_props: Dictionary = {}) -> Level:
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	var ship: Node = load(SHIP).instantiate()
	for key in ship_props:
		ship.set(key, ship_props[key])
	root.add_child(ship)
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = goal_at
	root.add_child(goal)
	world.add_child(root)
	return root


func results(lvl: Level) -> Array:
	var seen := []
	lvl.finished.connect(func(won: bool): seen.append(won))
	return seen


func test_reaching_goal_wins() -> void:
	var lvl := level(Vector2(300, 0), {"linear_velocity": Vector2(300, 0)})
	var seen := results(lvl)
	await frames(120)
	check(seen == [true], "results %s, expected [true]" % [seen])


func test_destroyed_loses() -> void:
	var lvl := level(Vector2(3000, 0))
	var seen := results(lvl)
	lvl.ship.take_damage(100)
	await frames(2)
	check(seen == [false], "results %s, expected [false]" % [seen])


func test_finish_is_idempotent() -> void:
	var lvl := level(Vector2(300, 0), {"linear_velocity": Vector2(300, 0)})
	var seen := results(lvl)
	lvl.ship.take_damage(100)
	lvl.finish(true)
	await frames(120)
	check(seen == [false], "results %s, expected exactly one loss" % [seen])


func test_the_main_scene_opens_on_home() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	world.add_child(main)
	check(main.page == MAIN.Page.HOME, "the main scene must open on the home page, not %s" % main.page)
	check(stage_rows(main).is_empty(), "the home page must list no levels or training stages")
	main.free()


func test_official_lists_every_level() -> void:
	var list := menu(MAIN.Page.OFFICIAL)
	world.add_child(list)
	var levels := Progress.levels()
	check(stage_rows(list).size() == levels.size(), "%d rows for %d levels" % [stage_rows(list).size(), levels.size()])
	list.free()


func test_official_row_shows_the_best_medal() -> void:
	var par := int(LevelFormat.read(Progress.LEVELS_DIR + "level_01" + LevelFormat.EXTENSION).get("par", 0))
	check(par > 0, "level_01 must have a par for this test")
	var cases := {
		"unplayed": [-1, []],
		"below bronze": [ceili(Progress.BRONZE_FRACTION * par) - 1, []],
		"bronze": [ceili(Progress.BRONZE_FRACTION * par), [Progress.Medal.BRONZE]],
		"silver": [ceili(Progress.SILVER_FRACTION * par), [Progress.Medal.SILVER]],
		"gold": [par, [Progress.Medal.GOLD]],
	}
	for name in cases:
		Progress.reset()
		if cases[name][0] >= 0:
			Progress.record_win("level_01", cases[name][0], 20.0, 50.0, 50.0)
		var list := menu(MAIN.Page.OFFICIAL)
		world.add_child(list)
		var tiers := medal_tiers(stage_rows(list)["Level 01"])
		check(tiers == cases[name][1], "%s: medal icons %s, expected %s" % [name, tiers, cases[name][1]])
		list.free()



## A scored level: like `level`, but with an id so wins are saved.
func scored_level(goal_at: Vector2, ship_props: Dictionary = {}) -> Level:
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	root.level_id = "level_01"
	root.title = "Launch"
	var ship: Node = load(SHIP).instantiate()
	for key in ship_props:
		ship.set(key, ship_props[key])
	root.add_child(ship)
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = goal_at
	root.add_child(goal)
	world.add_child(root)
	return root


func test_win_saves_points() -> void:
	var lvl := scored_level(Vector2(300, 0), {"linear_velocity": Vector2(300, 0)})
	lvl.ship.start_boost()  # starts the clock without burning fuel
	await frames(120)
	var best := Progress.best_points("level_01")
	var expected := Progress.points(Ship.MAX_FUEL, Ship.MAX_HEALTH, lvl.ship.flight_time)
	check(best == expected, "saved %d, expected %d" % [best, expected])
	check(lvl.hud.result_text().contains(str(best)), "panel must show the points: %s" % lvl.hud.result_text())
	check(lvl.hud.result_text().contains("New best"), "first win must say New best")
	check(lvl.hud.result_text().contains("Level 1 · Launch"), "the panel must name the level: %s" % lvl.hud.result_text())


func test_loss_saves_nothing() -> void:
	var lvl := scored_level(Vector2(3000, 0))
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	check(Progress.best_points("level_01") == -1, "a loss saved %d points" % Progress.best_points("level_01"))
	check(lvl.hud.result_text().contains("Hull destroyed"), "loss cause missing: %s" % lvl.hud.result_text())
	check(lvl.hud.result_text().contains("Level 1 · Launch"), "the panel must name the level: %s" % lvl.hud.result_text())


func test_loss_cause_out_of_fuel() -> void:
	var lvl := scored_level(Vector2(3000, 0), {"fuel": 0.0})
	await frames(310)
	check(lvl.hud.result_text().contains("Out of fuel"), "loss cause missing: %s" % lvl.hud.result_text())


func test_result_card_counts_up_and_fills_medal_slots() -> void:
	var points := Progress.points(Ship.MAX_FUEL, Ship.MAX_HEALTH, 0.0)  # a win with nothing spent
	var cases := [[2 * points, "Medals: Bronze"], [points, "Medals: Bronze, Silver, Gold"], [4 * points, "Medals: "]]
	for case in cases:
		var lvl := scored_level(Vector2(3000, 0))
		lvl.par = case[0]
		lvl.finish(true)
		await frames(2)
		check(medal_tiers(lvl.hud) == [Progress.Medal.BRONZE, Progress.Medal.SILVER, Progress.Medal.GOLD], "three slots must show: %s" % [medal_tiers(lvl.hud)])
		check(int(lvl.hud.result_text().split("\n")[2]) < points, "the total must count up, not jump: %s" % lvl.hud.result_text())
		await frames(ceili(lvl.hud.COUNT_SECONDS * 60) + 5)
		var lines := lvl.hud.result_text().split("\n")
		check(lines[2] == str(points), "the count must end at the points: %s" % lvl.hud.result_text())
		check(lines.has(case[1]), "par %d: expected '%s' in %s" % [case[0], case[1], lvl.hud.result_text()])
		lvl.free()


func test_training_result_has_no_medal_slots() -> void:
	var lvl := training_stage(Progress.trainings()[0])
	await frames(2)
	lvl.finish(true)
	await frames(2)
	check(medal_tiers(lvl.hud).is_empty(), "a stage without par shows no medal slots: %s" % [medal_tiers(lvl.hud)])
	check(not lvl.hud.result_text().contains("Medals"), "a stage without par has no medal line: %s" % lvl.hud.result_text())
	lvl.free()


func test_clock_waits_for_first_thrust() -> void:
	var lvl := scored_level(Vector2(3000, 0))
	await frames(60)
	check(lvl.ship.flight_time == 0.0, "clock ran %f s before any thrust" % lvl.ship.flight_time)
	lvl.ship.thrusting = true
	await frames(60)
	check(absf(lvl.ship.flight_time - 1.0) < 0.05, "clock %f s after 1 s of thrust" % lvl.ship.flight_time)


## The stage rows under `node`, by name ("Level 01", "Training 2"); the home page's Training button is not one.
func stage_rows(node: Node) -> Dictionary:
	var rows := {}
	for button: Button in node.find_children("*", "Button", true, false):
		var label := row_title(button).get_slice(" · ", 0)
		if label.begins_with("Level ") or (label.begins_with("Training ") and label.get_slice(" ", 1).is_valid_int()):
			rows[label] = button
	return rows


## A stage row's title ("Level 01 · Launch"), or a plain button's text.
func row_title(button: Button) -> String:
	var title := button.find_child("Title", true, false)
	return title.text if title else button.text


## Everything a stage row says: its title and the best-score cells.
func row_text(button: Button) -> String:
	return " ".join(button.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text))


## The first button under `node` whose label starts with `prefix`, or null.
func button_starting(node: Node, prefix: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text.begins_with(prefix):
			return button
	return null


func test_menu_locks_levels() -> void:
	var list := menu(MAIN.Page.OFFICIAL)
	world.add_child(list)
	var buttons := stage_rows(list)
	check(not buttons.has("Training 1"), "the official list must not list training stages")
	check(not buttons["Level 01"].disabled and buttons["Level 02"].disabled, "fresh progress: only level 1 open")
	list.queue_free()
	var training := menu(MAIN.Page.TRAINING)
	world.add_child(training)
	buttons = stage_rows(training)
	check(not buttons.has("Level 01"), "the training list must not list levels")
	check(not buttons["Training 1"].disabled and buttons["Training 2"].disabled, "fresh progress: only training 1 open")
	Progress.record_win("tutorial_1", 1780, 30.0)
	await frames(1)
	buttons = stage_rows(training)
	check(not buttons["Training 2"].disabled, "winning training 1 must open training 2 on the list")
	check(row_text(buttons["Training 1"]).contains("1780"), "best points missing: %s" % row_text(buttons["Training 1"]))


func test_intro_card_until_first_thrust() -> void:
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	root.title = "Drift"
	root.hint = "Let go to coast."
	root.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(5000, 0)
	root.add_child(goal)
	world.add_child(root)
	var lvl := root as Level
	await frames(30)
	check(lvl.hud.intro_text().contains("Drift") and lvl.hud.intro_text().contains("Let go to coast."), "intro card: '%s'" % lvl.hud.intro_text())
	lvl.ship.thrusting = true
	await frames(90)
	check(lvl.hud.intro_text() == "", "intro card still shown after the first thrust (clock %f)" % lvl.ship.flight_time)


## A level with a goal and one tour stop, tours switched on.
func toured_level() -> Level:
	Tuning.set_value("tours", true)
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	root.level_id = "level_01"
	root.title = "Launch"
	root.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(3000, 0)
	root.add_child(goal)
	var tour := Node2D.new()
	tour.name = "Tour"
	var stop := Marker2D.new()
	stop.position = Vector2(1500, 0)
	stop.set_meta("text", "A wall.")
	tour.add_child(stop)
	root.add_child(tour)
	world.add_child(root)
	return root


func test_tour_walks_stops_then_plays() -> void:
	var lvl := toured_level()
	await frames(2)
	check(lvl.tour != null and tree.paused, "an unwon level must start with a paused tour")
	check(lvl.tour.caption() == "Level 1 · Launch", "first stop is the overview, named: '%s'" % lvl.tour.caption())
	lvl.tour.next()
	check(lvl.tour.caption() == "A wall.", "second stop: '%s'" % lvl.tour.caption())
	lvl.tour.next()  # back at the ship: Go!
	lvl.tour.next()
	await frames(2)
	check(not tree.paused and lvl.tour == null, "Go! must end the tour and unpause")
	check(Progress.toured.has("level_01"), "tour must be remembered for the session")


func test_no_tour_once_won() -> void:
	Progress.record_win("level_01", 1000, 10.0)
	var lvl := toured_level()
	await frames(2)
	check(lvl.tour == null and not tree.paused, "a won level must not tour")


func test_goal_arrow_edge_point() -> void:
	var size := Vector2(1280, 720)
	var p := Hud.edge_point(Vector2(5000, 360), size, 40.0)
	check(p.is_equal_approx(Vector2(1240, 360)), "goal far right: %s" % p)
	p = Hud.edge_point(Vector2(640, -9000), size, 40.0)
	check(p.is_equal_approx(Vector2(640, 40)), "goal far up: %s" % p)


func test_distance_and_speed_units() -> void:
	check(Hud.distance_text(4000) == "400 m", "4000 px: %s" % Hud.distance_text(4000))
	check(Hud.distance_text(12000) == "1.2 km", "12000 px: %s" % Hud.distance_text(12000))
	check(Hud.speed_text(800) == "80 m/s", "800 px/s: %s" % Hud.speed_text(800))


func test_credits_carry_the_licenses() -> void:
	var holder := Node.new()
	world.add_child(holder)
	var o := Credits.open(holder)
	var text := ""
	for label: Label in o.body.get_children():
		text += label.text + "\n"
	check(text.contains("GNU AFFERO GENERAL PUBLIC LICENSE"), "credits must carry the AGPL text")
	check(text.contains("SIL OPEN FONT LICENSE"), "credits must carry the font license text")
	check(text.contains("Permission is hereby granted, free of charge") and text.contains("Jacob Ibáñez Sánchez"), "credits must carry the Play Games plugin's MIT license")
	check(text.contains(Engine.get_license_text().substr(0, 40)), "credits must carry Godot's license")


func test_velocity_arrow_setting() -> void:
	var lvl := level(Vector2(3000, 0))
	check(not lvl.ship.show_velocity, "levels hide the velocity arrow by default")
	lvl.free()
	Settings.show_velocity = true
	lvl = level(Vector2(3000, 0))
	check(lvl.ship.show_velocity, "the setting must turn the arrow on in levels")


func test_gravity_field_setting() -> void:
	check(Settings.show_gravity, "gravity fields must show by default")
	Settings.show_gravity = false
	var saved := ConfigFile.new()
	saved.load(Settings.path)
	check(not saved.get_value("display", "show_gravity", true), "the gravity setting must save")
	Settings.show_gravity = true


## A training stage built without its lesson script, so no lesson coroutine outlives the test.
func training_stage(id: String) -> Level:
	var lvl := LevelFormat.build(LevelFormat.read(Progress.TUTORIALS_DIR + id + LevelFormat.EXTENSION))
	lvl.level_id = id
	world.add_child(lvl)
	return lvl


func test_the_last_training_stage_ends_the_training() -> void:
	var lvl := training_stage(Progress.trainings()[-1])
	await frames(2)
	lvl.finish(true)
	await frames(2)
	var shown: Array = lvl.hud.find_children("*", "Button", true, false).filter(func(b: Button): return b.is_visible_in_tree()).map(func(b: Button): return b.text)
	check("End training" in shown and not "Next" in shown, "end panel of the last training stage: %s" % [shown])
	lvl.free()
	var other := training_stage(Progress.trainings()[0])
	await frames(2)
	other.finish(true)
	await frames(2)
	shown = other.hud.find_children("*", "Button", true, false).filter(func(b: Button): return b.is_visible_in_tree()).map(func(b: Button): return b.text)
	check("Next" in shown and not "End training" in shown, "end panel of an earlier training stage: %s" % [shown])
	other.free()


func test_main_menu_marks_completed_training() -> void:
	var training_button := func() -> String:
		var main: Control = load("res://scenes/main.tscn").instantiate()
		world.add_child(main)
		var text: String = main.find_children("*", "Button", true, false).filter(func(b: Button): return b.text.begins_with("Training"))[0].text
		main.free()
		return text
	for id in Progress.trainings().slice(0, -1):
		Progress.record_win(id, 1000, 10.0)
	check(training_button.call() == "Training", "not all training done: %s" % training_button.call())
	Progress.record_win(Progress.trainings()[-1], 1000, 10.0)
	check(training_button.call().contains("completed"), "all training done: %s" % training_button.call())


## A key tap through Input, as the OS delivers it.
func tap(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func test_pause_toggles_the_tree() -> void:
	var lvl := level(Vector2(3000, 0))
	await frames(2)
	tap(KEY_ESCAPE)
	await frames(1)
	check(tree.paused, "pause must pause the tree")
	var focus := lvl.hud.get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "Resume", "Resume must hold focus on the pause card, not %s" % focus)
	tap(KEY_ESCAPE)
	await frames(1)
	check(not tree.paused, "pause again must resume")


func test_accept_in_flight_presses_nothing() -> void:
	var lvl := level(Vector2(3000, 0))
	await frames(2)
	var on_button := lvl.hud.pause_button.get_global_rect().get_center()
	for at in [on_button, on_button + Vector2(0, 300)]:  # press on Pause, release away from it
		var move := InputEventMouseMotion.new()
		move.position = at
		tree.root.push_input(move, true)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = at == on_button
		event.position = at
		tree.root.push_input(event, true)
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	Input.flush_buffered_events()
	await frames(5)
	check(is_instance_valid(lvl) and not lvl.is_queued_for_deletion(), "ui_accept restarted the level")
	var focus := lvl.hud.get_viewport().gui_get_focus_owner()
	check(focus == null, "a HUD top-bar button took focus: %s" % focus)


func test_result_card_takes_focus() -> void:
	var lvl := level(Vector2(3000, 0))
	await frames(2)
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	await frames(30)  # the card takes focus after a short delay
	var focus := lvl.hud.get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "Retry", "the result card's first button must hold focus, not %s" % focus)


## A fire tap just after the finish must not skip the card by pressing its first button.
func test_fire_tap_after_finish_presses_nothing() -> void:
	var lvl := scored_level(Vector2(300, 0), {"linear_velocity": Vector2(300, 0)})
	var pressed := []
	lvl.hud.retry_requested.connect(func(): pressed.append("retry"))
	lvl.hud.next_requested.connect(func(): pressed.append("next"))
	lvl.hud.replay_requested.connect(func(): pressed.append("replay"))
	for i in 150:
		if lvl.hud._result.visible:
			break
		await frames(1)
	check(lvl.hud._result.visible, "control: the level must have ended")
	await frames(3)
	for down in [true, false]:  # keycode for ui_accept, physical keycode for fire
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		space.physical_keycode = KEY_SPACE
		space.pressed = down
		Input.parse_input_event(space)
		Input.flush_buffered_events()
	await frames(3)
	check(pressed.is_empty(), "a fire tap just after the finish pressed %s" % [pressed])


func test_cancel_resumes_from_the_pause_card() -> void:
	var lvl := level(Vector2(3000, 0))
	await frames(2)
	lvl.hud.toggle_pause()
	check(tree.paused, "control: the pause card pauses")
	send_action(&"ui_cancel")
	send_action(&"ui_cancel", false)
	await frames(1)
	check(not tree.paused and not lvl.hud._pause.visible, "ui_cancel (B) must resume")


func test_resume_returns_focus_to_the_caption() -> void:
	var lvl := Progress.build("tutorial_1")
	world.add_child(lvl)
	await frames(5)
	var ok := focused()
	check(ok is Button and ok.text == "OK", "control: the caption's OK must hold focus, not %s" % ok)
	lvl.hud.toggle_pause()
	lvl.hud.toggle_pause()
	check(focused() == ok, "after resuming, focus must return to OK, not %s" % focused())


func menu(page: int) -> Control:
	return MAIN.menu(page)


## An action sent through Input, as a gamepad button or a mapped key would.
func send_action(action: StringName, pressed := true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func focused() -> Control:
	return tree.root.gui_get_focus_owner()


func test_home_opens_with_official_focused() -> void:
	var home := menu(MAIN.Page.HOME)
	world.add_child(home)
	var focus := focused()
	check(focus is Button and focus.text.begins_with("Official"), "the home page must focus Official levels, not %s" % focus)
	check(focus and not focus.has_focus(true), "a screen must open with its focus ring hidden, for phones")
	home.free()


func test_list_pages_focus_their_first_stage() -> void:
	var list := menu(MAIN.Page.OFFICIAL)
	world.add_child(list)
	var focus := focused()
	check(focus is Button and row_title(focus).begins_with("Level 01"), "the official list must focus the first level, not %s" % focus)
	list.free()
	var training := menu(MAIN.Page.TRAINING)
	world.add_child(training)
	focus = focused()
	check(focus is Button and row_title(focus).begins_with("Training 1"), "the training list must focus the first stage, not %s" % focus)
	training.free()


func test_overlay_closes_on_cancel_and_restores_focus() -> void:
	var main := menu(MAIN.Page.HOME)
	world.add_child(main)
	var settings: Button = main.find_children("*", "Button", true, false).filter(func(b: Button): return b.text == "Settings")[0]
	settings.grab_focus()
	settings.pressed.emit()
	var focus := focused()
	check(focus is Button and focus.text == "Close", "an overlay must focus Close, not %s" % focus)
	send_action(&"ui_cancel")
	await frames(2)
	check(main.find_children("*", "Overlay", true, false).is_empty(), "ui_cancel must close the overlay")
	check(focused() == settings, "focus must return to the Settings button, not %s" % focused())


func test_overlay_keeps_focus_inside() -> void:
	var main := menu(MAIN.Page.HOME)
	world.add_child(main)
	var overlay := Overlay.open(main, "Test")
	for i in 8:
		send_action(&"ui_down")
		send_action(&"ui_down", false)
	check(overlay.is_ancestor_of(focused()), "focus left the overlay for %s" % focused())


func test_cancel_on_a_list_returns_home() -> void:
	for page in [MAIN.Page.OFFICIAL, MAIN.Page.TRAINING]:
		var list := menu(page)
		world.add_child(list)
		send_action(&"ui_cancel")
		await frames(2)
		var scene := tree.current_scene
		check(scene != null and scene.scene_file_path == "res://scenes/main.tscn" and scene.page == MAIN.Page.HOME, "ui_cancel on a list must open the home page: %s" % scene)
		list.free()
		if scene:
			scene.free()
			tree.current_scene = null


func test_cancel_on_home_does_nothing() -> void:
	var home := menu(MAIN.Page.HOME)
	world.add_child(home)
	send_action(&"ui_cancel")
	await frames(2)
	check(tree.current_scene == null and home.is_inside_tree(), "ui_cancel on home must leave it open")
	home.free()


func test_home_opens_each_list_and_back_returns_home() -> void:
	for entry in [["Official", MAIN.Page.OFFICIAL], ["Training", MAIN.Page.TRAINING]]:
		var home := menu(MAIN.Page.HOME)
		world.add_child(home)
		button_starting(home, entry[0]).pressed.emit()
		home.free()
		await frames(2)
		var list = tree.current_scene
		check(list != null and list.page == entry[1], "%s must open its list: %s" % [entry[0], list])
		if list == null:
			continue
		button_starting(list, "Back").pressed.emit()
		await frames(2)
		var back = tree.current_scene
		check(back != null and back.page == MAIN.Page.HOME, "Back must return to home: %s" % back)
		if back:
			back.free()
			tree.current_scene = null


func test_menu_from_a_level_reopens_the_official_list() -> void:
	var lvl := scored_level(Vector2(3000, 0))
	await frames(2)
	lvl.hud.menu_requested.emit()
	await frames(2)
	var list = tree.current_scene
	check(list != null and list.page == MAIN.Page.OFFICIAL, "Menu from an official level must reopen the official list: %s" % list)
	if list:
		list.free()
		tree.current_scene = null


func test_menu_from_a_training_stage_reopens_the_training_list() -> void:
	var lvl := training_stage(Progress.trainings()[0])
	await frames(2)
	lvl.hud.menu_requested.emit()
	await frames(2)
	var list = tree.current_scene
	check(list != null and list.page == MAIN.Page.TRAINING, "Menu from a training stage must reopen the training list: %s" % list)
	if list:
		list.free()
		tree.current_scene = null


func test_tutorial_ok_takes_focus() -> void:
	var lvl := Progress.build("tutorial_1")
	world.add_child(lvl)
	await frames(5)
	var focus := focused()
	check(focus is Button and focus.text == "OK", "the caption's OK must hold focus, not %s" % focus)
	check(lvl._card.visible, "control: the caption card must be showing")
	send_action(&"ui_accept")
	send_action(&"ui_accept", false)
	await frames(2)
	check(not lvl._card.visible, "ui_accept must press OK")


## An Esc key press as the keyboard sends it: keycode and physical keycode both set.
func escape() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func test_cancel_closes_the_tuning_panel_only() -> void:
	var lvl := level(Vector2(3000, 0))
	await frames(2)
	TuningPanel.open(lvl.hud)
	check(tree.paused, "control: the panel pauses the tree")
	escape()
	await frames(2)
	check(lvl.hud.find_children("*", "TuningPanel", true, false).is_empty(), "Esc must close the panel")
	check(not tree.paused and not lvl.hud._pause.visible, "the same Esc must not open the pause card (paused %s)" % tree.paused)


func test_held_fire_does_not_press_the_result_card() -> void:
	var lvl := scored_level(Vector2(300, 0), {"linear_velocity": Vector2(300, 0)})
	var pressed := []
	lvl.hud.retry_requested.connect(func(): pressed.append("retry"))
	lvl.hud.next_requested.connect(func(): pressed.append("next"))
	lvl.hud.replay_requested.connect(func(): pressed.append("replay"))
	lvl.hud.menu_requested.connect(func(): pressed.append("menu"))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	for i in 150:  # held through the finish: the OS repeats the key
		var echo := space.duplicate()
		echo.echo = true
		Input.parse_input_event(echo)
		Input.flush_buffered_events()
		await frames(1)
	check(lvl.hud._result.visible, "control: the level must have ended")
	space.pressed = false
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	await frames(3)
	check(pressed.is_empty(), "a held fire key pressed a result-card button: %s" % [pressed])


func test_focused_button_is_visible() -> void:
	var box := ThemeDB.get_default_theme().get_stylebox("focus", "Button")
	check(box is StyleBoxFlat and box.get_border_width(SIDE_LEFT) > 0 and not box.draw_center, "a focused button must draw an outline, not %s" % box)


func test_ui_pause_settings_keeps_flight_frozen_until_resume() -> void:
	var lvl := level(Vector2(3000, 0), {"linear_velocity": Vector2(120, 0)})
	await frames(2)
	var pause_buttons := lvl.hud.find_children("*", "Button", true, false).filter(func(b: Button): return b.text == "Pause")
	if pause_buttons.is_empty():
		check(false, "flight needs a Pause action")
		return
	pause_buttons[0].pressed.emit()
	var stopped_at := lvl.ship.position
	var settings_buttons := lvl.hud._pause.find_children("*", "Button", true, false).filter(func(b: Button): return b.text == "Settings")
	if settings_buttons.is_empty():
		check(false, "pause must offer flight settings")
		tree.paused = false
		return
	settings_buttons[0].grab_focus()
	settings_buttons[0].pressed.emit()
	var sheets := lvl.hud.find_children("*", "Overlay", true, false)
	if sheets.is_empty():
		check(false, "settings must open while paused")
		tree.paused = false
		return
	Settings.show_velocity = true
	check(lvl.ship.show_velocity, "display settings must apply to the current ship")
	send_action(&"pause")
	send_action(&"pause", false)
	await frames(3)
	check(tree.paused and lvl.ship.position == stopped_at, "Start must not resume flight beneath settings")
	escape()
	await frames(2)
	check(tree.paused and lvl.hud.find_children("*", "Overlay", true, false).is_empty(), "Esc closes settings without resuming")
	check(focused() == settings_buttons[0], "closing settings restores its pause-card action")
	escape()
	await frames(3)
	check(not tree.paused and lvl.ship.position != stopped_at, "a second Esc resumes flight")


func test_official_focus_advances_to_unfinished_level() -> void:
	Progress.record_win("level_01", 1200, 10.0)
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	var next := focused()
	check(next is Button and row_title(next).begins_with("Level 02"), "returning after a clear must select the next unfinished level")
	Progress.record_win("level_02", 1300, 9.0)
	await frames(1)
	next = focused()
	check(next is Button and row_title(next).begins_with("Level 03"), "progress refresh must advance the suggested stage")
	main.free()
	Progress.unlock_all = true
	main = menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	next = focused()
	check(next is Button and row_title(next).begins_with("Level 03"), "unlocking all must not suggest replaying a finished stage")


## Result integration uses real recorder, durable outbox and HUD; only the device/network are faked.
func _result_setup(owner := "p_me") -> FakeTransport:
	Community.use_defaults()
	Community.history_path = "user://test_results/history.json"
	_wipe_results("user://test_results")
	var net := FakeTransport.new()
	world.add_child(net)
	Community.transport = net
	Community.platform = FakePlatform.new()
	_result_owner(owner)
	net.answer("GET", "/nonce", 200, {"nonce": "results"})
	net.hold("POST", "/scores")
	net.respond("GET", "/boards/", func(_request: Dictionary) -> Dictionary:
		return {"status": 200, "body": _result_payload()})
	return net


func _result_owner(owner: String) -> void:
	var file := ConfigFile.new()
	if owner != "":
		file.set_value("player", "id", owner)
		file.set_value("session", "token", "token")
		file.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
	check(file.save(Community.session_path) == OK, "isolated result session saves")


func _wipe_results(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub in DirAccess.get_directories_at(folder):
		_wipe_results(folder.path_join(sub))
		DirAccess.remove_absolute(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))


func _result_level(id := "level_01", testing := false, publishing := false) -> Level:
	var lvl := Progress.build("level_01")
	lvl.level_id = Community.STAGE_PREFIX + lvl.level_sha256 if id == "community" else id
	lvl.testing = testing
	lvl.publishing = publishing
	world.add_child(lvl)
	return lvl


func _result_payload() -> Dictionary:
	var rows := []
	for i in 20:
		rows.append({"rank": i + 1, "player": {"id": "pilot_%d" % i, "name": "Pilot %02d" % (i + 1)}, "points": 3000 - i * 50, "seconds": 12.5 + i})
	return {"level": {"kind": "official", "name": "Launch"}, "rows": rows, "you": {"rank": 25, "player": {"id": "p_me", "name": "My Pilot"}, "points": 700, "seconds": 30.25}, "count": 30, "quantiles": range(0, 3100, 150)}


func _result_disk() -> CommunityScores:
	var scores := CommunityScores.new()
	scores.path = Community.history_path.get_basename() + "_scores.json"
	check(scores.load_file() == OK, "result outbox reloads")
	return scores


func test_results_enqueue_only_signed_in_play_new_best_wins() -> void:
	for case in ["campaign", "community", "training", "test", "publish", "draft", "loss", "not_best", "desktop", "signed_out", "unknown_owner", "replay"]:
		Progress.reset()
		var net := _result_setup("" if case == "signed_out" else "p_me")
		if case == "desktop":
			(Community.platform as FakePlatform).is_available = false
		if case == "unknown_owner":
			var session := ConfigFile.new()
			session.set_value("session", "token", "token")
			session.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 1000)
			session.save(Community.session_path)
		var id: String = {"community": "community", "training": "tutorial_1", "draft": "user_draft"}.get(case, "level_01")
		if case == "not_best":
			Progress.record_win("level_01", 99999, 0.0)
		var lvl := _result_level(id, case == "test" or case == "publish", case == "publish")
		if case == "replay":
			lvl.process_mode = Node.PROCESS_MODE_DISABLED
		lvl.finish(case != "loss")
		var entries := _result_disk().entries("p_me")
		var eligible: bool = case == "campaign" or case == "community"
		check(entries.size() == (1 if eligible else 0), "%s: only signed-in Play new-best real wins enqueue" % case)
		if eligible and not entries.is_empty():
			var run := Demo.decode(_result_disk().snapshot("p_me", lvl.level_sha256, entries[0].revision))
			check(run != null and run.events().back()[1] == Demo.Event.GOAL_REACHED and run.events().back()[0] == run.frame_count(), "%s: queue contains the finalized winning recorder" % case)
		if case in ["desktop", "signed_out", "unknown_owner", "training", "test", "publish", "draft", "loss", "replay"]:
			check(net.requests.is_empty(), "%s: no automatic leaderboard request" % case)
		check((Community.platform as FakePlatform).sign_ins == 0, "%s: a result never signs in" % case)
		lvl.free()


func test_result_queues_its_finalized_memory_demo_when_best_demo_save_fails() -> void:
	_result_setup()
	var old_dir := Progress.demos_dir
	Progress.demos_dir = "user://test_results/blocked/"
	DirAccess.make_dir_recursive_absolute(Progress.demos_dir + "level_01.demo.gz")
	var blocker := FileAccess.open(Progress.demos_dir + "level_01.demo.gz/occupied", FileAccess.WRITE)
	blocker.store_string("keep directory nonempty")
	blocker.close()
	var lvl := _result_level()
	lvl.ship.fuel = 31.0
	lvl.finish(true)
	check(Progress.best_demo("level_01") == null, "best-demo path cannot be saved")
	var disk := _result_disk()
	var queued := disk.entry("p_me", lvl.level_sha256)
	check(not queued.is_empty(), "valid finalized memory replay can queue despite best-demo save failure")
	if not queued.is_empty():
		var bytes := disk.snapshot("p_me", lvl.level_sha256, queued.revision)
		var run := Demo.decode(bytes)
		check(run != null and run.ship_at(run.frame_count() - 1).fuel == 31.0 and run.events().back()[1] == Demo.Event.GOAL_REACHED, "durable queue owns this new run, never a prior Progress replay")
		lvl.demo.level_sha256 = "b".repeat(64)
		check(disk.snapshot("p_me", lvl.level_sha256, queued.revision) == bytes, "later in-memory mutations cannot change durable bytes")
	Progress.demos_dir = old_dir


func test_result_posting_is_immediate_and_exact_rank_is_for_remote_stored_best() -> void:
	var net := _result_setup()
	var lvl := _result_level()
	lvl.finish(true)
	check(lvl.hud._result.visible and lvl.hud.result_text().contains("Posting"), "result shows without awaiting the held upload")
	check(net.count("POST", "/scores") == 1, "score sync starts without waiting for the board")
	var stored := _result_payload()
	stored.you.rank = 7
	stored.you.points = 900
	for i in stored.rows.size():
		stored.rows[i].points = 1020 - i * 20
	stored.rows[6] = stored.you.duplicate(true)
	net.answer("GET", "/boards/", 200, stored)
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 900, "best": false})
	net.release_hold("POST", "/scores")
	var text := lvl.hud.result_text()
	check(text.contains("Your ranked best") and text.contains("Rank #7") and text.contains("900 points"), "best:false rank is labelled as the remote stored best")
	check(text.contains("Estimate:") and not text.contains("Rank #25"), "higher local score remains estimated and bounded by the new remote rank")
	check(button_starting(lvl.hud, "Board").is_visible_in_tree(), "eligible win offers Board")
	check(lvl.hud.find_child("LeaderboardPreview", true, false) != null, "eligible result hosts the shared top-five preview")


func test_result_pending_and_queue_save_error_are_visible_without_claiming_exact_rank() -> void:
	var net := _result_setup()
	var lvl := _result_level()
	lvl.finish(true)
	net.answer("POST", "/scores", 0)
	net.release_hold("POST", "/scores")
	check(lvl.hud.result_text().contains("Will post when online") and lvl.hud.result_text().contains("Estimate:"), "offline post retains pending and honest local estimate")
	lvl.free()
	Progress.reset()
	_result_setup()
	DirAccess.make_dir_recursive_absolute(Community.history_path.get_basename() + "_scores.json.tmp")
	lvl = _result_level()
	lvl.finish(true)
	check(lvl.hud.result_text().contains("could not be queued") and not lvl.hud.result_text().contains("Posting") and not lvl.hud.result_text().contains("Will post when online"), "failed durable enqueue is visible, never falsely queued")


func test_result_ignores_wrong_owner_hash_revision_and_superseding_same_hash() -> void:
	var net := _result_setup()
	var lvl := _result_level()
	lvl.finish(true)
	var state := Community.score_state(lvl.level_sha256)
	var before := lvl.hud.result_text()
	var posted := {"state": "posted", "rank": 1, "points": 9999, "best": true}
	Community.score_result.emit("other", lvl.level_sha256, state.revision, posted)
	Community.score_result.emit("p_me", "b".repeat(64), state.revision, posted)
	Community.score_result.emit("p_me", lvl.level_sha256, state.revision + 1, posted)
	check(lvl.hud.result_text() == before, "wrong owner/hash/revision cannot change live result")
	check(Community.queue_score(lvl.level_id, lvl.demo) == "", "new same-hash revision is durable")
	Community.score_result.emit("p_me", lvl.level_sha256, state.revision, posted)
	check(lvl.hud.result_text() == before, "superseded revision cannot overwrite the result")
	_result_owner("p_other")
	Community.identity_changed.emit("p_other")
	check(not lvl.hud.result_text().contains("Posting") and not lvl.hud.result_text().contains("Rank #25"), "owner switch immediately clears prior private status")
	before = lvl.hud.result_text()
	Community.score_result.emit("p_me", lvl.level_sha256, state.revision, posted)
	net.answer("POST", "/scores", 200, {"rank": 1, "points": 9999, "best": true})
	net.release_hold("POST", "/scores")
	check(lvl.hud.result_text() == before, "held previous-owner upload cannot restore private standing after an owner switch")


func test_result_closed_during_held_score_and_board_only_updates_cache() -> void:
	var net := _result_setup()
	net.hold("GET", "/boards/")
	var lvl := _result_level()
	var sha := lvl.level_sha256
	lvl.finish(true)
	lvl.queue_free()
	await frames(2)
	net.answer("POST", "/scores", 200, {"rank": 7, "points": 2000, "best": true})
	net.release_hold("POST", "/scores")
	net.release_hold("GET", "/boards/")
	await frames(2)
	check(not is_instance_valid(lvl) and Community.cached_board(sha).get("count") == 30, "late requests update cache, never freed result controls")


func test_result_matching_posted_score_becomes_exact_and_board_restores_focus() -> void:
	var net := _result_setup()
	var lvl := _result_level()
	lvl.finish(true)
	var points := Progress.best_points(lvl.level_id)
	var stored := _result_payload()
	stored.you.rank = 3
	stored.you.points = points
	for i in stored.rows.size():
		stored.rows[i].points = points + 100 - i * 50
	stored.rows[2] = stored.you.duplicate(true)
	net.answer("GET", "/boards/", 200, stored)
	net.answer("POST", "/scores", 200, {"rank": 3, "points": points, "best": true})
	net.release_hold("POST", "/scores")
	check(lvl.hud.result_text().contains("Your ranked best · Rank #3 of 30") and not lvl.hud.result_text().contains("Estimate:"), "matching local and stored best displays exact standing")
	var board := button_starting(lvl.hud, "Board")
	board.grab_focus()
	board.pressed.emit()
	var sheets := lvl.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1, "Board opens the shared full sheet")
	if not sheets.is_empty():
		sheets[0].close()
		await frames(2)
		check(board.has_focus(), "closing Board restores the existing result action")


func test_result_invalid_finalized_demo_never_falls_back_to_prior_best_replay() -> void:
	_result_setup()
	var lvl := _result_level()
	var prior := Demo.new()
	prior.level_sha256 = lvl.level_sha256
	prior.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 1.0, "hull": 1.0}, {})
	prior.add_event(Demo.Event.GOAL_REACHED)
	Progress.save_best_demo(lvl.level_id, prior)
	check(Progress.best_demo(lvl.level_id) != null, "prior best replay exists")
	lvl.demo.truncated = true
	lvl.finish(true)
	check(_result_disk().entries("p_me").is_empty() and lvl.hud.result_text().contains("cannot be posted"), "invalid new recording never uploads the previous best replay")


func test_result_preview_and_actions_fit_logical_viewport_with_ad_footer() -> void:
	var old_size := tree.root.size
	tree.root.size = Vector2i(1280, 720)
	await frames(2)
	_result_setup()
	Monetization.platform = load("res://tests/support/fake_monetization_platform.gd").new()
	Monetization.start()
	var lvl := _result_level()
	lvl.finish(true)
	lvl.hud._rate.show()  # the densest legitimate result also offers community rating
	await frames(3)
	var available := lvl.hud._result_frame.get_global_rect()
	check(Monetization.footer_height > 0 and available.encloses(lvl.hud._result.get_global_rect()), "result preview and breakdown fit above the reserved footer: %s in %s" % [lvl.hud._result.get_global_rect(), available])
	for button: Button in lvl.hud._result.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			check(available.encloses(button.get_global_rect()), "%s remains visible above footer" % button.text)
	lvl.free()
	Monetization.use_defaults()
	tree.root.size = old_size


func test_result_post_after_held_board_forces_fresh_preview_without_regressing_standing() -> void:
	var net := _result_setup()
	net.hold("GET", "/boards/")
	var lvl := _result_level()
	lvl.finish(true)
	var points := Progress.best_points(lvl.level_id)
	net.answer("POST", "/scores", 200, {"rank": 3, "points": points, "best": true})
	net.release_hold("POST", "/scores")
	check(lvl.hud.result_text().contains("Rank #3") and not lvl.hud.result_text().contains(" of 30"), "POST standing appears immediately without inventing a still-unknown population")
	net.hold("GET", "/boards/")
	net.release_hold("GET", "/boards/")
	check(net.count("GET", "/boards/") == 2 and lvl.hud.result_text().contains("Rank #3 of 30"), "old board completion schedules a forced post-upload read without regressing exact standing")
	# Three higher scores now exist: a competitor arrived after the POST reported rank 3.
	var fresh := {"level": {"kind": "official", "name": "Launch"}, "rows": [], "you": null, "count": 31, "quantiles": [1180, 1200, 1240, 1260, 1300, 1320, 1360, 1380, 1420, 1440, 1480, 1520, 1540, 1580, 1600, 1640, 1660, 1700, 1800, 2000, 2100]}
	var scores: Array = [2100, 2000, 1900, 1800] + range(1700, 1160, -20)
	for i in scores.size():
		var row := {"rank": i + 1, "player": {"id": "p_me" if i == 3 else "pilot_%d" % i, "name": "My Pilot" if i == 3 else "Pilot %02d" % (i + 1)}, "points": scores[i], "seconds": 30.0 + i}
		if i < 20:
			fresh.rows.append(row)
		if i == 3:
			fresh.you = row
	net.answer("GET", "/boards/", 200, fresh)
	net.release_hold("GET", "/boards/")
	var preview := lvl.hud.find_child("LeaderboardPreview", true, false)
	var text := "\n".join(preview.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text))
	check(text.contains("Rank #4 of 31") and not text.contains("Rank #25"), "fresh own row replaces the pre-upload preview")
	check(lvl.hud.result_text().contains("Rank #4 of 31") and not lvl.hud.result_text().contains("Rank #3"), "fresh post-upload board supersedes the provisional POST rank in the HUD too")


func _campaign_sha(id := "level_01") -> String:
	return LevelFormat.sha256(LevelFormat.read(Progress.LEVELS_DIR + id + LevelFormat.EXTENSION))


func _campaign_best(sha: String, points := 700) -> void:
	Progress.record_win("level_01", points, 30.0, 25.0, 25.0)
	var run := Demo.new()
	run.level_sha256 = sha
	run.add_frame({"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 25.0, "hull": 25.0}, {})
	run.add_event(Demo.Event.GOAL_REACHED)
	Progress.save_best_demo("level_01", run)


func _campaign_badge(main: Node) -> Button:
	return stage_rows(main)["Level 01"].find_child("BoardBadge", true, false) as Button


func test_campaign_cached_exact_estimate_and_no_cache_badges() -> void:
	var net := _result_setup()
	var sha := _campaign_sha()
	_campaign_best(sha)
	net.hold("GET", "/boards/" + sha)
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	check(_campaign_badge(main) != null and not _campaign_badge(main).visible, "no cached board means no badge")
	net.release_hold("GET", "/boards/" + sha)
	await frames(3)
	check(_campaign_badge(main).text == "#25" and _campaign_badge(main).tooltip_text.contains("cached"), "matching local best uses the cached exact rank")
	var payload := _result_payload()
	payload.you = null
	net.answer("GET", "/boards/" + sha, 200, payload)
	await Community.board(sha, true)
	await frames(2)
	check(_campaign_badge(main).text.begins_with("~top ") and _campaign_badge(main).text.contains("%"), "unposted same-version best uses shared percentile estimate")


func test_opening_campaign_refreshes_only_completed_once_per_hash_hour() -> void:
	var net := _result_setup()
	var sha := _campaign_sha()
	_campaign_best(sha)
	for i in 2:
		var main := menu(MAIN.Page.OFFICIAL)
		world.add_child(main)
		await frames(2)
		main.free()
	check(net.count("GET", "/boards/") == 1 and net.count("GET", "/boards/" + sha) == 1, "opening twice refreshes only the completed current hash once")
	for file in DirAccess.get_files_at(Community.dir):
		if file.begins_with("board_") and file.ends_with(".json"):
			var cached: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Community.dir + file))
			cached.fetched_at = int(Time.get_unix_time_from_system()) - Community.BOARD_CACHE_SECONDS - 1
			var saved := FileAccess.open(Community.dir + file, FileAccess.WRITE)
			saved.store_string(JSON.stringify(cached))
			saved.close()
	var reopened := menu(MAIN.Page.OFFICIAL)
	world.add_child(reopened)
	await frames(2)
	check(net.count("GET", "/boards/" + sha) == 2, "expired cache refreshes on the next opening")


func test_campaign_board_updates_in_place_and_board_return_preserves_selection() -> void:
	var net := _result_setup()
	var sha := _campaign_sha()
	_campaign_best(sha)
	net.hold("GET", "/boards/" + sha)
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	await frames(2)
	var selected: Button = stage_rows(main)["Level 02"]
	selected.grab_focus()
	var row: Button = stage_rows(main)["Level 01"]
	net.release_hold("GET", "/boards/" + sha)
	await frames(3)
	check(stage_rows(main)["Level 01"] == row and focused() == selected, "async badge update preserves existing rows and selection")
	var badge := _campaign_badge(main)
	badge.grab_focus()
	badge.pressed.emit()
	await frames(2)
	var sheets := main.find_children("*", "Overlay", true, false)
	check(sheets.size() == 1, "campaign badge opens the shared board")
	if sheets.is_empty():
		return
	sheets[0].close()
	await frames(2)
	check(focused() == badge and stage_rows(main)["Level 01"] == row, "return restores the exact campaign board action")


func test_campaign_current_file_hash_never_uses_old_revision_rank_or_idbest() -> void:
	var net := _result_setup()
	var current := _campaign_sha()
	var old := "b".repeat(64)
	_campaign_best(old, 9999)
	await Community.board(old)
	var payload := _result_payload()
	payload.you = null
	net.answer("GET", "/boards/" + current, 200, payload)
	net.hold("GET", "/boards/" + current)
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	check(not _campaign_badge(main).visible, "same filename with changed content does not adopt the old hash's exact rank")
	net.release_hold("GET", "/boards/" + current)
	await frames(3)
	check(not _campaign_badge(main).visible, "old id best cannot produce an estimate for a new file revision")
	check(net.count("GET", "/boards/" + current) == 1, "requests use LevelFormat.sha256 of the bundled current file")


func test_training_and_desktop_lists_have_no_boards_requests_or_badges() -> void:
	var net := _result_setup()
	var sha := _campaign_sha()
	_campaign_best(sha)
	await Community.board(sha)
	net.requests.clear()
	var training := menu(MAIN.Page.TRAINING)
	world.add_child(training)
	await frames(2)
	check(training.find_children("BoardBadge", "Button", true, false).is_empty() and net.requests.is_empty(), "training neither displays nor fetches boards")
	training.free()
	(Community.platform as FakePlatform).is_available = false
	var desktop := menu(MAIN.Page.OFFICIAL)
	world.add_child(desktop)
	await frames(2)
	check(desktop.find_children("BoardBadge", "Button", true, false).is_empty() and net.requests.is_empty(), "desktop ignores even a populated board cache")


func test_campaign_identity_change_invalidates_private_badge_immediately() -> void:
	var net := _result_setup()
	_campaign_best("b".repeat(64))
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	await frames(2)
	check(_campaign_badge(main).text == "#25", "setup: current-hash remote best is exact even without a matching local replay")
	_result_owner("")
	Community.identity_changed.emit("")
	check(not _campaign_badge(main).visible, "sign-out immediately removes private exact rank")
	check(net.count("POST", "/session") == 0, "identity cancellation never signs back in")


func test_campaign_first_sign_in_still_reads_each_completed_hash_only_once() -> void:
	var net := _result_setup("")
	net.answer("POST", "/session", 200, {"token": "tok", "player": {"id": "p_me", "name": "My Pilot"}})
	_campaign_best(_campaign_sha())
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	await frames(3)
	check(net.count("GET", "/boards/") == 1, "identity learned during the opening read must not start a duplicate board refresh")


func test_campaign_long_title_and_badge_fit_above_reserved_footer() -> void:
	_result_setup()
	_campaign_best(_campaign_sha())
	Monetization.platform = load("res://tests/support/fake_monetization_platform.gd").new()
	Monetization.start()
	var main := menu(MAIN.Page.OFFICIAL)
	world.add_child(main)
	Monetization.set_surface(main, true)  # stress the same frame with a reserved footer
	await frames(4)
	var row: Button = stage_rows(main)["Level 01"]
	var title := row.find_child("Title", true, false) as Label
	title.text = "Level 01 · An extremely long orbital slalom through an abandoned interstellar shipyard"
	await frames(3)
	var frame: Control = main._column.get_parent()
	var scroll: ScrollContainer = main._levels.get_parent()
	check(frame.get_global_rect().encloses(scroll.get_global_rect()), "campaign scroll stays inside the footer-reserved frame")
	check(main._column.global_position.y >= frame.global_position.y, "the title is not pushed above the screen")
	check(row.get_global_rect().encloses(_campaign_badge(main).get_global_rect()), "badge stays inside the long-title row")
