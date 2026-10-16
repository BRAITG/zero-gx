extends "res://scenes/tutorial.gd"
## Training 6: black holes and stars. Lethal to touch, and they pull far harder than planets.

@onready var _hole: Node2D = $BlackHole


func lesson() -> void:
	await say("Black holes pull far harder than planets, and anything that touches one is gone. Don't touch anything: watch your arrow.")
	await until(for_seconds(2.0), "Watch the black hole pull you in.")
	await touch_target(func() -> Vector2: return ship.global_position - _hole.global_position, func() -> bool: return ship.global_position.distance_to(_hole.global_position) > 950.0, "Push away from it! Hold the ring.")
	await say("Stars burn anything that touches them, and their pull reaches across a whole course. There is one off to the right: you will feel it on the way to the green ring.")
