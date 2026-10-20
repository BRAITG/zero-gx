extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"


func probe() -> Level:
	var root := Node2D.new()
	root.set_script(load("res://tests/support/tutorial_probe.gd"))
	root.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(3000, 0)
	root.add_child(goal)
	world.add_child(root)
	return root


func press(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	tree.root.push_input(event, true)  # viewport coordinates: headless window scaling differs


func test_touch_target_ignores_off_ring() -> void:
	var lvl = probe()
	await frames(3)
	check(lvl.ring_active(), "the probe must show a ring")
	var off: Vector2 = lvl.ring_centre() + Vector2(-400, 150)
	press(off, true)
	await frames(10)
	check(not lvl.ship.thrusting and lvl.ship.linear_velocity.length() < 1.0, "a touch off the ring moved the ship")
	press(off, false)
	press(lvl.ring_centre(), true)
	await frames(10)
	check(lvl.ship.thrusting and lvl.ship.linear_velocity.x > 1.0, "holding the ring must thrust toward it")
	press(lvl.ring_centre(), false)


func test_tutorial_restores_on_death() -> void:
	var lvl = probe()
	var lost := []
	lvl.finished.connect(func(won: bool): lost.append(won))
	await frames(3)
	var start: Vector2 = lvl.ship.global_position
	lvl.hold_ring(true)
	await frames(20)
	lvl.ship.take_damage(Ship.MAX_HEALTH)
	for i in 300:  # the wreck, then the beam back
		await frames(1)
		if lvl.retries > 0:
			break
	await frames(3)
	check(lost.is_empty(), "dying in a tutorial must not end the stage")
	check(lvl.ship.health == Ship.MAX_HEALTH and lvl.ship.visible, "the ship must come back whole")
	check(lvl.ship.global_position.distance_to(start) < 5.0, "the ship must return to the step's start, not %s" % lvl.ship.global_position)


## Every tutorial can be finished: answer each step as a player would, then fly the route.
func test_tutorials_complete() -> void:
	for id in Progress.trainings():
		var lvl = Progress.build(id)
		world.add_child(lvl)
		var outcome := {"won": null}
		lvl.finished.connect(func(won: bool): outcome.won = won)
		var route := lvl.get_node("Route") as Line2D
		var waypoints: Array[Vector2] = []
		for point in route.points:
			waypoints.append(route.position + point)
		waypoints.append(lvl.goal.position)
		var pilot := {"next": 0}
		var step := "lesson"
		var lesson_retries := -1
		for frame in 4800:
			await frames(1)
			if outcome.won != null:
				break
			if lvl.card_waiting():
				lvl.press_ok()
			lvl.hold_ring(lvl.ring_active())
			if lvl.goal_revealed():
				if lesson_retries < 0:
					lesson_retries = lvl.retries
				step = "flight"
				fly(lvl.ship, waypoints, pilot, route.get_meta("cruise", CRUISE))
		check(lesson_retries == 0, "%s: the guided steps killed the ship %d times" % [id, lesson_retries])
		check(outcome.won == true, "%s: not finished (%s, at %s, fuel %d, hull %d)" % [id, step, lvl.ship.global_position.round(), lvl.ship.fuel, lvl.ship.health])
		lvl.free()


## A lethal touch kills inside the physics step, where the freeze is deferred: the respawn must
## still leave the ship free, back at the step's start.
func test_tutorial_restores_after_lethal_touch() -> void:
	var lvl = probe()
	var hole: GravityBody = load("res://scenes/gravity_body.tscn").instantiate()
	hole.preset = GravityBody.Preset.BLACK_HOLE
	hole.position = Vector2(400, 0)
	lvl.add_child(hole)
	await frames(3)
	var start: Vector2 = lvl.ship.global_position
	for i in 400:
		await frames(1)
		if lvl.retries > 0:
			break
	await frames(10)
	check(lvl.retries == 1, "the ship must fall in once, not %d times" % lvl.retries)
	check(not lvl.ship.freeze and lvl.ship.visible, "the respawned ship must fly again")
	check(lvl.ship.global_position.distance_to(start) < 150.0, "the ship must be back near the step's start, not at %s" % lvl.ship.global_position.round())


func test_aims_at_boundary() -> void:
	check(Tutorial.aims_at(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(29))), "29 degrees off must still aim at the ring")
	check(not Tutorial.aims_at(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(31))), "31 degrees off must not aim at the ring")
	check(not Tutorial.aims_at(Vector2.ZERO, Vector2.RIGHT), "no steering aims at nothing")


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Training 1 on the keyboard, past its first card, with the first ring showing.
func keys_training() -> Tutorial:
	var lvl: Tutorial = Progress.build(Progress.trainings()[0])
	world.add_child(lvl)
	await frames(5)
	lvl.press_ok()
	await frames(3)
	lvl.input.scheme = "keys"
	return lvl


func test_keyboard_player_completes_the_first_ring() -> void:
	var lvl := await keys_training()
	check(lvl.ring_active(), "the first ring must show")
	key(KEY_D, true)
	key(KEY_SPACE, true)
	var caption := ""
	for i in 90:
		await frames(1)
		if i == 5:
			caption = lvl._caption_label.text
		if not lvl.ring_active():
			break
	key(KEY_SPACE, false)
	key(KEY_D, false)
	check(caption == "Point at the ring and hold fire.", "caption read '%s'" % caption)
	check(not lvl.ring_active(), "aiming at the ring and holding fire must complete the step")


func test_fire_without_aim_does_not_hold_the_ring() -> void:
	var lvl := await keys_training()
	key(KEY_A, true)
	key(KEY_SPACE, true)
	await frames(60)
	key(KEY_SPACE, false)
	key(KEY_A, false)
	check(lvl.ring_active(), "firing away from the ring must not complete the step")
