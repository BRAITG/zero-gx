extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"


func test_reset_restores_defaults() -> void:
	for key in Tuning.RANGES:
		Tuning.set_value(key, Tuning.RANGES[key][1])
	Tuning.reset()
	for key in Tuning.DEFAULTS:
		check(Tuning.get(key) == Tuning.DEFAULTS[key], "%s = %s after reset, expected %s" % [key, Tuning.get(key), Tuning.DEFAULTS[key]])


func test_speed_capped_at_max_speed() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"thrusting": true, "aim_point": Vector2(100000, 0)})
	await frames(300)
	check(ship.linear_velocity.length() <= Tuning.max_speed + 1.0, "speed %f above cap %f" % [ship.linear_velocity.length(), Tuning.max_speed])


func test_overspeed_eases_down() -> void:
	var ship = spawn(SHIP, Vector2.ZERO, {"linear_velocity": Vector2(1200, 0)})
	var last := 1200.0
	var worst := 0.0
	for i in 120:
		await frames(1)
		var speed: float = ship.linear_velocity.length()
		worst = maxf(worst, last - speed)
		last = speed
	check(worst <= 400.0 / 60.0 + 0.5, "speed dropped %f in one step" % worst)
	check(absf(last - Tuning.max_speed) <= 1.0, "speed %f after 2 s, expected %f" % [last, Tuning.max_speed])


func test_slider_sets_tuning() -> void:
	var panel := TuningPanel.open(world)
	var slider: HSlider = panel.find_child("turn_rate", true, false)
	slider.value = 3.0
	check(Tuning.turn_rate == 3.0, "turn_rate %f after moving its slider to 3" % Tuning.turn_rate)
	panel.close()


func test_panel_blocks_touch() -> void:
	var level := Node2D.new()
	level.set_script(load("res://scenes/level.gd"))
	var ship: Ship = load(SHIP).instantiate()
	level.add_child(ship)
	level.add_child(load("res://scenes/goal.tscn").instantiate())
	world.add_child(level)
	await frames(2)
	var centre := tree.root.get_visible_rect().size / 2.0
	press(centre, true)
	await frames(1)  # ShipInput applies on the physics step
	check(ship.thrusting, "control: a touch without the panel should thrust")
	press(centre, false)
	await frames(1)
	var panel := TuningPanel.open(world)
	check(tree.paused, "opening the panel must pause the game")
	press(centre, true)
	await frames(1)
	check(not ship.thrusting, "a touch on the panel reached the ship")
	press(centre, false)
	panel.close()
	check(not tree.paused, "closing the panel must unpause")


func press(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.device = InputEvent.DEVICE_ID_EMULATION  # a touch, as Godot emulates it
	tree.root.push_input(event)


func test_panel_freed_by_scene_change_unpauses() -> void:
	await frames(1)
	var holder := Node.new()
	world.add_child(holder)
	TuningPanel.open(holder)
	holder.free()  # what a scene change (e.g. Android back from a level) does to an open panel
	check(not tree.paused, "game stays paused after the panel's scene was freed")


func test_tuning_from_pause_preserves_pause_on_close() -> void:
	tree.paused = true
	var panel := TuningPanel.open(world)
	panel.close()
	await frames(2)
	check(tree.paused, "closing developer tuning must not resume beneath Settings")
	tree.paused = false
