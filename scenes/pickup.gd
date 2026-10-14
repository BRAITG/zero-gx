@tool
class_name Pickup
extends Area2D
## A one-shot ship upgrade (or downgrade). Only the ship collects it; asteroids pass through.

enum Kind { THRUST_UP, THRUST_DOWN, BOOST }

const RADIUS := 28.0
const COLORS := {Kind.THRUST_UP: Color("#5be37d"), Kind.THRUST_DOWN: Color("#b07cff"), Kind.BOOST: Color("#ff9a3c")}
const PULSE_SPEED := 4.0  # rad/s

@export var kind: Kind = Kind.THRUST_UP:
	set(value):
		kind = value
		queue_redraw()

var _time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body is Ship:
		return
	match kind:
		Kind.THRUST_UP: body.apply_power(Tuning.power_up)
		Kind.THRUST_DOWN: body.apply_power(Tuning.power_down)
		Kind.BOOST: body.start_boost()
	Sfx.play(["power_up", "power_down", "boost"][kind])
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var color: Color = COLORS[kind]
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	draw_circle(Vector2.ZERO, RADIUS, Color(color, 0.12 + 0.1 * pulse))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(color, 0.6 + 0.4 * pulse), 3.0, true)
	match kind:
		Kind.THRUST_UP, Kind.THRUST_DOWN:
			var flip := 1.0 if kind == Kind.THRUST_UP else -1.0
			for offset: float in [-5.0, 5.0]:
				var y := offset * flip
				draw_polyline(PackedVector2Array([Vector2(-10, y + 5 * flip), Vector2(0, y - 5 * flip), Vector2(10, y + 5 * flip)]), color, 3.0, true)
		Kind.BOOST:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -15), Vector2(8, 3), Vector2(0, 13), Vector2(-8, 3)]), color)
