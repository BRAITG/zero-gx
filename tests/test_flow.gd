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
	var levels := Array(ResourceLoader.list_directory("res://levels/")).filter(func(f: String): return f.ends_with(".tscn"))
	var buttons := main.find_children("*", "Button", true, false).filter(func(b: Button): return b.text.begins_with("Level"))
	check(buttons.size() == levels.size(), "%d buttons for %d levels" % [buttons.size(), levels.size()])


## A scored level: like `level`, but with an id so wins are saved.
func scored_level(goal_at: Vector2, ship_props: Dictionary = {}) -> Level:
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	root.level_id = "level_01"
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


func test_loss_saves_nothing() -> void:
	var lvl := scored_level(Vector2(3000, 0))
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	await frames(2)
	check(Progress.best_points("level_01") == -1, "a loss saved %d points" % Progress.best_points("level_01"))
	check(lvl.hud.result_text().contains("Hull destroyed"), "loss cause missing: %s" % lvl.hud.result_text())


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
	check(not buttons["Training 1"].disabled and buttons["Training 2"].disabled, "fresh progress: only training 1 open")
	check(buttons["Level 01"].text.contains("locked"), "locked level label: %s" % buttons["Level 01"].text)
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
	check(lvl.tour.caption().contains("whole course"), "first stop is the overview: '%s'" % lvl.tour.caption())
	lvl.tour.next()
	check(lvl.tour.caption().contains("green ring"), "second stop is the goal: '%s'" % lvl.tour.caption())
	lvl.tour.next()
	check(lvl.tour.caption() == "A wall.", "third stop: '%s'" % lvl.tour.caption())
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
