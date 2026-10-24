class_name ShipInput
extends Node
## Turns pad, keyboard, mouse and touch input into the ship's aim_point, steering, thrusting and
## align_gate. The last device used picks the scheme.

const AIM_REACH := 1000.0  # px ahead of the ship that a stick or key direction aims at
## One press aims and fires, the engine waiting for the nose (today's touch); rings are touched.
const GATED := ["finger", "mouse_click"]
## Touch with a stick or aiming finger and a fire button, read from `touch`.
const TWO_HANDED := ["stick", "finger_button"]

## The touch schemes and the mouse ones: a settings change re-picks within the family the last device used.
const TOUCH_SCHEMES := ["finger", "stick", "finger_button"]
const MOUSE_SCHEMES := ["mouse_aim", "mouse_click"]
## The name of each joypad button on the common layouts; one not listed is named by its number.
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A / Cross",
	JOY_BUTTON_B: "B / Circle",
	JOY_BUTTON_X: "X / Square",
	JOY_BUTTON_Y: "Y / Triangle",
	JOY_BUTTON_BACK: "Back / Select",
	JOY_BUTTON_GUIDE: "Guide / Home",
	JOY_BUTTON_START: "Start / Menu",
	JOY_BUTTON_LEFT_STICK: "Left stick press",
	JOY_BUTTON_RIGHT_STICK: "Right stick press",
	JOY_BUTTON_LEFT_SHOULDER: "Left bumper / L1",
	JOY_BUTTON_RIGHT_SHOULDER: "Right bumper / R1",
	JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_MISC1: "Misc 1",
	JOY_BUTTON_PADDLE1: "Paddle 1",
	JOY_BUTTON_PADDLE2: "Paddle 2",
	JOY_BUTTON_PADDLE3: "Paddle 3",
	JOY_BUTTON_PADDLE4: "Paddle 4",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}
## Per axis, the name for a negative and for a positive value.
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["Left stick left", "Left stick right"],
	JOY_AXIS_LEFT_Y: ["Left stick up", "Left stick down"],
	JOY_AXIS_RIGHT_X: ["Right stick left", "Right stick right"],
	JOY_AXIS_RIGHT_Y: ["Right stick up", "Right stick down"],
	JOY_AXIS_TRIGGER_LEFT: ["Left trigger", "Left trigger"],
	JOY_AXIS_TRIGGER_RIGHT: ["Right trigger", "Right trigger"],
}

## Emitted when the scheme changes, so the intro card can name the controls in use.
signal scheme_changed

var ship: Ship
## "finger", "mouse_click", "mouse_aim", "keys", "pad", "stick" or "finger_button".
var scheme: String
## The stick or aiming finger and fire button of the two-handed touch schemes.
var touch: TouchControls
var _fire := false
## Screen point that aims: a held finger or click, or the cursor once the mouse aims; else null.
var _pointer: Variant = null
## Whether the last tick wrote to the ship. An idle input never writes, so autopilots, tutorials
## and tests can set the ship's controls themselves.
var _applied := false


func _init(for_ship: Ship) -> void:
	ship = for_ship
	scheme = Settings.touch_scheme if DisplayServer.is_touchscreen_available() else _mouse_scheme()


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2  # above the HUD's
	add_child(layer)
	touch = TouchControls.new()
	touch.hud = get_parent().get("hud")
	layer.add_child(touch)
	touch.visible = scheme in TWO_HANDED
	Settings.changed.connect(_settings_changed)


## Releases during a pause are never seen (nor are presses), and focus loss lets go of actions
## without sending events, so both let go of everything held; the next physics tick then writes
## the release to the ship.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_fire = false
		_pointer = null
		if touch:
			touch.release()


## Where the player steers, in world space; Vector2.ZERO when not steering.
func steer_direction() -> Vector2:
	if _pointer != null:
		return (ship.get_canvas_transform().affine_inverse() * (_pointer as Vector2) - ship.global_position).normalized()
	if scheme in ["keys", "pad"]:
		return Input.get_vector(&"steer_left", &"steer_right", &"steer_up", &"steer_down").normalized()
	if scheme == "stick":
		return touch.direction.normalized()
	return Vector2.ZERO


func fire_held() -> bool:
	return _fire


func touches_rings() -> bool:
	return scheme in GATED

## The level 1 introduction, naming the controls in use: the fire bindings as they are, so a rebind shows.
func intro_hint() -> String:
	match scheme:
		"finger":
			return "Touch and hold: the ship turns toward your finger and fires its engine. Reach the green ring."
		"mouse_click":
			return "Click and hold: the ship turns toward the cursor and fires its engine. Reach the green ring."
		"mouse_aim":
			return "Move the mouse to turn the ship toward the cursor. Hold %s to fire its engine. Reach the green ring." % _fire_names()
		"stick":
			return "Drag to steer. Hold the fire button on the %s to fire its engine. Reach the green ring." % Settings.fire_side
		"finger_button":
			return "Touch to aim: the ship turns toward your finger. Hold the fire button on the %s to fire its engine. Reach the green ring." % Settings.fire_side
		_:
			return "Steer with the keys or a stick and hold %s to fire its engine. Reach the green ring." % _fire_names()

## The fire bindings as the player reads them, e.g. "Space or Left Mouse Button or A / Cross".
func _fire_names() -> String:
	var names := " or ".join(InputMap.action_get_events(&"fire").map(binding_name))
	return names if names != "" else "the fire control"  # a saved file may leave fire unbound


func _unhandled_input(event: InputEvent) -> void:
	# GUI controls consume their own events first, so a tap on a HUD button never reaches here.
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_use(Settings.touch_scheme)  # `touch` read it in _input already
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		_use(Settings.touch_scheme)
		if scheme == "finger":
			_point(event)
		return  # a touch also matches the mouse fire binding; it is not one
	if event is InputEventMouse:
		_use(_mouse_scheme())
		if scheme == "mouse_click":
			_point(event)
		elif event is InputEventMouseMotion:
			_pointer = event.position
	elif event is InputEventKey:
		if scheme != "mouse_aim" or _steers(event):
			_use("keys")  # a fire key keeps the cursor aiming
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_use("pad")  # small stick drift must not take over from the keyboard
	# Tracked from events, not polled: Input counts a click a GUI control consumed as pressed.
	if event.is_action_pressed(&"fire"):
		_fire = true
	elif event.is_action_released(&"fire"):
		_fire = false
	elif event.is_action_pressed(&"pause"):
		var hud: Hud = get_parent().get("hud")
		if hud:
			hud.toggle_pause()
			get_viewport().set_input_as_handled()  # the pause card, next in line, would resume at once


func _physics_process(_delta: float) -> void:
	if scheme in TWO_HANDED:
		_pointer = touch.aim_screen
		_fire = touch.fire
	var direction := steer_direction()
	var gated := scheme in GATED
	var active := not ship.controls_locked and (ship.accept_input or not gated) and (direction != Vector2.ZERO or _fire or _pointer != null)
	if not (active or _applied):
		return
	_applied = active  # going idle writes once, to let go of the ship
	ship.align_gate = gated or not active
	ship.thrusting = active and (_pointer != null if gated else _fire)
	ship.steering = active and not gated and direction != Vector2.ZERO
	ship.touch_screen = _pointer if active else null
	if ship.steering and _pointer == null:
		ship.aim_point = ship.global_position + direction * AIM_REACH


func _use(new_scheme: String) -> void:
	if new_scheme != scheme:
		scheme = new_scheme
		_pointer = null
		touch.visible = scheme in TWO_HANDED
		scheme_changed.emit()

## A setting changed meanwhile, as on the pause card: the pointer scheme follows it now, not at the next press.
func _settings_changed() -> void:
	if scheme in TOUCH_SCHEMES:
		_use(Settings.touch_scheme)
	elif scheme in MOUSE_SCHEMES:
		_use(_mouse_scheme())


func _steers(event: InputEvent) -> bool:
	return [&"steer_left", &"steer_right", &"steer_up", &"steer_down"].any(func(action: StringName) -> bool: return event.is_action(action))


func _mouse_scheme() -> String:
	return "mouse_aim" if Settings.mouse_aims else "mouse_click"


## A finger or click: the left button aims while held, and a drag moves the aim.
func _point(event: InputEventMouse) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer = event.position if event.pressed else null
	elif event is InputEventMouseMotion and _pointer != null:
		_pointer = event.position

## The player-facing name of a binding: keys by physical name; pads by the names of the common layouts.
static func binding_name(event: InputEvent) -> String:
	if event is InputEventKey:
		return event.as_text_physical_keycode() if event.physical_keycode != KEY_NONE else event.as_text()
	if event is InputEventJoypadButton:
		return BUTTON_NAMES.get(event.button_index, "Button %d" % event.button_index)
	if event is InputEventJoypadMotion:
		var index := 0 if event.axis_value < 0.0 else 1
		if event.axis in AXIS_NAMES:
			return AXIS_NAMES[event.axis][index]
		return "Axis %d (%s)" % [event.axis, ["negative", "positive"][index]]
	return event.as_text()
