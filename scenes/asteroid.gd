@tool
class_name Asteroid
extends RigidBody2D
## A drifting rock with no pull of its own. Gravity bodies pull it; planets take damage when it hits them.

const RADIUS := 20.0
const MASS := 2.0
const MIN_IMPACT_SPEED := 20.0  # px/s
const PLANET_DAMAGE_PER_IMPULSE := 0.04
const MAX_SPEED := 1200.0  # Same no-tunneling bound as the ship.

var _previous_velocity := Vector2.ZERO
var _outline := PackedVector2Array()


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) if Engine.is_editor_hint() else get_instance_id()
	for i in 8:
		_outline.append(Vector2.RIGHT.rotated(TAU * i / 8.0) * RADIUS * rng.randf_range(0.8, 1.2))
	if Engine.is_editor_hint():
		return
	mass = MASS
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	physics_material_override = load("res://physics/frictionless.tres")
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	_previous_velocity = linear_velocity


func impact_multiplier() -> float:
	return 1.0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(MAX_SPEED)
	var velocity_change := state.linear_velocity - _previous_velocity
	_previous_velocity = state.linear_velocity
	for i in state.get_contact_count():
		var body := state.get_contact_collider_object(i) as GravityBody
		if body == null:
			continue
		if body.impact_multiplier() == Impact.LETHAL:
			queue_free()
			return
		body.struck.emit(self)
		var speed_change := absf(velocity_change.dot(state.get_contact_local_normal(i)))
		if speed_change >= MIN_IMPACT_SPEED:
			body.take_damage(speed_change * mass * PLANET_DAMAGE_PER_IMPULSE)


func _draw() -> void:
	draw_colored_polygon(_outline, Color("#8a8178"))
