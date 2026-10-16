class_name Tutorial
extends Level
## A guided stage. Subclasses override `lesson()`, a coroutine of steps:
##   await say(text)                       caption + OK; the ship holds still while it shows
##   await touch_target(direction, done)   a ring the player must touch; holding it thrusts toward it
##   await until(done, text)               a caption until `done` is true
##   reveal_goal()                         show the goal and hand the controls back
## Losing the ship mid-lesson puts it back where the current step began.

const RING_DISTANCE := 300.0  # px on screen from the ship
const RING_RADIUS := 56.0
const SCREEN_MARGIN := 90.0

## How many times the ship has been put back after dying or running dry.
var retries := 0
## Seconds the current ring has been held; see `held()`.
var held_time := 0.0
var _caption: PanelContainer
var _caption_label: Label
var _card: PanelContainer
var _card_label: Label
var _ok_pressed := false
var _ring: _Ring
var _ring_direction: Variant = null  # Vector2 or Callable -> Vector2
var _checkpoint := []  # [position, velocity, fuel] at the start of the current step
var _goal_shown := false


## The lesson's steps. Override in each tutorial.
func lesson() -> void:
	pass


func _ready() -> void:
	super._ready()
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
	_mark()
	var velocity := ship.linear_velocity
	ship.freeze = true
	_card_label.text = text
	_card.show()
	_ok_pressed = false
	while not _ok_pressed:
		await get_tree().physics_frame
	_card.hide()
	ship.freeze = false
	ship.linear_velocity = velocity


## Press the OK of the current caption card (the button calls this; tests too).
func press_ok() -> void:
	_ok_pressed = true


func touch_target(direction: Variant, done: Callable, text := "") -> void:
	_mark()
	held_time = 0.0
	_ring_direction = direction
	_ring.show()
	await until(done, text)
	_ring.hide()
	_ring_direction = null
	_ring.held = false
	ship.thrusting = false


func until(done: Callable, text := "") -> void:
	if _checkpoint.is_empty():
		_mark()
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
	var centre := (at + direction.normalized() * RING_DISTANCE).clamp(Vector2.ONE * SCREEN_MARGIN, screen - Vector2.ONE * SCREEN_MARGIN)
	_ring.position = centre - _ring.size / 2.0
	ship.thrusting = _ring.held
	if _ring.held:
		held_time += delta
		ship.aim_point = get_viewport().canvas_transform.affine_inverse() * centre


func _ship_lost() -> void:
	_retry()


func _ship_stranded() -> void:
	_retry()


func _retry() -> void:
	await get_tree().physics_frame  # after the death sequence has hidden and frozen the ship
	ship.respawn(_checkpoint[0], _checkpoint[1], _checkpoint[2])
	held_time = 0.0
	retries += 1


func _mark() -> void:
	_checkpoint = [ship.global_position, ship.linear_velocity, ship.fuel]


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
