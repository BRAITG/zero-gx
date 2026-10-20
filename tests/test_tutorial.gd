extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"


func probe(script := "res://tests/support/tutorial_probe.gd", velocity := Vector2.ZERO) -> Level:
	var root := Node2D.new()
	root.set_script(load(script))
	var ship: Ship = load(SHIP).instantiate()
	ship.linear_velocity = velocity
	root.add_child(ship)
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
	Settings.mouse_aims = false  # a click is a one-finger touch; a cursor that aims fires without a ring
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
	check(Tutorial.aims_at(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(89))), "89 degrees off must still aim at the ring")
	check(not Tutorial.aims_at(Vector2.RIGHT, Vector2.RIGHT.rotated(deg_to_rad(91))), "91 degrees off must not aim at the ring")
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


## The ring's direction from the ship, in world space.
func ring_angle(lvl: Tutorial) -> float:
	return (tree.root.canvas_transform.affine_inverse() * lvl.ring_centre() - lvl.ship.global_position).angle()


func test_steering_turns_the_ship_before_the_goal_is_revealed() -> void:
	var lvl := await keys_training()
	check(not lvl.goal_revealed(), "the goal must still be hidden")
	key(KEY_S, true)
	await frames(30)
	key(KEY_S, false)
	check(absf(wrapf(lvl.ship.rotation - PI / 2.0, -PI, PI)) < 0.1, "holding S turned the ship to %f rad, expected toward +Y" % lvl.ship.rotation)
	check(not lvl.ship.thrusting and lvl.held_time == 0.0, "steering alone must neither fire nor count the ring")


func test_fire_within_ninety_degrees_counts_the_ring_and_turns_to_it() -> void:
	var lvl := await keys_training()
	var to_ring := ring_angle(lvl)
	lvl.ship.rotation = to_ring + deg_to_rad(80)
	key(KEY_SPACE, true)
	await frames(20)
	key(KEY_SPACE, false)
	check(lvl.held_time > 0.2, "fire 80 degrees off the ring counted only %f s" % lvl.held_time)
	check(absf(wrapf(lvl.ship.rotation - to_ring, -PI, PI)) < 0.1, "the ship turned to %f rad, the ring is at %f" % [lvl.ship.rotation, to_ring])


func test_fire_beyond_ninety_degrees_thrusts_but_does_not_count() -> void:
	var lvl := await keys_training()
	var nose := ring_angle(lvl) + deg_to_rad(100)
	lvl.ship.rotation = nose
	key(KEY_SPACE, true)
	await frames(30)
	key(KEY_SPACE, false)
	check(lvl.held_time == 0.0 and lvl.ring_active(), "fire 100 degrees off the ring counted %f s" % lvl.held_time)
	check(lvl.ship.linear_velocity.length() > 20.0 and absf(wrapf(lvl.ship.linear_velocity.angle() - nose, -PI, PI)) < 0.1, "fire must thrust along the nose, got %s" % lvl.ship.linear_velocity)
	check(absf(wrapf(lvl.ship.rotation - nose, -PI, PI)) < 0.05, "the ship must not turn to a ring it is not counting")


func test_steering_without_fire_never_counts_the_ring() -> void:
	var lvl := await keys_training()
	key(KEY_D, true)
	await frames(60)
	key(KEY_D, false)
	check(lvl.held_time == 0.0 and lvl.ring_active(), "steering at the ring counted %f s without fire" % lvl.held_time)


## The cursor aims too, and the assist must win over it within the same physics tick.
func test_ring_assist_overrides_the_cursor_aim() -> void:
	var lvl := await keys_training()
	lvl.input.scheme = "mouse_aim"
	var to_ring := ring_angle(lvl)
	lvl.ship.rotation = to_ring + deg_to_rad(80)
	var motion := InputEventMouseMotion.new()
	motion.position = tree.root.canvas_transform * lvl.ship.global_position + Vector2.from_angle(to_ring - deg_to_rad(60)) * 200.0
	tree.root.push_input(motion, true)
	key(KEY_SPACE, true)
	await frames(20)
	key(KEY_SPACE, false)
	check(lvl.held_time > 0.2, "fire with the cursor 60 degrees off the ring counted only %f s" % lvl.held_time)
	check(absf(wrapf(lvl.ship.rotation - to_ring, -PI, PI)) < 0.1, "the ship followed the cursor to %f rad, the ring is at %f" % [lvl.ship.rotation, to_ring])


func test_wait_ring_lets_the_player_turn_then_fire_releases_the_ship() -> void:
	var moving := Vector2(0, -150)
	var lvl := await probe("res://tests/support/tutorial_wait_probe.gd", moving)
	await frames(5)
	lvl.input.scheme = "keys"
	check(lvl.waiting(), "the ring must hold the ship")
	var start: Vector2 = lvl.ship.global_position
	key(KEY_S, true)
	await frames(30)
	key(KEY_S, false)
	check(absf(wrapf(lvl.ship.rotation - PI / 2.0, -PI, PI)) < 0.1, "holding S turned the waiting ship to %f rad, expected toward +Y" % lvl.ship.rotation)
	check(lvl.ship.global_position.distance_to(start) < 0.5 and lvl.waiting() and lvl.held_time == 0.0, "the waiting ship drifted %s px" % lvl.ship.global_position.distance_to(start))
	key(KEY_SPACE, true)  # the nose is 45 degrees off the ring
	for i in 30:
		await frames(1)
		if not lvl.waiting():
			break
	var released: Vector2 = lvl.ship.linear_velocity  # at most a tick of thrust on the stored velocity
	await frames(5)
	key(KEY_SPACE, false)
	check(not lvl.waiting() and lvl.held_time > 0.0, "fire within 90 degrees must release the ship")
	check(absf(released.y - moving.y) < 15.0, "the ship must be released with its stored velocity %s, got %s" % [moving, released])
	check(lvl.ship.global_position.distance_to(start) > 5.0, "the released ship must fly on")


func test_wait_ring_ignores_fire_pointing_away() -> void:
	var lvl := await probe("res://tests/support/tutorial_wait_probe.gd", Vector2(0, -150))
	await frames(5)
	lvl.input.scheme = "keys"
	var start: Vector2 = lvl.ship.global_position
	lvl.ship.rotation = ring_angle(lvl) + deg_to_rad(150)
	key(KEY_SPACE, true)
	await frames(20)
	key(KEY_SPACE, false)
	check(lvl.waiting() and lvl.ship.global_position.distance_to(start) < 0.5, "fire away from a wait ring moved the ship %f px" % lvl.ship.global_position.distance_to(start))
