@tool
class_name Asteroid
extends RigidBody2D
## A drifting rock with no pull of its own. Gravity bodies pull it; planets take damage when it hits them.

const RADIUS := 20.0
const MASS := 2.0
const MIN_IMPACT_SPEED := 20.0  # px/s
const PLANET_DAMAGE_PER_IMPULSE := 0.04
const MAX_SPEED := 1200.0  # Same no-tunneling bound as the ship.

## Orbit on rails: set a parent planet to circle it exactly until something hits this asteroid.
@export var orbit_parent: NodePath
@export var orbit_radius := 150.0
## rad/s; the sign sets the direction.
@export var orbit_speed := 1.0
@export var orbit_angle := 0.0

var on_rails := false
var _parent: Node2D
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
	if not orbit_parent.is_empty():
		_parent = get_node(orbit_parent)
		on_rails = true
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true
		_place_on_orbit()
		if _parent.has_signal("shattered"):
			_parent.shattered.connect(release.bind(Vector2.ZERO))


func _physics_process(delta: float) -> void:
	if not on_rails or Engine.is_editor_hint():
		return
	if not is_instance_valid(_parent):
		release(Vector2.ZERO)
		return
	orbit_angle += orbit_speed * delta
	_place_on_orbit()


func _place_on_orbit() -> void:
	global_position = _parent.global_position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius


## Leave the rails with the current orbital velocity plus `impulse`. No-op once free.
func release(impulse: Vector2) -> void:
	if not on_rails:
		return
	on_rails = false
	freeze = false
	linear_velocity = Vector2(-sin(orbit_angle), cos(orbit_angle)) * orbit_radius * orbit_speed + impulse / mass
	_previous_velocity = linear_velocity


func impact_multiplier() -> float:
	return 1.0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(MAX_SPEED)
	var velocity_change := state.linear_velocity - _previous_velocity
	_previous_velocity = state.linear_velocity
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		if collider is Asteroid and collider.on_rails:
			# Equal and opposite to what this asteroid received along the contact normal.
			var normal := state.get_contact_local_normal(i)
			collider.release.call_deferred(-velocity_change.project(normal) * mass)
		var body := collider as GravityBody
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
