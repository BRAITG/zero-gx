extends "res://scenes/tutorial.gd"
## Training 2: walls. Blue walls bounce you without harm.


func lesson() -> void:
	await say("Courses are lined with walls. Blue walls are safe: you bounce off them.")
	await touch_target(Vector2.RIGHT, func() -> bool: return ship.linear_velocity.x < -20.0, "Fly into the wall ahead. Hold the ring.")
	await say("You bounced and kept most of your speed. Now follow the corridor up to the green ring.")
