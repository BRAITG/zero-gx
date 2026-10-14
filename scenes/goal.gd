@tool
class_name Goal
extends Area2D
## Point B: the level is won when the ship enters this ring.

signal reached

const RADIUS := 80.0

var _time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	body_entered.connect(func(body: Node): if body is Ship: reached.emit())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color(0.4, 1.0, 0.6, 0.5 + 0.5 * pulse), 4.0)
	draw_circle(Vector2.ZERO, RADIUS * 0.25, Color(0.4, 1.0, 0.6, 0.35))
