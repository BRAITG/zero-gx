extends "res://scenes/tutorial.gd"
## Training 5: gravity. A planet bends your path for free.


func lesson() -> void:
	await say("Planets pull you in, harder the closer you get. Don't touch anything: just watch your arrow.")
	await until(for_seconds(4.0), "Watch the arrow bend toward the planet.")
	await say("The planet turned you without using any fuel. Fly close past planets to swing around them, but never into them.")
