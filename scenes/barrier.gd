@tool
class_name Barrier
extends StaticBody2D
## A glowing energy wall. Edit the child Line2D `Shape` points in the editor; collision follows them.

enum Kind { BLUE, ORANGE, RED }

const MULTIPLIERS := {Kind.BLUE: 0.1, Kind.ORANGE: 1.0, Kind.RED: Impact.LETHAL}
const COLORS := {Kind.BLUE: Color("#3aa0ff"), Kind.ORANGE: Color("#ff8a1f"), Kind.RED: Color("#ff1028")}
## Width of the bright core.
const WIDTHS := {Kind.BLUE: 4.0, Kind.ORANGE: 4.0, Kind.RED: 6.0}
const GLOW_WIDTH := 8.0  # multiple of the core width
const GLOW_ALPHA := 0.6
const CORE_WHITENESS := 0.35
const PULSE_SPEED := 3.0  # rad/s
const PULSE_DEPTH := 0.25  # fraction of glow alpha
## Godot adds both bodies' bounce: 0.4 here + 0.4 on ships and asteroids = 0.8 off a barrier.
const BARRIER_BOUNCE := 0.4
## Collision thickness. Zero-width segments let a fast ship's center land on the line and pass.
const THICKNESS := 16.0

@export var kind: Kind = Kind.BLUE:
	set(value):
		kind = value
		_style()
## Also connect the last point back to the first.
@export var closed := false:
	set(value):
		closed = value
		_style()

var _glow: Line2D


func _ready() -> void:
	_style()
	if Engine.is_editor_hint():
		return
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = BARRIER_BOUNCE
	physics_material_override = material
	var points: PackedVector2Array = $Shape.points
	var count := points.size() if closed else points.size() - 1
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var side := (b - a).orthogonal().normalized() * THICKNESS * 0.5
		var slab := ConvexPolygonShape2D.new()
		slab.points = PackedVector2Array([a + side, b + side, b - side, a - side])
		var shape := CollisionShape2D.new()
		shape.shape = slab
		add_child(shape)


func impact_multiplier() -> float:
	return MULTIPLIERS[kind]


func _process(_delta: float) -> void:
	# Pulse the glow; each wall gets its own phase so they shimmer out of step.
	var t := Time.get_ticks_msec() * 0.001 * PULSE_SPEED + get_instance_id() % 7
	if _glow:
		_glow.modulate.a = 1.0 - PULSE_DEPTH * (0.5 + 0.5 * sin(t))


func _style() -> void:
	var line := get_node_or_null("Shape") as Line2D
	if not line:
		return
	line.default_color = COLORS[kind].lerp(Color.WHITE, CORE_WHITENESS)
	line.width = WIDTHS[kind]
	line.closed = closed
	if _glow:
		_glow.free()
	_glow = line.duplicate() as Line2D
	_glow.width = WIDTHS[kind] * GLOW_WIDTH
	_glow.default_color = Color(COLORS[kind], GLOW_ALPHA)
	_glow.begin_cap_mode = Line2D.LINE_CAP_NONE  # round caps smear the gradient into a blob
	_glow.end_cap_mode = Line2D.LINE_CAP_NONE
	# Fades to transparent across the line's width: Line2D maps texture V across it.
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 0))
	falloff.set_color(1, Color(1, 1, 1, 0))
	falloff.add_point(0.5, Color.WHITE)
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill_to = Vector2(0, 1)
	_glow.texture = texture
	_glow.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = additive
	add_child(_glow, false, Node.INTERNAL_MODE_FRONT)  # internal: never saved, drawn under Shape
