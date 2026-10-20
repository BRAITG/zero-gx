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


## A finger `index` pressing or lifting at `at`, in viewport coordinates.
func touch(index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	tree.root.push_input(event, true)


func drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	tree.root.push_input(event, true)


## A ShipInput in a two-handed touch scheme, with its fire button on `side`.
func two_handed(touch_scheme: String, side := "right") -> ShipInput:
	Settings.touch_scheme = touch_scheme
	Settings.fire_side = side
	return controlled()


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


func test_key_fire_keeps_mouse_aim() -> void:
	var input := controlled()
	var ship := input.ship
	await frames(2)
	var move := InputEventMouseMotion.new()
	move.position = screen_centre() + Vector2(300, 0)
	tree.root.push_input(move, true)
	key(KEY_SPACE, true)
	await frames(2)
	check(input.scheme == "mouse_aim", "scheme %s after Space with the mouse aiming, expected mouse_aim" % input.scheme)
	check(ship.steering and ship.thrusting, "the cursor must aim while Space fires (steering %s, thrusting %s)" % [ship.steering, ship.thrusting])
	key(KEY_SPACE, false)


## Godot lets go of held actions on focus loss without sending a release event.
func test_focus_loss_lets_go_of_fire() -> void:
	var input := controlled()
	await frames(1)
	key(KEY_SPACE, true)
	await frames(2)
	check(input.ship.thrusting, "control: Space must thrust")
	Input.action_release(&"fire")  # what Input.release_pressed_events() does, unexposed to scripts
	input.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(3)
	check(not input.fire_held() and not input.ship.thrusting, "fire stuck after focus loss (fire %s, thrusting %s)" % [input.fire_held(), input.ship.thrusting])
	key(KEY_SPACE, false)


## Android sends each touch twice, as a touch and an emulated mouse press; the press is not one.
func test_emulated_mouse_neither_aims_nor_fires_in_two_handed() -> void:
	for touch_scheme in ["stick", "finger_button"]:
		var input := two_handed(touch_scheme)
		await frames(1)
		var at := screen_centre() + Vector2(300, 0)
		click(at, true, InputEvent.DEVICE_ID_EMULATION)
		await frames(2)
		check(not input.fire_held() and not input.ship.thrusting and not input.ship.steering, "%s: an emulated mouse press aimed or fired (fire %s, thrusting %s, steering %s)" % [touch_scheme, input.fire_held(), input.ship.thrusting, input.ship.steering])
		click(at, false, InputEvent.DEVICE_ID_EMULATION)
		input.ship.queue_free()
		input.queue_free()
		await frames(1)


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


func test_virtual_stick_anchors_where_the_thumb_lands() -> void:
	var input := two_handed("stick")
	await frames(1)
	touch(0, Vector2(300, 500), true)
	drag(0, Vector2(300 + 110, 500))
	check(input.scheme == "stick", "scheme %s after a touch, expected stick" % input.scheme)
	check(input.touch.direction.is_equal_approx(Vector2(1, 0)), "direction %s at the stick's rim, expected (1, 0)" % input.touch.direction)
	drag(0, Vector2(300 + 10, 500))
	check(input.touch.direction == Vector2.ZERO, "direction %s inside the deadzone, expected zero" % input.touch.direction)
	drag(0, Vector2(300 + 400, 500))
	check(is_equal_approx(input.touch.direction.length(), 1.0), "direction %s past the rim, expected length 1" % input.touch.direction)
	touch(0, Vector2(300 + 400, 500), false)


func test_stick_and_button_together() -> void:
	var input := two_handed("stick")
	var ship := input.ship
	await frames(1)
	var width := input.touch.size.x
	touch(0, Vector2(300, 500), true)
	drag(0, Vector2(300, 500 - 110))
	touch(1, Vector2(width - 300, 500), true)
	await frames(2)
	check(ship.steering and ship.thrusting, "both thumbs must steer and fire (steering %s, thrusting %s)" % [ship.steering, ship.thrusting])
	check(not ship.align_gate, "the fire button must fire ungated")
	touch(1, Vector2(width - 300, 500), false)
	await frames(2)
	check(ship.steering and not ship.thrusting, "lifting the fire thumb must keep steering (steering %s, thrusting %s)" % [ship.steering, ship.thrusting])
	touch(0, Vector2(300, 500 - 110), false)


func test_sides_swap() -> void:
	var input := two_handed("stick", "left")
	await frames(1)
	touch(0, Vector2(300, 500), true)
	drag(0, Vector2(300 + 110, 500))
	await frames(2)
	check(input.touch.fire and input.ship.thrusting, "a touch on the left half must fire with the button on the left")
	check(input.touch.direction == Vector2.ZERO, "a touch on the fire half anchored the stick")
	touch(0, Vector2(300 + 110, 500), false)


func test_finger_button_aims_anywhere_but_the_button() -> void:
	var input := two_handed("finger_button")
	var ship := input.ship
	await frames(1)
	var finger := screen_centre() + Vector2(300, 0)  # the camera centres the ship
	touch(0, finger, true)
	await frames(2)
	check(ship.steering and not ship.thrusting, "a touch off the button must aim without firing (steering %s, thrusting %s)" % [ship.steering, ship.thrusting])
	check(ship.aim_point.is_equal_approx(ship.get_canvas_transform().affine_inverse() * finger), "aim_point %s, expected under the finger" % ship.aim_point)
	touch(0, finger, false)
	await frames(2)
	var aim := ship.aim_point
	var size := input.touch.size
	var button := Vector2(size.x - TouchControls.MARGIN - TouchControls.BUTTON_RADIUS, size.y - TouchControls.MARGIN - TouchControls.BUTTON_RADIUS)
	touch(1, button, true)
	await frames(2)
	check(ship.thrusting and not ship.align_gate, "a touch on the button must fire ungated")
	check(ship.aim_point == aim, "the fire button moved aim_point from %s to %s" % [aim, ship.aim_point])
	touch(1, button, false)


func test_touch_on_hud_button_is_ignored() -> void:
	var input := two_handed("stick")
	var hud := Hud.new()
	hud.ship = input.ship
	world.add_child(hud)
	input.touch.hud = hud
	await frames(2)
	var on_button := hud.restart_button.get_global_rect().get_center()
	touch(0, on_button, true)
	drag(0, on_button + Vector2(110, 0))
	await frames(2)
	check(not input.touch.fire and not input.ship.thrusting, "a touch on Restart fired")
	check(input.touch.direction == Vector2.ZERO, "a touch on Restart anchored the stick")
	touch(0, on_button + Vector2(110, 0), false)


## A real Level (so it has a HUD to pause from) with a ship at the origin and a distant goal.
func playable_level() -> Level:
	var lvl := Node2D.new()
	lvl.set_script(load("res://scenes/level.gd"))
	lvl.add_child(load(SHIP).instantiate())
	var goal: Node2D = load(GOAL).instantiate()
	goal.position = Vector2(3000, 0)
	lvl.add_child(goal)
	world.add_child(lvl)
	return lvl


func test_key_released_during_pause_stops_thrust() -> void:
	var lvl := playable_level()
	await frames(2)
	key(KEY_SPACE, true)
	await frames(2)
	check(lvl.ship.thrusting, "Space must thrust before the pause")
	for down in [true, false]:
		key(KEY_ESCAPE, down)
	await frames(1)
	check(tree.paused, "Escape must pause")
	key(KEY_SPACE, false)  # a paused ShipInput never sees this
	for down in [true, false]:
		key(KEY_ESCAPE, down)
	await frames(3)
	check(not tree.paused and not lvl.ship.thrusting, "the ship thrusts on after Space was released in the pause (paused %s, thrusting %s)" % [tree.paused, lvl.ship.thrusting])


func test_touch_released_during_pause_is_let_go() -> void:
	Settings.touch_scheme = "stick"
	Settings.fire_side = "right"
	var lvl := playable_level()
	await frames(2)
	var fire_at := Vector2(lvl.input.touch.size.x - 300, 500)
	touch(0, fire_at, true)
	await frames(2)
	check(lvl.input.touch.fire and lvl.ship.thrusting, "a touch on the fire side must fire before the pause")
	lvl.hud.toggle_pause()
	touch(0, fire_at, false)  # a paused TouchControls never sees this
	lvl.hud.toggle_pause()
	await frames(3)
	check(not lvl.input.touch.fire and not lvl.ship.thrusting, "the touch's lift in the pause was missed (fire %s, thrusting %s)" % [lvl.input.touch.fire, lvl.ship.thrusting])
	touch(1, fire_at, true)
	await frames(2)
	check(lvl.input.touch.fire and lvl.ship.thrusting, "a new touch on the fire side must fire again")
	touch(1, fire_at, false)
