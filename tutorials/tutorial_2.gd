extends "res://scenes/tutorial.gd"
## Training 2: walls. An angled bounce off a blue wall; only the head-on part of the speed hurts.


func lesson() -> void:
	await say("Courses are lined with walls. Blue walls bounce you back.")
	await touch_target(Vector2(1, 1), func() -> bool: return ship.linear_velocity.y < -20.0, "Fly into the floor at an angle. Hold the ring.")
	await say("You bounced off at about the angle you came in, and kept most of your speed.")
	await say("Only the speed straight into a wall hurts: glancing hits barely scratch, head-on hits at speed do. Now follow the corridor up to the green ring.")
