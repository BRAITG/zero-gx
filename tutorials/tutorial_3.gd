extends "res://scenes/tutorial.gd"
## Training 3: fuel. Thrust costs fuel; coasting is free.


func lesson() -> void:
	await say("This time your tank is small. Watch the yellow fuel bar at the top left.")
	await touch_target(Vector2.RIGHT, func() -> bool: return ship.fuel <= 15.0, "Hold the ring to speed up.")
	await say("Every second of thrust burns fuel. Once it runs out, you have 5 seconds to finish. Let go now and coast to the end.")
