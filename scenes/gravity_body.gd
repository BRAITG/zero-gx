@tool
class_name GravityBody
extends StaticBody2D
## A planet, black hole or star: a solid circle with inverse-square point gravity that ends at `reach`.

signal shattered
signal struck(by: Node)

enum Preset { PLANET, BLACK_HOLE, STAR }

## radius, strength (px/s² at the surface), reach, lethal
const PRESETS := {
	Preset.PLANET: [64.0, 3200.0, 450.0, false],
	Preset.BLACK_HOLE: [64.0, 16000.0, 800.0, true],
	Preset.STAR: [600.0, 3000.0, 3000.0, true],
}
## Planet hues, picked per planet from its position so neighbours differ.
const PLANET_COLORS := [Color("#3f7a52"), Color("#2f6f8f"), Color("#8f6f35"), Color("#7a4466")]
const STAR_COLOR := Color("#ffcf4a")
const STAR_CORE := Color("#fff3c4")
const FLARE_COLORS := [Color("#ff8a2a"), Color("#ffb347")]
const DISC_EDGES := 1024
const FLAME_SPACING := 36.0  # px of rim per flame
const FLAME_LENGTH := Vector2(25, 70)  # px, flickering between
const PROMINENCE_SIZE := Vector2(50, 130)  # px radius, rising and falling
const STAR_PROMINENCES := 7
const DISK_COLORS := [Color("#ff9a4a"), Color("#c46cff"), Color("#ffd8a8")]
const SHARDS_MIN := 12
const SHARDS_MAX := 20
const SHARD_SPEED_MIN := 100.0
const SHARD_SPEED_MAX := 250.0
const SHARD_GAP := 4.0  # px between neighbouring shards on the spawn ring
## Debug field disc: opacity grows with the square root of the pull, so weak edges stay visible.
const FIELD_REFERENCE_PULL := 4000.0  # px/s² drawn at full opacity
const FIELD_MAX_ALPHA := 0.35
const FIELD_BANDS := 32

var _shattering := false
var _time := 0.0

@export var preset: Preset = Preset.PLANET:
	set(value):
		preset = value
		queue_redraw()
static var _unit_disc: ArrayMesh  # see _disc()
## Negative values mean "use the preset's value".
@export var radius := -1.0
@export var strength := -1.0
@export var reach := -1.0
## Only planets can be destroyed, and only by asteroid impacts.
@export var destructible := false
@export var health := 100.0


func _ready() -> void:
	var values: Array = PRESETS[preset]
	if radius < 0: radius = values[0]
	if strength < 0: strength = values[1]
	if reach < 0: reach = values[2]
	if preset == Preset.STAR:
		z_index = 1  # a star's edge burns over the walls it crosses
		add_to_group("stars")  # ships near one take heat damage
	if Engine.is_editor_hint():
		return
	physics_material_override = load("res://physics/frictionless.tres")
	var body_shape := CollisionShape2D.new()
	body_shape.shape = CircleShape2D.new()
	body_shape.shape.radius = radius
	add_child(body_shape)
	var field := Area2D.new()
	field.name = "Field"
	field.monitorable = false
	field.gravity_space_override = Area2D.SPACE_OVERRIDE_COMBINE
	field.gravity_point = true
	field.gravity_point_center = Vector2.ZERO
	field.gravity_point_unit_distance = radius
	_apply_gravity_tuning(field)
	Tuning.changed.connect(_apply_gravity_tuning.bind(field))
	var field_shape := CollisionShape2D.new()
	field_shape.shape = CircleShape2D.new()
	field_shape.shape.radius = reach
	field.add_child(field_shape)
	add_child(field)


func _apply_gravity_tuning(field: Area2D) -> void:
	field.gravity = _surface_pull()
	queue_redraw()  # the field disc shows planet_gravity and the overlay toggle


func _surface_pull() -> float:
	match preset:
		Preset.PLANET: return strength * Tuning.planet_gravity
		Preset.BLACK_HOLE: return strength * Tuning.black_hole_gravity
	return strength


## Opacity of the debug field disc at `distance` from the centre; 0 beyond reach.
func field_alpha(distance: float) -> float:
	if distance > reach:
		return 0.0
	var pull := _surface_pull() * pow(radius / maxf(distance, radius), 2)
	return FIELD_MAX_ALPHA * sqrt(minf(pull / FIELD_REFERENCE_PULL, 1.0))


func impact_multiplier() -> float:
	return Impact.LETHAL if PRESETS[preset][3] else 1.0


func take_damage(amount: float) -> void:
	if not destructible or _shattering or preset != Preset.PLANET:
		return
	health -= amount
	if health <= 0.0:
		_shattering = true
		_shatter.call_deferred()  # Bodies cannot be added from inside a physics callback.


func _shatter() -> void:
	var rng := RandomNumberGenerator.new()
	var count := rng.randi_range(SHARDS_MIN, SHARDS_MAX)
	# Ring large enough that neighbouring shards do not overlap at spawn.
	var ring := maxf(radius + Asteroid.RADIUS + SHARD_GAP, count * (2.0 * Asteroid.RADIUS + SHARD_GAP) / TAU)
	var scene: PackedScene = load("res://scenes/asteroid.tscn")
	for k in count:
		var direction := Vector2.RIGHT.rotated(TAU * k / count)
		var shard: Asteroid = scene.instantiate()
		shard.position = position + direction * ring
		shard.linear_velocity = direction * rng.randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX)
		get_parent().add_child(shard)
	shattered.emit()
	queue_free()


func _draw() -> void:
	var r: float = radius if radius > 0 else PRESETS[preset][0]
	if not Engine.is_editor_hint() and Tuning.show_overlays:
		var band := (reach - r) / FIELD_BANDS
		for i in FIELD_BANDS:
			var middle := r + band * (i + 0.5)
			draw_arc(Vector2.ZERO, middle, 0.0, TAU, 96, Color(1, 1, 1, field_alpha(middle)), band)
	match preset:
		Preset.PLANET: _draw_planet(r)
		Preset.BLACK_HOLE: _draw_black_hole(r)
		Preset.STAR: _draw_star(r)
	if Engine.is_editor_hint():
		var d: float = reach if reach > 0 else PRESETS[preset][2]
		draw_arc(Vector2.ZERO, d, 0.0, TAU, 96, Color(1, 1, 1, 0.15), 2.0)


func _process(delta: float) -> void:
	if preset != Preset.PLANET:  # black holes spin and stars pulse
		_time += delta
		queue_redraw()


## A lit sphere: lighter, smaller discs stacked toward the light (top left), and a thin atmosphere.
func _draw_planet(r: float) -> void:
	var base: Color = PLANET_COLORS[absi(int(position.x * 7.0 + position.y * 13.0)) % PLANET_COLORS.size()]
	draw_circle(Vector2.ZERO, r, base.darkened(0.45))
	for k in 7:
		var f := k / 7.0
		draw_circle(Vector2(-0.28, -0.28) * r * f, r * (1.0 - f * 0.72), base.lerp(base.lightened(0.45), f))
	draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 96, Color(base.lightened(0.5), 0.55), 3.0, true)
	draw_arc(Vector2.ZERO, r + 7.0, 0.0, TAU, 96, Color(base.lightened(0.4), 0.14), 8.0, true)


## A black disc ringed by a bright photon ring and a turning accretion disk.
func _draw_black_hole(r: float) -> void:
	for ring in 3:
		var radius := r * (1.35 + ring * 0.22)
		for k in 6:
			var start := _time * (1.4 - ring * 0.35) + k * TAU / 6.0
			draw_arc(Vector2.ZERO, radius, start, start + 0.75, 24, Color(DISK_COLORS[(k + ring) % 3], 0.45 - ring * 0.1), 6.0 - ring, true)
	draw_circle(Vector2.ZERO, r, Color("#020106"))
	draw_arc(Vector2.ZERO, r + 3.0, 0.0, TAU, 96, DISK_COLORS[2], 3.0, true)


## A hot core inside a slowly pulsing corona, with flickering flames and looping prominences.
func _draw_star(r: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 1.3)
	for k in range(8, 0, -1):
		_disc(r * (1.0 + k * (0.035 + 0.01 * pulse)), Color(STAR_COLOR, 0.05))
	var rim := TAU * r
	var arc := _view_arc(r + FLAME_LENGTH.y)  # flames are many: draw only those that can show
	for layer in 2:  # tongues of fire along the rim: long faint ones under short bright ones
		var count := int(rim / (FLAME_SPACING - layer * 6.0))
		var half := 0.35 * TAU / count
		var color := Color(FLARE_COLORS[layer], 0.35 + 0.35 * layer)
		for n in range(floori(arc.x / TAU * count), ceili(arc.y / TAU * count) + 1):
			var i := posmod(n, count)
			var at := i * TAU / count + 0.3 * half * sin(_time * 0.7 + i)
			var flicker := 0.5 + 0.5 * sin(_time * (2.0 + i % 5 * 0.6) + i * 1.7 + layer)
			var length := (FLAME_LENGTH.x + (FLAME_LENGTH.y - FLAME_LENGTH.x) * flicker) * (1.0 - 0.5 * layer)
			draw_colored_polygon(PackedVector2Array([Vector2.from_angle(at - half) * (r - 2.0), Vector2.from_angle(at) * (r + length), Vector2.from_angle(at + half) * (r - 2.0)]), color)
	var arches := maxi(STAR_PROMINENCES, int(rim / 1500.0))
	for i in arches:  # slow arches of plasma rising off the surface
		var at := i * TAU / arches + _time * 0.03 * 600.0 / r
		var rise := 0.5 + 0.5 * sin(_time * 0.9 + i * 2.3)
		draw_arc(Vector2.from_angle(at) * r, PROMINENCE_SIZE.x + (PROMINENCE_SIZE.y - PROMINENCE_SIZE.x) * rise, at - PI / 2.0, at + PI / 2.0, 24, Color(FLARE_COLORS[0], 0.5 + 0.4 * rise), 8.0, true)
	_disc(r, STAR_COLOR)
	for k in 5:
		_disc(r * (0.9 - k * 0.17), STAR_COLOR.lerp(STAR_CORE, (k + 1) / 5.0))


## A filled circle smooth at any size: one shared fan mesh, scaled (draw_circle shows facets on a
## star-sized circle, and a big polygon would be triangulated again every frame).
func _disc(radius: float, color: Color) -> void:
	if _unit_disc == null:
		var points := PackedVector2Array([Vector2.ZERO])
		for k in DISC_EDGES + 1:
			points.append(Vector2.from_angle(k * TAU / DISC_EDGES))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		var fan := PackedInt32Array()
		for k in DISC_EDGES:
			fan.append_array([0, k + 1, k + 2])
		arrays[Mesh.ARRAY_INDEX] = fan
		_unit_disc = ArrayMesh.new()
		_unit_disc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	draw_mesh(_unit_disc, null, Transform2D(0.0, Vector2.ONE * radius, 0.0, Vector2.ZERO), color)


## The angles (from, to) of the circle of `radius` around this body that the screen can show;
## the whole circle when the view holds the centre.
func _view_arc(radius: float) -> Vector2:
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var screen := get_viewport_rect()
	var corners := [to_local * screen.position, to_local * Vector2(screen.end.x, screen.position.y), to_local * screen.end, to_local * Vector2(screen.position.x, screen.end.y)]
	if Geometry2D.is_point_in_polygon(Vector2.ZERO, PackedVector2Array(corners)):
		return Vector2(0.0, TAU)
	var first: float = corners[0].angle()
	var low := 0.0
	var high := 0.0
	for corner: Vector2 in corners:
		var turn := wrapf(corner.angle() - first, -PI, PI)
		low = minf(low, turn)
		high = maxf(high, turn)
	return Vector2(first + low, first + high)
