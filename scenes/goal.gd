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
	var green := Color(0.4, 1.0, 0.6)
	for k in 3:  # rings born at the core, fading as they reach the edge
		var f := fmod(_time * 0.6 + k / 3.0, 1.0)
		draw_arc(Vector2.ZERO, RADIUS * f, 0.0, TAU, 48, Color(green, 0.6 * (1.0 - f)), 3.0, true)
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color(green, 0.6 + 0.4 * pulse), 4.0, true)
	for k in 4:
		draw_circle(Vector2.ZERO, RADIUS * (0.32 - k * 0.07), Color(green, 0.18 + k * 0.12))
