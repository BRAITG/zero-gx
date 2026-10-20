extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const GOAL := "res://scenes/goal.tscn"


## A ship at the origin with a ShipInput driving it, both in the world.
func controlled(props: Dictionary = {}) -> ShipInput:
	var ship: Ship = spawn(SHIP, Vector2.ZERO, props)
	var input := ShipInput.new(ship)
	world.add_child(input)
	return input


## Through Input, as the OS delivers it: action state first, then GUI, then _unhandled_input.
func send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	send(event)


func stick_x(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	send(event)


func pad_button(button: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = down
	send(event)


## A left mouse press or release at `at` in viewport coordinates (headless window scaling differs).
## `device` DEVICE_ID_EMULATION makes it a touch, as Godot emulates one.
func click(at: Vector2, down: bool, device := 0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = at
	event.device = device
	tree.root.push_input(event, true)


func screen_centre() -> Vector2:
	return tree.root.get_visible_rect().size / 2.0


func test_keys_steer_to_heading_and_fire_ungated() -> void:
	var input := controlled()
	var ship := input.ship
	await frames(1)
	key(KEY_D, true)
	key(KEY_S, true)
	await frames(30)
	check(input.scheme == "keys", "scheme %s after a key, expected keys" % input.scheme)
	check(absf(wrapf(ship.rotation - PI / 4, -PI, PI)) < 0.05, "rotation %f, expected PI/4" % ship.rotation)
	key(KEY_SPACE, true)
	await frames(1)
	check(not ship.align_gate and ship.thrusting, "fire must thrust ungated (gate %s, thrusting %s)" % [ship.align_gate, ship.thrusting])
	key(KEY_SPACE, false)
	key(KEY_D, false)
	key(KEY_S, false)


func test_released_keys_hold_heading() -> void:
	var input := controlled()
	var ship := input.ship
	await frames(1)
	key(KEY_W, true)
	await frames(30)
	key(KEY_W, false)
	await frames(1)
	var heading := ship.rotation
	check(not ship.steering, "still steering after the keys were released")
	await frames(30)
	check(absf(ship.rotation - heading) < 0.001, "rotation moved from %f to %f with no keys held" % [heading, ship.rotation])


func test_pad_stick_steers_and_a_fires() -> void:
	var input := controlled({"rotation": PI / 2})
	var ship := input.ship
	await frames(1)
	stick_x(1.0)
	await frames(30)
	check(input.scheme == "pad", "scheme %s after the stick, expected pad" % input.scheme)
	check(absf(wrapf(ship.rotation, -PI, PI)) < 0.05, "rotation %f, expected 0" % ship.rotation)
	pad_button(JOY_BUTTON_A, true)
	await frames(1)
	check(ship.thrusting, "A must fire")
	pad_button(JOY_BUTTON_A, false)
	stick_x(0.0)


func test_small_stick_drift_keeps_the_scheme() -> void:
	var input := controlled()
	await frames(1)
	key(KEY_D, true)
	key(KEY_D, false)
	stick_x(0.3)
	await frames(1)
	check(input.scheme == "keys", "scheme %s after stick drift, expected keys" % input.scheme)
	stick_x(0.0)


func test_mouse_aims_without_click() -> void:
	var input := controlled()
	var ship := input.ship
	await frames(2)
	var move := InputEventMouseMotion.new()
	move.position = screen_centre() + Vector2(300, 0)
	tree.root.push_input(move, true)
	await frames(2)
	check(input.scheme == "mouse_aim", "scheme %s after a real mouse move, expected mouse_aim" % input.scheme)
	check(ship.steering and not ship.thrusting, "a moving mouse must steer without firing (steering %s, thrusting %s)" % [ship.steering, ship.thrusting])


func test_click_on_hud_button_does_not_fire() -> void:
	var input := controlled()
	var hud := Hud.new()
	hud.ship = input.ship
	world.add_child(hud)
	await frames(2)
	var on_button := hud.restart_button.get_global_rect().get_center()
	click(on_button, true)
	await frames(2)
	check(not input.fire_held() and not input.ship.thrusting, "a click on Restart reached the ship")
	click(on_button, false)


func test_ignored_while_controls_are_locked() -> void:
	var input := controlled({"accept_input": false})
	await frames(1)
	key(KEY_SPACE, true)
	await frames(2)
	check(not input.ship.thrusting, "fire reached a locked ship")
	check(input.fire_held(), "fire must still be tracked while locked")
	key(KEY_SPACE, false)


func test_held_finger_keeps_steering_as_the_camera_follows() -> void:
	var input := controlled()
	var ship := input.ship
	await frames(2)
	click(screen_centre() + Vector2(300, 0), true, InputEvent.DEVICE_ID_EMULATION)  # the finger then stays still
	await frames(150)
	check(input.scheme == "finger", "scheme %s after a touch, expected finger" % input.scheme)
	check(ship.position.x > 400, "ship should keep flying right, at %s" % ship.position)
	check(abs(wrapf(ship.rotation, -PI, PI)) < 0.3, "ship turned to %f rad instead of following the held finger" % ship.rotation)
	click(screen_centre() + Vector2(300, 0), false, InputEvent.DEVICE_ID_EMULATION)


## Autopilots, tutorials and tests set the ship's controls directly; an idle input must not undo them.
func test_idle_input_leaves_scripted_controls_alone() -> void:
	var lvl := Node2D.new()
	lvl.set_script(load("res://scenes/level.gd"))
	lvl.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(3000, 0)
	lvl.add_child(goal)
	world.add_child(lvl)
	check(lvl.input is ShipInput, "a Level must create its ShipInput")
	lvl.ship.aim_point = Vector2(1000, 0)
	lvl.ship.thrusting = true
	await frames(10)
	check(lvl.ship.thrusting and lvl.ship.align_gate, "an idle ShipInput overwrote the scripted controls")
