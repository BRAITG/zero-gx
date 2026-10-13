@tool
class_name GravityBody
extends StaticBody2D
## A planet, black hole or star: a solid circle with inverse-square point gravity that ends at `reach`.

signal shattered
signal struck(by: Node)

enum Preset { PLANET, BLACK_HOLE, STAR }

## radius, strength (px/s² at the surface), reach, lethal
const PRESETS := {
	Preset.PLANET: [64.0, 400.0, 450.0, false],
	Preset.BLACK_HOLE: [64.0, 4000.0, 800.0, true],
	Preset.STAR: [600.0, 3000.0, 3000.0, true],
}
const COLORS := {
	Preset.PLANET: Color("#4f8a5b"),
	Preset.BLACK_HOLE: Color("#05030a"),
	Preset.STAR: Color("#ffcf4a"),
}
const SHARDS_MIN := 12
const SHARDS_MAX := 20
const SHARD_SPEED_MIN := 100.0
const SHARD_SPEED_MAX := 250.0
const SHARD_GAP := 4.0  # px between neighbouring shards on the spawn ring

var _shattering := false

@export var preset: Preset = Preset.PLANET:
	set(value):
		preset = value
		queue_redraw()
## Negative values mean "use the preset's value".
@export var radius := -1.0
@export var strength := -1.0
@export var reach := -1.0
## Only planets can be destroyed, and only by asteroid impacts.
@export var destructible := false
@export var health := 100.0


func _ready() -> void:
	var values: Array = PRESETS[preset]
	if radius < 0: radius = values[0]
	if strength < 0: strength = values[1]
	if reach < 0: reach = values[2]
	if Engine.is_editor_hint():
		return
	physics_material_override = load("res://physics/frictionless.tres")
	var body_shape := CollisionShape2D.new()
	body_shape.shape = CircleShape2D.new()
	body_shape.shape.radius = radius
	add_child(body_shape)
	var field := Area2D.new()
	field.name = "Field"
	field.monitorable = false
	field.gravity_space_override = Area2D.SPACE_OVERRIDE_COMBINE
	field.gravity_point = true
	field.gravity_point_center = Vector2.ZERO
	field.gravity_point_unit_distance = radius
	field.gravity = strength
	var field_shape := CollisionShape2D.new()
	field_shape.shape = CircleShape2D.new()
	field_shape.shape.radius = reach
	field.add_child(field_shape)
	add_child(field)


func impact_multiplier() -> float:
	return Impact.LETHAL if PRESETS[preset][3] else 1.0


func take_damage(amount: float) -> void:
	if not destructible or _shattering or preset != Preset.PLANET:
		return
	health -= amount
	if health <= 0.0:
		_shattering = true
		_shatter.call_deferred()  # Bodies cannot be added from inside a physics callback.


func _shatter() -> void:
	var rng := RandomNumberGenerator.new()
	var count := rng.randi_range(SHARDS_MIN, SHARDS_MAX)
	# Ring large enough that neighbouring shards do not overlap at spawn.
	var ring := maxf(radius + Asteroid.RADIUS + SHARD_GAP, count * (2.0 * Asteroid.RADIUS + SHARD_GAP) / TAU)
	var scene: PackedScene = load("res://scenes/asteroid.tscn")
	for k in count:
		var direction := Vector2.RIGHT.rotated(TAU * k / count)
		var shard: Asteroid = scene.instantiate()
		shard.position = position + direction * ring
		shard.linear_velocity = direction * rng.randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX)
		get_parent().add_child(shard)
	shattered.emit()
	queue_free()


func _draw() -> void:
	var r: float = radius if radius > 0 else PRESETS[preset][0]
	draw_circle(Vector2.ZERO, r, COLORS[preset])
	if preset == Preset.BLACK_HOLE:
		draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 64, Color("#b48cff"), 3.0)
	if Engine.is_editor_hint():
		var d: float = reach if reach > 0 else PRESETS[preset][2]
		draw_arc(Vector2.ZERO, d, 0.0, TAU, 96, Color(1, 1, 1, 0.15), 2.0)
