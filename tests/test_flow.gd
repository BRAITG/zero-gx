extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"


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


func test_main_lists_levels() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	world.add_child(main)
	var levels := Progress.levels()
	var buttons := main.find_children("*", "Button", true, false).filter(func(b: Button): return b.text.begins_with("Level"))
	check(buttons.size() == levels.size(), "%d buttons for %d levels" % [buttons.size(), levels.size()])


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


func test_clock_waits_for_first_thrust() -> void:
	var lvl := scored_level(Vector2(3000, 0))
	await frames(60)
	check(lvl.ship.flight_time == 0.0, "clock ran %f s before any thrust" % lvl.ship.flight_time)
	lvl.ship.thrusting = true
	await frames(60)
	check(absf(lvl.ship.flight_time - 1.0) < 0.05, "clock %f s after 1 s of thrust" % lvl.ship.flight_time)


func level_buttons(main: Control) -> Dictionary:
	var by_level := {}
	for button: Button in main.find_children("*", "Button", true, false):
		if button.text.begins_with("Level") or button.text.begins_with("Training"):
			by_level[button.text.get_slice(" · ", 0)] = button
	return by_level


func test_menu_locks_levels() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	world.add_child(main)
	var buttons := level_buttons(main)
	check(not buttons.has("Training 1"), "the main menu must not list training stages")
	check(not buttons["Level 01"].disabled and buttons["Level 02"].text.contains("locked"), "fresh progress: only level 1 open")
	main.queue_free()
	main = load("res://scenes/main.gd").menu(true)
	world.add_child(main)
	buttons = level_buttons(main)
	check(not buttons.has("Level 01"), "the training list must not list levels")
	check(not buttons["Training 1"].disabled and buttons["Training 2"].disabled, "fresh progress: only training 1 open")
	Progress.record_win("tutorial_1", 1780, 30.0)
	await frames(1)
	buttons = level_buttons(main)
	check(not buttons["Training 2"].disabled, "winning training 1 must open training 2 on the menu")
	check(buttons["Training 1"].text.contains("1780"), "best points missing: %s" % buttons["Training 1"].text)


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
	check(text.contains(Engine.get_license_text().substr(0, 40)), "credits must carry Godot's license")


func test_velocity_arrow_setting() -> void:
	var lvl := level(Vector2(3000, 0))
	check(not lvl.ship.show_velocity, "levels hide the velocity arrow by default")
	lvl.free()
	Settings.show_velocity = true
	lvl = level(Vector2(3000, 0))
	check(lvl.ship.show_velocity, "the setting must turn the arrow on in levels")


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
	var on_button := lvl.hud.restart_button.get_global_rect().get_center()
	for at in [on_button, on_button + Vector2(0, 300)]:  # press on Restart, release away from it
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
	await frames(2)
	var focus := lvl.hud.get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "Retry", "the result card's first button must hold focus, not %s" % focus)
