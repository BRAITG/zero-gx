extends "res://scenes/tutorial.gd"
## Training 7: stars. Huge, lethal to touch, and their pull reaches across the whole course.

@onready var _star: Node2D = find_children("*", "GravityBody", false, false)[0]


func lesson() -> void:
	await say("Below you is a star. It burns anything that touches it, and its pull reaches across the whole course. Your way to the goal runs right over it.")
	await until(for_seconds(0.7), "Feel it pull you down.")
	await touch_target(func() -> Vector2: return ship.global_position - _star.global_position, held(0.8), "Push away from the star: tap and hold the ring.", true)
	await say("Keep pushing against its pull the whole way across, and the green ring is past the star. Never let it drag you down.")
