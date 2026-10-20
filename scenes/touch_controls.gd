class_name TouchControls
extends Control
## The two-handed touch layouts, `Settings.touch_scheme` "stick" and "finger_button": a floating
## virtual stick or an aiming finger, and a fire button on `Settings.fire_side`. Each touch is
## tracked by its index, so both thumbs work at once.

const STICK_RADIUS := 110.0  # px
const DEADZONE := 0.15  # of STICK_RADIUS
const BUTTON_RADIUS := 90.0  # px
const MARGIN := 48.0  # px from the screen edges to the fire button

## Touches that start on its buttons are the HUD's, not the ship's.
var hud: Hud
## The virtual stick on the unit disc; zero inside the deadzone.
var direction := Vector2.ZERO
## The aiming finger's screen position (finger + button), or null.
var aim_screen: Variant = null
var fire := false
var _anchor := Vector2.ZERO  # where the stick's thumb landed
var _steer_index := -1  # the touch on the stick or aiming; -1 for none
var _fire_index := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if Settings.touch_scheme == "finger" or not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var stick := Settings.touch_scheme == "stick"
	var index: int = event.index
	if event is InputEventScreenTouch and event.pressed:
		if hud and hud.blocks(event.position):
			return
		var on_fire_side: bool = (event.position.x > size.x / 2.0) == (Settings.fire_side == "right")
		if (on_fire_side if stick else event.position.distance_to(button_centre()) <= BUTTON_RADIUS):
			if _fire_index == -1:
				_fire_index = index
				fire = true
		elif _steer_index == -1:
			_steer_index = index
			_anchor = event.position
			if not stick:
				aim_screen = event.position
	elif event is InputEventScreenTouch:
		if index == _fire_index:
			_fire_index = -1
			fire = false
		elif index == _steer_index:
			_steer_index = -1
			direction = Vector2.ZERO
			aim_screen = null
	elif index == _steer_index:
		if stick:
			var offset: Vector2 = ((event.position - _anchor) / STICK_RADIUS).limit_length(1.0)
			direction = offset if offset.length() > DEADZONE else Vector2.ZERO
		else:
			aim_screen = event.position
	queue_redraw()


func button_centre() -> Vector2:
	var x := MARGIN + BUTTON_RADIUS
	return Vector2(x if Settings.fire_side == "left" else size.x - x, size.y - MARGIN - BUTTON_RADIUS)


func _draw() -> void:
	if _steer_index != -1 and Settings.touch_scheme == "stick":
		draw_arc(_anchor, STICK_RADIUS, 0.0, TAU, 64, Style.INK_DIM, 3.0)
		draw_circle(_anchor + direction * STICK_RADIUS, STICK_RADIUS * 0.4, Color(Style.INK, 0.5))
	draw_circle(button_centre(), BUTTON_RADIUS, Color(Style.ACCENT, 0.6 if fire else 0.2))
