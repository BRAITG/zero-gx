class_name Thumbnail
extends Control
## A composed 16:9 picture of what a stage is about, drawn in code: one scene per official level and
## training stage, in the game's own ship, wall, pickup and gravity-body shapes. Not a map of the stage.
## Compositions are authored on a 320x180 canvas and scaled to the control's size; they must read at
## phone size (about 130x73 px), so objects are large and each picture has one idea.

const CANVAS := Vector2(320, 180)
const BACKGROUND := [Color("#0b152a"), Color("#030610")]
const GOAL_GREEN := Color(0.4, 1.0, 0.6)
const PLANET := GravityBody.PLANET_COLORS[1]
const ROCK := Color("#6f675f")
const ROCK_RIM := Color("#b3a89a")
const FUEL := ScoreIcon.COLORS[ScoreIcon.Kind.FUEL]

var stage_id: String


func _init(id: String) -> void:
	stage_id = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / CANVAS)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(CANVAS.x, 0), CANVAS, Vector2(0, CANVAS.y)]), PackedColorArray([BACKGROUND[0], BACKGROUND[0].lerp(BACKGROUND[1], 0.5), BACKGROUND[1], BACKGROUND[0].lerp(BACKGROUND[1], 0.5)]))
	for i in 75:
		draw_circle(Vector2((i * 73 + 17) % 320, (i * 47 + 11) % 180), 0.9 if i % 9 == 0 else 0.45, Color(0.75, 0.82, 1.0, 0.12 + (i % 5) * 0.08))
	match stage_id:
		"level_01":  # Launch: a firing ship, open space, the goal ahead.
			_ship(Vector2(112, 111), -0.24, 2.25, true)
			_goal(Vector2(253, 77), 36)
		"level_02":  # Drift: engine off, a long straight wake, nothing to push against.
			_wake([Vector2(-10, 118), Vector2(150, 96)])
			_ship(Vector2(150, 96), -0.14, 2.25, false)
		"level_03":  # Brake: still moving right (the arrow), turned around and firing, an orange wall ahead.
			_wake([Vector2(-10, 90), Vector2(130, 90)])
			_ship(Vector2(130, 90), PI, 2.25, true, 0.0, 0.7)
			_arrow(Vector2(135, 114), Vector2(222, 114))
			_wall([Vector2(272, 20), Vector2(272, 160)], Barrier.Kind.ORANGE)
		"level_04":  # Pull: a course that sags toward a planet below, and clears it.
			_field(Vector2(150, 215), 100, 20, 2)
			_planet(Vector2(150, 215), 80)
			_wake([Vector2(-10, 40), Vector2(80, 52), Vector2(150, 70), Vector2(230, 56)])
			_ship(Vector2(230, 56), -0.2, 2.1, false)
		"level_05":  # Swing: a planet half out of frame, the wake wrapping it, the ship leaving on the tangent.
			_planet(Vector2(204, 114), 98)
			var arc := PackedVector2Array()
			for k in 25:
				arc.append(Vector2(204, 114) + Vector2.from_angle(lerpf(PI / 2.0, PI * 200.0 / 180.0, k / 24.0)) * 135.0)
			_wake(arc, false)
			_ship(Vector2(77, 68), -1.22, 2.1, false)
		"level_06":  # Edge: red walls narrowing to a gap, the ship coasting slowly through.
			_wall([Vector2(-10, 10), Vector2(150, 62), Vector2(330, 52)], Barrier.Kind.RED)
			_wall([Vector2(-10, 180), Vector2(150, 128), Vector2(330, 138)], Barrier.Kind.RED)
			_wake([Vector2(-10, 95), Vector2(150, 95)])
			_ship(Vector2(150, 95), 0.0, 2.0, false)
		"level_07":  # Power: a green pickup ahead, a violet one off to the side.
			_ship(Vector2(90, 100), -0.3, 2.1, true)
			_pickup(Vector2(240, 62), Pickup.Kind.THRUST_UP, 1.6)
			_pickup(Vector2(270, 150), Pickup.Kind.THRUST_DOWN, 1.0)
		"level_08":  # Rocks: two asteroids, one gap, the ship coasting straight through it.
			_asteroid(Vector2(205, 22), 2.1, 1)
			_asteroid(Vector2(245, 168), 2.1, 2)
			_wake([Vector2(-10, 98), Vector2(130, 96)])
			_ship(Vector2(130, 96), 0.0, 2.0, false)
		"level_09":  # Abyss: a black hole filling the frame, the ship firing away from its rim.
			_black_hole(Vector2(225, 105), 62)
			_ship(Vector2(78, 62), -2.4, 2.1, true)
		"level_10":  # Sun: a star half out of frame, the ship's course bent toward it, glowing with its heat.
			_star(Vector2(300, 90), 110)
			_wake([Vector2(-10, 172), Vector2(60, 160), Vector2(110, 90)])
			_ship(Vector2(110, 90), -PI / 2.0, 2.1, false, 0.4)
		"level_11":  # Corona: a red wall above, a star's flames below, the ship in the dark gap between.
			_wall([Vector2(-10, 20), Vector2(330, 20)], Barrier.Kind.RED)
			_star(Vector2(160, 325), 190)
			_ship(Vector2(150, 54), 0.0, 1.8, true, 0.3)
		"level_12":  # Burn: the ship at full burn, barely steering, a boost pickup in its way.
			_ship(Vector2(100, 90), 0.0, 2.25, true, 0.0, 2.2)
			_pickup(Vector2(262, 90), Pickup.Kind.BOOST, 1.5)
		"tutorial_1":  # Coast: the ship and its velocity arrow, nothing else.
			_ship(Vector2(130, 95), -0.2, 2.25, false)
			_arrow(Vector2(130, 95), Vector2(250, 70))
		"tutorial_2":  # Walls: a blue wall and a wake bouncing off it.
			_wall([Vector2(250, -10), Vector2(250, 190)], Barrier.Kind.BLUE)
			_wake([Vector2(-10, 40), Vector2(246, 100), Vector2(150, 130)], false)
			_ship(Vector2(150, 130), PI - 0.3, 2.0, false)
		"tutorial_3":  # Fuel: engine off, coasting, the fuel gauge nearly empty.
			_wake([Vector2(-10, 118), Vector2(110, 100)])
			_ship(Vector2(110, 100), -0.15, 2.25, false)
			_drop(Vector2(196, 48), 13)
			draw_rect(Rect2(216, 38, 90, 20), Color(FUEL, 0.25))
			draw_rect(Rect2(216, 38, 16, 20), FUEL)
			draw_rect(Rect2(216, 38, 90, 20), FUEL, false, 2.0)
		"tutorial_4":  # Danger walls: orange and red walls either side of the ship.
			_wall([Vector2(-10, 30), Vector2(330, 30)], Barrier.Kind.ORANGE)
			_wall([Vector2(-10, 150), Vector2(330, 150)], Barrier.Kind.RED)
			_ship(Vector2(150, 90), 0.0, 2.0, true)
		"tutorial_5":  # Gravity: the course already bending toward a planet, the arrow still clearing it.
			_field(Vector2(240, 135), 58, 20, 3)
			_planet(Vector2(240, 135), 44)
			_wake([Vector2(-10, 50), Vector2(50, 54), Vector2(100, 62)])
			_ship(Vector2(100, 62), 0.09, 2.0, false)
			_arrow(Vector2(100, 62), Vector2(185, 70))
		"tutorial_6":  # Black holes: a hole with a wide field, the ship keeping clear.
			_field(Vector2(235, 95), 66, 18, 4)
			_black_hole(Vector2(235, 95), 40)
			_ship(Vector2(80, 60), -0.6, 2.0, false)
		"tutorial_7":  # Stars: a star's edge and the ship's heat glow.
			_star(Vector2(320, 180), 130)
			_ship(Vector2(110, 70), -0.4, 2.1, false, 0.4)
		_:
			push_error("No thumbnail composed for stage %s" % stage_id)


## The hull in Ship's proportions (nose 14, half-width 8) times `scale`; `heat` reddens it as near a star, `flame` scales the exhaust.
func _ship(at: Vector2, angle: float, scale: float, firing: bool, heat := 0.0, flame := 1.0) -> void:
	_local(at, angle, scale)
	var nose := Vector2(14, 0)
	var hull := PackedVector2Array([nose, Vector2(-10, 8), Vector2(-5, 0), Vector2(-10, -8), nose])
	if firing:
		var reach := 22.0 * flame
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 4.5), Vector2(-reach, 0), Vector2(-6, -4.5)]), Ship.FLAME)
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 2.2), Vector2(-reach * 0.7, 0), Vector2(-6, -2.2)]), Ship.FLAME_CORE)
	if heat > 0.0:
		for k in 4:  # a soft halo: the in-game glow has bloom, a flat disc here hides the hull
			draw_circle(Vector2.ZERO, (14 + 8 * heat) * (1.0 - k * 0.2), Color(Ship.HEAT_RED, 0.12 * heat))
	draw_colored_polygon(hull.slice(0, 4), Ship.HULL.lerp(Ship.HEAT_RED, heat))
	draw_polyline(hull, Ship.HULL_EDGE.lerp(Ship.HEAT_RED, heat), 1.0, true)
	draw_circle(Vector2(3.5, 0), 1.8, Style.ACCENT)
	_local(Vector2.ZERO)


## The game's goal ring (goal.gd) at a frozen moment.
func _goal(at: Vector2, r: float) -> void:
	for f in [0.25, 0.58, 0.91]:
		draw_arc(at, r * f, 0.0, TAU, 48, Color(GOAL_GREEN, 0.6 * (1.0 - f)), 2.2, true)
	draw_arc(at, r, 0.0, TAU, 64, Color(GOAL_GREEN, 0.9), 3.0, true)
	for k in 4:
		draw_circle(at, r * (0.32 - k * 0.07), Color(GOAL_GREEN, 0.18 + k * 0.12))


func _planet(at: Vector2, r: float) -> void:
	draw_circle(at, r, PLANET.darkened(0.45))
	for k in 7:
		var f := k / 7.0
		draw_circle(at + Vector2(-0.28, -0.28) * r * f, r * (1.0 - f * 0.72), PLANET.lerp(PLANET.lightened(0.45), f))
	draw_arc(at, r + 2.0, 0.0, TAU, 96, Color(PLANET.lightened(0.5), 0.55), 2.5, true)


func _black_hole(at: Vector2, r: float) -> void:
	for ring in 2:
		for k in 5:
			var start := k * TAU / 5.0 + ring * 0.6
			draw_arc(at, r * 1.3 + ring * r * 0.2, start, start + 0.9, 24, Color(GravityBody.DISK_COLORS[ring], 0.8 - ring * 0.25), 4.0 - ring, true)
	draw_circle(at, r, Color("#020106"))
	draw_arc(at, r + 1.5, 0.0, TAU, 96, GravityBody.DISK_COLORS[2], 2.0, true)


func _star(at: Vector2, r: float) -> void:
	for k in range(6, 0, -1):
		draw_circle(at, r * (1.0 + k * 0.05), Color(GravityBody.STAR_COLOR, 0.06))
	var count := int(TAU * r / 24.0)
	for i in count:
		var a := i * TAU / count
		var half := 0.35 * TAU / count
		var length := r * (0.08 + 0.1 * (i % 3))
		draw_colored_polygon(PackedVector2Array([at + Vector2.from_angle(a - half) * (r - 1), at + Vector2.from_angle(a) * (r + length), at + Vector2.from_angle(a + half) * (r - 1)]), Color(GravityBody.FLARE_COLORS[i % 2], 0.6))
	draw_circle(at, r, GravityBody.STAR_COLOR)
	for k in 5:
		draw_circle(at, r * (0.9 - k * 0.17), GravityBody.STAR_COLOR.lerp(GravityBody.STAR_CORE, (k + 1) / 5.0))


func _wall(points: Array, kind: Barrier.Kind) -> void:
	var color: Color = Barrier.COLORS[kind]
	var line := PackedVector2Array(points)
	draw_polyline(line, Color(color, 0.25), 10.0, true)
	draw_polyline(line, color, 2.5, true)


func _pickup(at: Vector2, kind: Pickup.Kind, scale: float) -> void:
	_local(at, 0.0, scale)
	var color: Color = Pickup.COLORS[kind]
	draw_circle(Vector2.ZERO, Pickup.RADIUS, Color(color, 0.2))
	draw_arc(Vector2.ZERO, Pickup.RADIUS, 0.0, TAU, 48, color, 3.0, true)
	match kind:
		Pickup.Kind.THRUST_UP, Pickup.Kind.THRUST_DOWN:
			var flip := 1.0 if kind == Pickup.Kind.THRUST_UP else -1.0
			for offset: float in [-5.0, 5.0]:
				var y := offset * flip
				draw_polyline(PackedVector2Array([Vector2(-10, y + 5 * flip), Vector2(0, y - 5 * flip), Vector2(10, y + 5 * flip)]), color, 3.0, true)
		Pickup.Kind.BOOST:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -15), Vector2(8, 3), Vector2(0, 13), Vector2(-8, 3)]), color)
	_local(Vector2.ZERO)


func _asteroid(at: Vector2, scale: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var outline := PackedVector2Array()
	for i in 8:
		outline.append(at + Vector2.RIGHT.rotated(TAU * i / 8.0) * Asteroid.RADIUS * scale * rng.randf_range(0.8, 1.2))
	draw_colored_polygon(outline, ROCK)
	for i in 2:
		draw_circle(at + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * Asteroid.RADIUS * scale, rng.randf_range(0.15, 0.28) * Asteroid.RADIUS * scale, ROCK.darkened(0.25))
	outline.append(outline[0])
	draw_polyline(outline, ROCK_RIM, 2.0, true)


## The faint discs that show a gravity body's reach.
func _field(at: Vector2, r: float, step: float, rings: int) -> void:
	for i in rings:
		draw_arc(at, r + i * step, 0.0, TAU, 96, Color(GravityBody.RIPPLE_TINT, 0.22), 1.5, true)


## The ship's exhaust trail through `points`, fading in from the tail to the ship as the game's does;
## `smooth` rounds the corners (a bounce keeps them sharp).
func _wake(points: Array, smooth := true) -> void:
	var line := PackedVector2Array(points)
	if smooth and points.size() > 2:
		var curve := Curve2D.new()
		for p: Vector2 in points:
			curve.add_point(p)
		for i in range(1, points.size() - 1):
			var dir: Vector2 = (points[i + 1] - points[i - 1]).normalized() * 25.0
			curve.set_point_in(i, -dir)
			curve.set_point_out(i, dir)
		line = curve.tessellate()
	var colors := PackedColorArray()
	for i in line.size():
		colors.append(Color(Ship.HULL_EDGE, 0.85 * i / (line.size() - 1)))
	draw_polyline_colors(line, colors, 5.0, true)


## The ship's velocity arrow (white, as in the tutorials).
func _arrow(from: Vector2, to: Vector2) -> void:
	var arrow := Color(1, 1, 1, 0.6)
	draw_line(from, to, arrow, 3.0, true)
	var back := (from - to).normalized() * 16.0
	draw_colored_polygon(PackedVector2Array([to, to + back.rotated(0.45), to + back.rotated(-0.45)]), arrow)


## A fuel drop (ScoreIcon's shape).
func _drop(at: Vector2, r: float) -> void:
	draw_circle(at + Vector2(0, r * 0.3), r * 0.62, FUEL)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.58, r * 0.12), at + Vector2(-r * 0.58, r * 0.12)]), FUEL)


## Draws what follows at `at`, turned by `angle` and scaled; `_local(Vector2.ZERO)` returns to the canvas.
func _local(at: Vector2, angle := 0.0, scale := 1.0) -> void:
	draw_set_transform_matrix(Transform2D(0.0, size / CANVAS, 0.0, Vector2.ZERO) * Transform2D(angle, Vector2.ONE * scale, 0.0, at))
