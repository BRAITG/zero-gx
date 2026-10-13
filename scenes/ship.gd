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
const RADIUS := 16.0

var thrusting := false
var aim_point := Vector2.ZERO
var fuel := MAX_FUEL
var health := MAX_HEALTH

var _still_time := 0.0
var _stranded_sent := false
var _camera: Camera2D


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
	if aim_point == Vector2.ZERO:
		aim_point = position + Vector2.RIGHT.rotated(rotation) * 100.0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var step := state.step
	var to_aim := aim_point - state.transform.origin
	if to_aim.length() > 1.0:
		var turn := wrapf(to_aim.angle() - state.transform.get_rotation(), -PI, PI)
		state.angular_velocity = clampf(turn / step, -TURN_RATE, TURN_RATE)
	else:
		state.angular_velocity = 0.0
	if thrusting and fuel > 0.0:
		state.apply_central_force(Vector2.RIGHT.rotated(state.transform.get_rotation()) * THRUST)
		fuel = maxf(fuel - FUEL_BURN * step, 0.0)
	if fuel == 0.0 and state.linear_velocity.length() < STRAND_SPEED:
		_still_time += step
		if _still_time >= STRAND_TIME and not _stranded_sent:
			_stranded_sent = true
			stranded.emit()
	else:
		_still_time = 0.0
	queue_redraw()


func _process(_delta: float) -> void:
	_camera.offset = (linear_velocity * LOOKAHEAD).limit_length(LOOKAHEAD_MAX)


func _unhandled_input(event: InputEvent) -> void:
	# Touches arrive as emulated left-mouse events; GUI controls consume theirs first.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		thrusting = event.pressed
		aim_point = get_canvas_transform().affine_inverse() * event.position
	elif event is InputEventMouseMotion:
		aim_point = get_canvas_transform().affine_inverse() * event.position


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		thrusting = false
		destroyed.emit()
		set_deferred("freeze", true)
		hide()


func _draw() -> void:
	var nose := Vector2(RADIUS * 1.4, 0)
	draw_colored_polygon(PackedVector2Array([nose, Vector2(-RADIUS, RADIUS * 0.8), Vector2(-RADIUS * 0.5, 0), Vector2(-RADIUS, -RADIUS * 0.8)]), Color("#e8f1ff"))
	if thrusting and fuel > 0.0:
		draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 0.6, RADIUS * 0.4), Vector2(-RADIUS * 2.0, 0), Vector2(-RADIUS * 0.6, -RADIUS * 0.4)]), Color("#ff9a3c"))
