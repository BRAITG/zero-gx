extends "res://tests/test_case.gd"


## Proves zero gravity, zero damping, and the fixed 60 FPS step the other tests rely on.
func test_free_body_coasts_in_a_straight_line() -> void:
	var body := RigidBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	body.add_child(shape)
	body.linear_velocity = Vector2(60, 0)
	world.add_child(body)
	await frames(60)
	check(abs(body.position.x - 60.0) < 1.5, "x after 1 s = %f, expected 60" % body.position.x)
	check(abs(body.position.y) < 0.01, "y drifted to %f" % body.position.y)
