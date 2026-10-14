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
		if button.text.begins_with("Level"):
			by_level[button.text.substr(0, 8)] = button
	return by_level


func test_menu_locks_levels() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	world.add_child(main)
	var buttons := level_buttons(main)
	check(not buttons["Level 01"].disabled and buttons["Level 02"].disabled, "fresh progress: only level 1 open")
	check(buttons["Level 02"].text.contains("locked"), "locked level label: %s" % buttons["Level 02"].text)
	Progress.record_win("level_01", 1780, 30.0)
	await frames(1)
	buttons = level_buttons(main)
	check(not buttons["Level 02"].disabled, "winning level 1 must open level 2 on the menu")
	check(buttons["Level 01"].text.contains("1780"), "best points missing: %s" % buttons["Level 01"].text)
