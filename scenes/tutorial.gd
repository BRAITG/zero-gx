class_name Tutorial
extends Level
## A guided stage. Subclasses override `lesson()`, a coroutine of steps:
##   await say(text)                       caption + OK; the ship holds still while it shows
##   await touch_target(direction, done)   a ring the player must touch; holding it thrusts toward it
##                                         (sticks, keys, mouse: fire aimed within 90° of it holds it)
##   await until(done, text)               a caption until `done` is true
##   reveal_goal()                         show the goal and hand the controls back
## Losing the ship ends the stage like a level, and Retry restarts it. Only Training 6's scripted close call rescues.

const RING_DISTANCE := 300.0  # px on screen from the ship
const RING_RADIUS := 56.0
const SCREEN_MARGIN := 90.0
const RING_ASSIST_DEGREES := 90.0  # a stick, key or cursor this near the ring, with fire held, counts as holding it
## Ring captions for sticks, keys and the mouse, applied in order.
const RING_WORDS := {
	"Touch and hold the ring": "Point at the ring and hold fire",
	"tap and hold the ring": "point at the ring and hold fire",
	"Hold the ring": "Point at the ring and hold fire",
	"hold the ring": "point at the ring and hold fire",
}
const BITS := 48  # pixels the ship breaks into for the rescue
const BIT_SIZE := 4.0
const SCATTER := 0.35  # s the pixels burst apart before they travel
const TRAVEL := 1.2  # s for the pixels to stream back to the start

## Seconds the current ring has been held; see `held()`.
var held_time := 0.0
var _caption: PanelContainer
var _caption_label: Label
var _card: PanelContainer
var _card_label: Label
var _ok_pressed := false
var _ring: _Ring
var _ring_direction: Variant = null  # Vector2 or Callable -> Vector2
var _goal_shown := false
var _paused_velocity: Variant = null  # Vector2 while a `wait` ring holds the ship, for a touch on the ring
var _step_waits := false  # the current ring pauses the ship until it is touched


## The lesson's steps. Override in each tutorial.
func lesson() -> void:
	pass


func _ready() -> void:
	super._ready()
	process_physics_priority = 1  # after ShipInput, so a ring's assist overrides what it just wrote
	goal.hide()
	goal.set_deferred("monitoring", false)
	ship.accept_input = false
	_build_ui()
	_run.call_deferred()


func _show_intro() -> void:
	pass


func _run() -> void:
	await lesson()
	if not _goal_shown:
		reveal_goal()


func say(text: String) -> void:
	var velocity := ship.linear_velocity
	ship.freeze = true
	_card_label.text = text
	_card.show()
	Style.focus_first(_card)
	_ok_pressed = false
	while not _ok_pressed:
		await get_tree().physics_frame
	_card.hide()
	ship.freeze = false
	ship.linear_velocity = velocity


## Press the OK of the current caption card (the button calls this; tests too).
func press_ok() -> void:
	_ok_pressed = true


## `wait`: the ship holds still until the ring is first touched, so there is time to react.
func touch_target(direction: Variant, done: Callable, text := "", wait := false) -> void:
	held_time = 0.0
	_ring_direction = direction
	_ring.show()
	_step_waits = wait
	if wait:
		_hold_still()
	if not input.touches_rings():
		for touch_words in RING_WORDS:
			text = text.replace(touch_words, RING_WORDS[touch_words])
	await until(done, text)
	_step_waits = false
	_ring.hide()
	_ring_direction = null
	_ring.held = false
	ship.thrusting = false


## Whether the ship is still waiting for the first touch on a `wait` ring.
func waiting() -> bool:
	return _paused_velocity != null


## What the ship moves at: while a `wait` ring holds it still, the velocity it gets back when released.
func motion() -> Vector2:
	return ship.linear_velocity if _paused_velocity == null else _paused_velocity


func _hold_still() -> void:
	_paused_velocity = ship.linear_velocity
	ship.anchor = ship.global_position


func until(done: Callable, text := "") -> void:
	_caption_label.text = text
	_caption.visible = text != ""
	while not done.call():
		await get_tree().physics_frame
	_caption.hide()


## A `done` condition: the current ring has been held for `seconds`.
func held(seconds: float) -> Callable:
	return func() -> bool: return held_time >= seconds


## A `done` condition: true once `seconds` of play have passed since it was made.
func for_seconds(seconds: float) -> Callable:
	var elapsed := {"s": 0.0}  # a dictionary, so the lambda can add to it
	return func() -> bool:
		elapsed.s += get_physics_process_delta_time()
		return elapsed.s >= seconds


func reveal_goal() -> void:
	_goal_shown = true
	goal.show()
	goal.monitoring = true
	ship.accept_input = true


## Whether a ring is waiting for a touch, and where it is on screen (for tests and drivers).
func ring_active() -> bool:
	return _ring.visible


func ring_centre() -> Vector2:
	return _ring.position + _ring.size / 2.0


## Hold or release the ring as a finger would.
func hold_ring(down: bool) -> void:
	_ring.held = down and _ring.visible


func card_waiting() -> bool:
	return _card.visible


func goal_revealed() -> bool:
	return _goal_shown


func _physics_process(delta: float) -> void:
	if _ring_direction == null:
		return
	var screen := get_viewport_rect().size
	var at := get_viewport().canvas_transform * ship.global_position
	var direction: Vector2 = _ring_direction.call() if _ring_direction is Callable else _ring_direction
	var top := _caption.get_global_rect().end.y + RING_RADIUS if _caption.visible else SCREEN_MARGIN  # never under the caption
	var centre := (at + direction.normalized() * RING_DISTANCE).clamp(Vector2(SCREEN_MARGIN, top), screen - Vector2.ONE * SCREEN_MARGIN)
	_ring.position = centre - _ring.size / 2.0
	var ring_world: Vector2 = get_viewport().canvas_transform.affine_inverse() * centre
	var assisted := false
	if not (_ring.held or input.touches_rings()) and input.fire_held():
		var aim := input.steer_direction()
		if aim == Vector2.ZERO:
			aim = Vector2.from_angle(ship.global_rotation)  # not steering: the nose is the aim
		assisted = aims_at(aim, ring_world - ship.global_position)
	var holding := _ring.held or assisted
	if holding or waiting() or input.touches_rings():  # otherwise ShipInput's fire stands
		ship.thrusting = holding
	if holding and waiting():  # the first touch lets the ship go on
		ship.anchor = null
		ship.linear_velocity = _paused_velocity
		_paused_velocity = null
	if holding:
		held_time += delta
		ship.aim_point = ring_world
	if assisted:  # pull the aim in over the stick, keys or cursor ShipInput just set
		ship.steering = true
		ship.touch_screen = null


## Whether an aim direction points within RING_ASSIST_DEGREES of the way to the ring.
static func aims_at(aim: Vector2, to_ring: Vector2) -> bool:
	return aim != Vector2.ZERO and absf(aim.angle_to(to_ring)) <= deg_to_rad(RING_ASSIST_DEGREES)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_caption = PanelContainer.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.hide()
	layer.add_child(_caption)
	_caption_label = _wrapped_label()
	_caption.add_child(_caption_label)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 80)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.hide()
	layer.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_card.add_child(column)
	_card_label = _wrapped_label()
	column.add_child(_card_label)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(200, 60)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(Sfx.play.bind("tap"))
	ok.pressed.connect(press_ok)
	column.add_child(ok)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ring = _Ring.new()
	_ring.hide()
	layer.add_child(_ring)


func _wrapped_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 700
	label.add_theme_font_size_override("font_size", 28)
	return label


## A rescue: the ship breaks into pixels that stream to `at` and gather there, ready to rebuild.
## The ship stays hidden and frozen meanwhile; it rides along with the pixels so the camera follows.
func beam_to(at: Vector2) -> void:
	var from := ship.global_position
	ship.freeze = true
	ship.hide()
	Sfx.play("power_down")
	var tween := create_tween().set_parallel()
	tween.tween_property(ship, "global_position", at, TRAVEL).set_delay(SCATTER).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in BITS:
		var bit := ColorRect.new()
		bit.size = Vector2.ONE * BIT_SIZE
		bit.color = Ship.HULL if i % 3 else Ship.HULL_EDGE
		bit.z_index = 20
		var home := Vector2(randf_range(-1.0, 1.4), randf_range(-0.8, 0.8)).rotated(ship.global_rotation) * Ship.RADIUS  # its spot in the ship
		bit.position = from + home
		add_child(bit)
		var burst := from + home * 2.5 + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 70.0)
		tween.tween_property(bit, "position", burst, SCATTER).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(bit, "position", at + home, TRAVEL * randf_range(0.7, 1.0)).set_delay(SCATTER + randf() * TRAVEL * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(bit.queue_free).set_delay(SCATTER + TRAVEL * 1.3)
	await tween.finished


## The touch target: a pulsing ring that counts a finger held on it.
class _Ring extends Control:
	var held := false
	var _time := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2.ONE * RING_RADIUS * 2.0
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			held = event.pressed
			accept_event()

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		var tint := Color("#3aa0ff")
		draw_circle(c, RING_RADIUS * (0.55 if held else 0.4), Color(tint, 0.35 + 0.25 * pulse))
		draw_arc(c, RING_RADIUS * (0.8 + 0.15 * pulse), 0.0, TAU, 48, tint, 4.0, true)
