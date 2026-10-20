extends "res://scenes/tutorial.gd"
## A minimal tutorial for tests: a ring down and to the right that holds the ship still until it is held.


func lesson() -> void:
	await touch_target(Vector2(1, 1), held(0.5), "Touch the ring", true)
	await until(func() -> bool: return false)
