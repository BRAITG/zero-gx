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


## The tiers of the medal icons visible under `node`.
func medal_tiers(node: Node) -> Array:
	var icons := node.find_children("*", "ScoreIcon", true, false).filter(func(i: ScoreIcon) -> bool: return i.kind == ScoreIcon.Kind.MEDAL and i.is_visible_in_tree())
	return icons.map(func(i: ScoreIcon) -> int: return i.tier)


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


func test_result_card_shows_medal_and_next_threshold() -> void:
	var points := Progress.points(Ship.MAX_FUEL, Ship.MAX_HEALTH, 0.0)  # a win with nothing spent
	var lvl := scored_level(Vector2(3000, 0))
	lvl.par = 2 * points  # bronze at 0.8 × points, silver at 1.4 ×
	lvl.finish(true)
	await frames(2)
	check(medal_tiers(lvl.hud) == [Progress.Medal.BRONZE], "the card must show the bronze medal: %s" % [medal_tiers(lvl.hud)])
	check(lvl.hud.result_text().contains("Silver at %d" % ceili(Progress.SILVER_FRACTION * lvl.par)), "next threshold missing: %s" % lvl.hud.result_text())
	lvl.free()
	lvl = scored_level(Vector2(3000, 0))
	lvl.par = points
	lvl.finish(true)
	await frames(2)
	check(medal_tiers(lvl.hud) == [Progress.Medal.GOLD], "the card must show the gold medal: %s" % [medal_tiers(lvl.hud)])
	check(lvl.hud.result_text().contains("Gold") and not lvl.hud.result_text().contains(" at "), "gold has nothing above it: %s" % lvl.hud.result_text())
	lvl.free()
	lvl = scored_level(Vector2(3000, 0))
	lvl.par = 4 * points
	lvl.finish(true)
	await frames(2)
	check(medal_tiers(lvl.hud).is_empty(), "a run under bronze earns no medal: %s" % [medal_tiers(lvl.hud)])
	check(lvl.hud.result_text().contains("Bronze at %d" % ceili(Progress.BRONZE_FRACTION * lvl.par)), "bronze threshold missing: %s" % lvl.hud.result_text())


func test_training_result_has_no_medal_line() -> void:
	var lvl := training_stage(Progress.trainings()[0])
	await frames(2)
	lvl.finish(true)
	await frames(2)
	var text := lvl.hud.result_text()
	check(medal_tiers(lvl.hud).is_empty(), "a stage without par earns no medal: %s" % [medal_tiers(lvl.hud)])
	for word in ["Bronze", "Silver", "Gold", " at "]:
		check(not text.contains(word), "a stage without par must not show '%s': %s" % [word, text])
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
