extends "res://scenes/tutorial.gd"
## Training 4: orange walls hurt, so brake before corners, on a limited tank.


func lesson() -> void:
	await say("Orange walls hurt. The faster you hit one, the more damage you take.")
	await touch_target(Vector2.RIGHT, held(0.8), "Hold the ring to get moving.")
	await touch_target(func() -> Vector2: return -ship.linear_velocity, func() -> bool: return ship.linear_velocity.length() < 150.0, "A corner is coming. Brake: push against your motion.")
	await say("Slow down before each corner and the walls cannot hurt you much. Watch your fuel on the way.")
