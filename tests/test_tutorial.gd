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


func test_lethal_hit_loses_the_stage() -> void:
	var lvl = probe()
	var lost := []
	lvl.finished.connect(func(won: bool): lost.append(won))
	await frames(3)
	lvl.ship.take_damage(1.0, true)  # a lethal hit, like a red wall or a star
	await frames(300)  # long enough for a rescue, were there one, to have played out
	check(lost == [false], "a lethal hit must lose the stage, got %s" % [lost])
	check(not lvl.ship.visible, "the wreck must stay down once the stage is lost")


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
		var lesson_lost := false
		for frame in 4800:
			await frames(1)
			if outcome.won != null:
				lesson_lost = outcome.won == false and not lvl.goal_revealed()
				break
			if lvl.card_waiting():
				lvl.press_ok()
			lvl.hold_ring(lvl.ring_active())
			if lvl.goal_revealed():
				step = "flight"
				fly(lvl.ship, waypoints, pilot, route.get_meta("cruise", CRUISE))
		check(not lesson_lost, "%s: the guided steps lost the stage" % id)
		check(outcome.won == true, "%s: not finished (%s, at %s, fuel %d, hull %d)" % [id, step, lvl.ship.global_position.round(), lvl.ship.fuel, lvl.ship.health])
		lvl.free()


## A black hole kills inside the physics step, where the freeze is deferred: the stage must still
## end as a loss, with the ship left down. Only Training 6's script rescues from a black hole.
func test_black_hole_touch_loses_the_stage() -> void:
	var lvl = probe()
	var hole: GravityBody = load("res://scenes/gravity_body.tscn").instantiate()
	hole.preset = GravityBody.Preset.BLACK_HOLE
	hole.position = Vector2(400, 0)
	lvl.add_child(hole)
	var lost := []
	lvl.finished.connect(func(won: bool): lost.append(won))
	await frames(3)
	for i in 400:
		await frames(1)
		if not lost.is_empty():
			break
	await frames(300)
	check(lost == [false], "falling into a black hole must lose the stage, got %s" % [lost])
	check(not lvl.ship.visible, "the wreck must stay down once the stage is lost")


## Training 6's close call: its script beams the ship back exactly once, to where the step began.
func test_training_6_close_call_is_rescued_once() -> void:
	var lvl: Level = Progress.build("tutorial_6")
	world.add_child(lvl)
	var outcome := {"won": null}
	lvl.finished.connect(func(won: bool): outcome.won = won)
	var beams := {"n": 0}  # each beam hides the ship while its pixels stream back
	lvl.ship.visibility_changed.connect(func(): if not lvl.ship.visible: beams.n += 1)
	await frames(1)
	var start: Vector2 = lvl.ship.global_position
	var back := false
	for i in 4800:
		await frames(1)
		if outcome.won != null:
			break
		if lvl.card_waiting():
			lvl.press_ok()
		lvl.hold_ring(lvl.ring_active())
		if beams.n == 1 and lvl.ship.visible:
			back = true
			break
	await frames(3)  # the respawn lands on the next physics step
	check(outcome.won == null, "the close call must not lose the stage, got %s" % outcome.won)
	check(beams.n == 1, "the close call must beam the ship back once, not %d times" % beams.n)
	check(back and lvl.ship.global_position.distance_to(start) < 10.0, "the ship must come back at the step's start %s, not %s" % [start.round(), lvl.ship.global_position.round()])


## Training 3: a ship that runs dry after the goal shows loses the stage like a level, and is not beamed back.
func test_training_3_out_of_fuel_loses_the_stage() -> void:
	var lvl: Level = Progress.build("tutorial_3")
	world.add_child(lvl)
	lvl.ship.fuel = 10.0  # the fuel step is done once the tank holds 15 or less
	var outcome := {"won": null}
	lvl.finished.connect(func(won: bool): outcome.won = won)
	var drained := false
	for i in 900:
		await frames(1)
		if outcome.won != null:
			break
		if lvl.card_waiting():
			lvl.press_ok()
		if lvl.goal_revealed() and not drained:
			drained = true
			lvl.ship.fuel = 0.0
	check(drained, "the goal must show before the tank runs dry")
	check(outcome.won == false, "running out of fuel after the goal shows must lose the stage, got %s" % outcome.won)
	check(lvl.ship.death_cause == "Out of fuel", "the death cause must be out of fuel, got '%s'" % lvl.ship.death_cause)
	check(lvl.ship.fuel == 0.0, "the ship must not be refilled and beamed back, fuel %f" % lvl.ship.fuel)


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
