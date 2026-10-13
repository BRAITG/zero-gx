class_name Ship
extends RigidBody2D
## The player: turns toward the touch point, thrusts while the finger is down, burns fuel.

signal destroyed
signal stranded

const MAX_FUEL := 100.0
const FUEL_BURN := 10.0  # per second of thrust
const THRUST := 600.0  # force; mass is 1, so px/s²
const TURN_RATE := 6.0  # rad/s
const MAX_HEALTH := 100.0
const STRAND_SPEED := 5.0  # px/s
const STRAND_TIME := 2.0  # s
const LOOKAHEAD := 0.3  # s of velocity the camera leads by
const LOOKAHEAD_MAX := 250.0  # px
## 1/s; eases the lookahead so a bounce's velocity flip doesn't jump the view.
const LOOKAHEAD_SMOOTHING := 3.0
const RADIUS := 16.0
const DAMAGE_PER_SPEED := 0.05  # health per px/s of normal speed change
const MIN_IMPACT_SPEED := 20.0  # px/s; below this a contact is resting, not a hit
## 20 px per 60 Hz step: under half of barrier thickness + ship diameter, so no hit can tunnel.
const MAX_SPEED := 1200.0
const ENGINE_VOLUME_DB := -10.0
## Damage at which an impact plays at full volume; lighter hits are quieter.
const LOUD_IMPACT_DAMAGE := 30.0

var thrusting := false
var aim_point := Vector2.ZERO
var fuel := MAX_FUEL
var health := MAX_HEALTH

var _still_time := 0.0
var _stranded_sent := false
var _camera: Camera2D
var _engine: AudioStreamPlayer
var _previous_velocity := Vector2.ZERO
## Where the finger rests on screen; null when no touch is held. Re-projected every step,
## because the camera follows the ship and a still finger sends no new events.
var _touch_screen: Variant = null


func _ready() -> void:
	mass = 1.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	physics_material_override = load("res://physics/frictionless.tres")
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.ignore_rotation = true
	add_child(_camera)
	_engine = AudioStreamPlayer.new()
	_engine.stream = Sfx.thrust
	_engine.volume_db = ENGINE_VOLUME_DB
	add_child(_engine)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var step := state.step
	if _touch_screen != null:
		aim_point = get_canvas_transform().affine_inverse() * (_touch_screen as Vector2)
	var to_aim := aim_point - state.transform.origin
	if thrusting and to_aim.length() > 1.0:  # finger up: hold heading and coast
		var turn := wrapf(to_aim.angle() - state.transform.get_rotation(), -PI, PI)
		state.angular_velocity = clampf(turn / step, -TURN_RATE, TURN_RATE)
	else:
		state.angular_velocity = 0.0
	if thrusting and fuel > 0.0:
		state.apply_central_force(Vector2.RIGHT.rotated(state.transform.get_rotation()) * THRUST)
		fuel = maxf(fuel - FUEL_BURN * step, 0.0)
	state.linear_velocity = state.linear_velocity.limit_length(MAX_SPEED)
	if fuel == 0.0 and state.linear_velocity.length() < STRAND_SPEED:
		_still_time += step
		if _still_time >= STRAND_TIME and not _stranded_sent:
			_stranded_sent = true
			stranded.emit()
	else:
		_still_time = 0.0
	_take_impacts(state)
	queue_redraw()


## Godot 2D reports zero contact impulses for polygon contacts, so the hit strength is the
## velocity change across this step, projected on each contact's normal. One hit per step.
func _take_impacts(state: PhysicsDirectBodyState2D) -> void:
	var velocity_change := state.linear_velocity - _previous_velocity
	_previous_velocity = state.linear_velocity
	var worst := 0.0
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		var normal := state.get_contact_local_normal(i)
		if collider is Asteroid and collider.on_rails:
			# Equal and opposite to what the ship received along the contact normal.
			collider.release.call_deferred(-velocity_change.project(normal) * mass)
		var multiplier: float = collider.impact_multiplier() if collider and collider.has_method("impact_multiplier") else 0.0
		if multiplier == Impact.LETHAL:
			take_damage(health)
			return
		var speed_change := absf(velocity_change.dot(normal))
		if speed_change >= MIN_IMPACT_SPEED:
			worst = maxf(worst, speed_change * DAMAGE_PER_SPEED * multiplier)
	if worst > 0.0:
		take_damage(worst)


func _process(delta: float) -> void:
	var target := (linear_velocity * LOOKAHEAD).limit_length(LOOKAHEAD_MAX)
	_camera.offset = _camera.offset.lerp(target, 1.0 - exp(-LOOKAHEAD_SMOOTHING * delta))
	var burning := thrusting and fuel > 0.0
	if burning != _engine.playing:
		_engine.playing = burning


func _unhandled_input(event: InputEvent) -> void:
	# Touches arrive as emulated left-mouse events; GUI controls consume theirs first.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		thrusting = event.pressed
		_touch_screen = event.position if event.pressed else null
		aim_point = get_canvas_transform().affine_inverse() * event.position
	elif event is InputEventMouseMotion and _touch_screen != null:
		_touch_screen = event.position


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health > 0.0:
		Sfx.play("impact", linear_to_db(clampf(amount / LOUD_IMPACT_DAMAGE, 0.2, 1.0)))
		return
	thrusting = false
	Sfx.play("explosion")
	destroyed.emit()
	set_deferred("freeze", true)
	hide()


func _draw() -> void:
	var nose := Vector2(RADIUS * 1.4, 0)
	draw_colored_polygon(PackedVector2Array([nose, Vector2(-RADIUS, RADIUS * 0.8), Vector2(-RADIUS * 0.5, 0), Vector2(-RADIUS, -RADIUS * 0.8)]), Color("#e8f1ff"))
	if thrusting and fuel > 0.0:
		draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 0.6, RADIUS * 0.4), Vector2(-RADIUS * 2.0, 0), Vector2(-RADIUS * 0.6, -RADIUS * 0.4)]), Color("#ff9a3c"))
