extends "res://scenes/tutorial.gd"
## Training 4: dangerous walls. Orange hurts, so brake before corners; red destroys on contact.

const CORNER_WALL_X := 1525.0  # the orange wall the first straight runs into
const BRAKE_DISTANCE := 400.0  # px before it where the lesson asks for the brake; it pauses until then


func lesson() -> void:
	await say("Orange walls hurt. The faster you hit one, the more damage you take.")
	await touch_target(Vector2.RIGHT, held(0.8), "Hold the ring to get moving.")
	await until(func() -> bool: return ship.global_position.x > CORNER_WALL_X - BRAKE_DISTANCE, "Coast toward the corner.")
	await touch_target(func() -> Vector2: return -motion(), func() -> bool: return not waiting() and ship.linear_velocity.length() < 150.0, "The wall is close. Brake: push against your motion.", true)
	await say("Slow down before each corner and the walls cannot hurt you much. Watch your fuel on the way.")
	await say("Above the corner there is a red gate. Red walls destroy your ship on contact: fly through the middle.")
