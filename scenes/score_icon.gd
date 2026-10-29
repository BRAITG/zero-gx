class_name ScoreIcon
extends Control
## Small code-drawn icons for the score breakdown, coloured like the things they count.

enum Kind { FUEL, HULL, TIME, MEDAL }

const COLORS := {
	Kind.FUEL: Color("#ffcf4a"),  # the fuel bar
	Kind.HULL: Color("#5be37d"),  # the hull bar
	Kind.TIME: Color("#dfe9ff"),
}
const MEDAL_COLORS := {
	Progress.Medal.BRONZE: Color("#c8803c"),
	Progress.Medal.SILVER: Color("#c9d2e3"),
	Progress.Medal.GOLD: Color("#ffcf4a"),
}
const SIZE := 30.0
## The medal's left half in fractions of SIZE: a hull plate with the ship's left half (nose, wing tip,
## rear notch) cut out of its axis. The medal is this and its mirror image, because a polygon with a
## hole cannot be drawn and a notch painted in the background colour would not suit every panel.
const MEDAL_LEFT := [Vector2(0.5, 0.06), Vector2(0.14, 0.24), Vector2(0.22, 0.66), Vector2(0.5, 0.94), Vector2(0.5, 0.54), Vector2(0.36, 0.62), Vector2(0.5, 0.30)]

var kind := Kind.FUEL
## Which medal a Kind.MEDAL icon draws; NONE draws nothing.
var tier := Progress.Medal.NONE:
	set(value):
		tier = value
		queue_redraw()
## A medal slot not yet earned: the tier's shape as a faint outline.
var empty := false:
	set(value):
		empty = value
		queue_redraw()


func _init(icon_kind: Kind, medal_tier := Progress.Medal.NONE) -> void:
	kind = icon_kind
	tier = medal_tier
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if kind == Kind.MEDAL:
		_draw_medal()
		return
	var c := Vector2(SIZE, SIZE) / 2.0
	var r := SIZE * 0.42
	var color: Color = COLORS[kind]
	match kind:
		Kind.FUEL:  # a drop
			draw_circle(c + Vector2(0, r * 0.3), r * 0.62, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.58, r * 0.12), c + Vector2(-r * 0.58, r * 0.12)]), color)
		Kind.HULL:  # a shield
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.75), c + Vector2(r * 0.8, -r * 0.75), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)]), color)
		Kind.TIME:  # a clock
			draw_arc(c, r, 0.0, TAU, 32, color, 2.5, true)
			draw_line(c, c + Vector2(0, -r * 0.65), color, 2.5, true)
			draw_line(c, c + Vector2(r * 0.5, 0), color, 2.5, true)


## Both halves of the medal in the tier's colour, or as a faint outline when `empty`; nothing for NONE.
func _draw_medal() -> void:
	if not MEDAL_COLORS.has(tier):
		return
	var color: Color = MEDAL_COLORS[tier]
	for mirrored in [false, true]:
		var half := PackedVector2Array()
		for point: Vector2 in MEDAL_LEFT:
			half.append(Vector2(1.0 - point.x if mirrored else point.x, point.y) * SIZE)
		if empty:
			half.append(half[0])
			draw_polyline(half, Color(color, 0.35), 1.5, true)
		else:
			draw_colored_polygon(half, color)
