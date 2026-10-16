extends "res://scenes/tutorial.gd"
## Training 1: no friction. Velocity, coasting, adding thrust sideways, and braking.


func lesson() -> void:
	await say("Your ship has a single engine. Let's learn to fly it.")
	await touch_target(Vector2.RIGHT, held(0.6), "Touch and hold the ring.")
	await say("The white arrow is your velocity: the direction you are moving, and how fast.")
	await until(for_seconds(2.0), "Now just watch.")
	await say("Nothing slowed you down. Space has no friction: you keep moving, and it costs no fuel.")
	await touch_target(Vector2.DOWN, held(0.6), "Touch and hold the ring below you.")
	await say("You did not turn downward. Your sideways motion is still there: the engine only adds to your velocity.")
	await touch_target(func() -> Vector2: return -ship.linear_velocity, func() -> bool: return ship.linear_velocity.length() < 40.0, "To stop, push against your motion. Hold the ring.")
	await say("Braking in space means accelerating the other way. Now fly into the green ring.")
