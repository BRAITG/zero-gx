@tool
class_name Barrier
extends StaticBody2D
## A glowing energy wall. Edit the child Line2D `Shape` points in the editor; collision follows them.

enum Kind { BLUE, ORANGE, RED }

const MULTIPLIERS := {Kind.BLUE: 0.1, Kind.ORANGE: 1.0, Kind.RED: Impact.LETHAL}
const COLORS := {Kind.BLUE: Color("#3aa0ff"), Kind.ORANGE: Color("#ff8a1f"), Kind.RED: Color("#a00010")}
const WIDTHS := {Kind.BLUE: 6.0, Kind.ORANGE: 6.0, Kind.RED: 9.0}
const BARRIER_BOUNCE := 0.8
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


func _style() -> void:
	var line := get_node_or_null("Shape") as Line2D
	if line:
		line.default_color = COLORS[kind]
		line.width = WIDTHS[kind]
		line.closed = closed
