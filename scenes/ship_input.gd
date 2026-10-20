class_name ShipInput
extends Node
## Turns pad, keyboard, mouse and touch input into the ship's aim_point, steering, thrusting and
## align_gate. The last device used picks the scheme.

const AIM_REACH := 1000.0  # px ahead of the ship that a stick or key direction aims at
## One press aims and fires, the engine waiting for the nose (today's touch); rings are touched.
const GATED := ["finger", "mouse_click"]

var ship: Ship
## "finger", "mouse_click", "mouse_aim", "keys", "pad", "stick" or "finger_button".
var scheme: String
var _fire := false
## Screen point that aims: a held finger or click, or the cursor once the mouse aims; else null.
var _pointer: Variant = null
## Whether the last tick wrote to the ship. An idle input never writes, so autopilots, tutorials
## and tests can set the ship's controls themselves.
var _applied := false


func _init(for_ship: Ship) -> void:
	ship = for_ship
	scheme = Settings.touch_scheme if DisplayServer.is_touchscreen_available() else _mouse_scheme()


## Where the player steers, in world space; Vector2.ZERO when not steering.
func steer_direction() -> Vector2:
	if _pointer != null:
		return (ship.get_canvas_transform().affine_inverse() * (_pointer as Vector2) - ship.global_position).normalized()
	if scheme in ["keys", "pad"]:
		return Input.get_vector(&"steer_left", &"steer_right", &"steer_up", &"steer_down").normalized()
	return Vector2.ZERO


func fire_held() -> bool:
	return _fire


func touches_rings() -> bool:
	return scheme in GATED


func _unhandled_input(event: InputEvent) -> void:
	# GUI controls consume their own events first, so a tap on a HUD button never reaches here.
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
		_use("keys")
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_use("pad")  # small stick drift must not take over from the keyboard
	# Tracked from events, not polled: Input counts a click a GUI control consumed as pressed.
	if event.is_action_pressed(&"fire"):
		_fire = true
	elif event.is_action_released(&"fire"):
		_fire = false
	elif event.is_action_pressed(&"pause"):
		var hud: Node = get_parent().get("hud")
		if hud and hud.has_method("toggle_pause"):
			hud.toggle_pause()


func _physics_process(_delta: float) -> void:
	var direction := steer_direction()
	var active := ship.accept_input and (direction != Vector2.ZERO or _fire or _pointer != null)
	if not (active or _applied):
		return
	_applied = active  # going idle writes once, to let go of the ship
	var gated := scheme in GATED
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


func _mouse_scheme() -> String:
	return "mouse_aim" if Settings.mouse_aims else "mouse_click"


## A finger or click: the left button aims while held, and a drag moves the aim.
func _point(event: InputEventMouse) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer = event.position if event.pressed else null
	elif event is InputEventMouseMotion and _pointer != null:
		_pointer = event.position
