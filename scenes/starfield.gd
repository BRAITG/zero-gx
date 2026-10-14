class_name Starfield
extends Node2D
## Endless parallax stars behind everything: they show motion when no wall is in view.
## Add one to a scene; with no camera (the menu) it drifts on its own.

const TILE := Vector2(2048, 2048)  # each layer repeats every tile
## scroll scale (closer layers move more), star count, star radius range, brightness, nebula blobs.
const LAYERS := [
	[0.08, 140, Vector2(0.8, 1.4), 0.35, 5],
	[0.25, 90, Vector2(1.0, 1.8), 0.55, 0],
	[0.5, 45, Vector2(1.4, 2.4), 0.85, 0],
]
const NEBULA_COLORS := [Color("#3a2a7a"), Color("#1d4a7a"), Color("#5a2050")]

## px/s of drift when nothing moves the camera, as on the menu.
@export var drift := Vector2.ZERO


func _ready() -> void:
	z_index = -100
	for i in LAYERS.size():
		var spec: Array = LAYERS[i]
		var parallax := Parallax2D.new()
		parallax.scroll_scale = Vector2.ONE * spec[0]
		parallax.repeat_size = TILE
		parallax.repeat_times = 3
		parallax.autoscroll = drift * spec[0]
		var layer := _StarLayer.new()
		layer.seed_value = 7 + i
		layer.spec = spec
		parallax.add_child(layer)
		add_child(parallax)


class _StarLayer extends Node2D:
	var seed_value := 0
	var spec: Array

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for blob in spec[4]:
			var centre := Vector2(rng.randf() * TILE.x, rng.randf() * TILE.y)
			var radius := rng.randf_range(250.0, 520.0)
			var tint: Color = NEBULA_COLORS[rng.randi() % NEBULA_COLORS.size()]
			for ring in 6:  # soft edge: stacked translucent discs
				draw_circle(centre, radius * (1.0 - ring * 0.14), Color(tint, 0.035))
		for star in spec[1]:
			var at := Vector2(rng.randf() * TILE.x, rng.randf() * TILE.y)
			var size := rng.randf_range(spec[2].x, spec[2].y)
			var tint := Color("#cfe0ff").lerp(Color("#fff2d8"), rng.randf())
			draw_circle(at, size, Color(tint, spec[3] * rng.randf_range(0.5, 1.0)))
