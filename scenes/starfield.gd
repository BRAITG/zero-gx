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
const MAX_STREAK := 24.0  # px of streak on the nearest layer at full blur; a hint, not a smear
const STAR_SHADER := preload("res://scenes/starfield.gdshader")

## px/s of drift when nothing moves the camera, as on the menu.
@export var drift := Vector2.ZERO

## The ship whose speed blurs the stars; null (menu, editor, demo viewer) keeps them round.
var ship: Ship
var _layers: Array[_StarLayer] = []


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
		_layers.append(layer)
		parallax.add_child(layer)
		add_child(parallax)


## 0 at rest, 1 at the speed limit or during a boost.
static func blur(speed: float, boosting: bool) -> float:
	if boosting:
		return 1.0
	return clampf(speed / Tuning.max_speed, 0.0, 1.0)


func _process(_delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var b := blur(ship.linear_velocity.length(), ship.boosting)
	var dir := ship.linear_velocity.normalized() if ship.linear_velocity.length() >= 1.0 else Vector2.ZERO
	for layer in _layers:
		var streak: Vector2 = dir * b * MAX_STREAK * layer.spec[0] / 0.5
		if streak.distance_to(layer.streak) > 0.5:
			layer.streak = streak


class _StarLayer extends Node2D:
	var seed_value := 0
	var spec: Array
	var streak := Vector2.ZERO:
		set(value):
			streak = value
			_material.set_shader_parameter("streak", value)
	var _material := ShaderMaterial.new()
	var _nebulae: Array[Array] = []

	func _ready() -> void:
		_material.shader = STAR_SHADER
		var mesh := QuadMesh.new()
		mesh.size = Vector2(2, 2)
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_2D
		batch.use_colors = true
		batch.use_custom_data = true
		batch.mesh = mesh
		batch.instance_count = spec[1]
		# Shader-expanded quads must stay visible across tile edges in either streak direction.
		var margin: float = MAX_STREAK + spec[2].y + 1.0
		batch.custom_aabb = AABB(Vector3(-margin, -margin, -1), Vector3(TILE.x + margin * 2, TILE.y + margin * 2, 2))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for blob in spec[4]:
			var centre := Vector2(rng.randf() * TILE.x, rng.randf() * TILE.y)
			var radius := rng.randf_range(250.0, 520.0)
			var tint: Color = NEBULA_COLORS[rng.randi() % NEBULA_COLORS.size()]
			_nebulae.append([centre, radius, tint])
		for star in spec[1]:
			var at := Vector2(rng.randf() * TILE.x, rng.randf() * TILE.y)
			var size := rng.randf_range(spec[2].x, spec[2].y)
			var tint := Color("#cfe0ff").lerp(Color("#fff2d8"), rng.randf())
			var c := Color(tint, spec[3] * rng.randf_range(0.5, 1.0))
			batch.set_instance_transform_2d(star, Transform2D(0.0, at))
			batch.set_instance_color(star, c)
			batch.set_instance_custom_data(star, Color(size, 0, 0, 0))
		var stars := MultiMeshInstance2D.new()
		stars.multimesh = batch
		stars.material = _material
		add_child(stars)

	func _draw() -> void:
		for blob in _nebulae:
			for ring in 6:  # soft edge: stacked translucent discs
				draw_circle(blob[0], blob[1] * (1.0 - ring * 0.14), Color(blob[2], 0.035))
