extends "res://scenes/tutorial.gd"
## A minimal tutorial for tests: one ring to the right, then wait forever.


func lesson() -> void:
	await touch_target(Vector2.RIGHT, held(0.5), "Touch the ring")
	await until(func() -> bool: return false)
