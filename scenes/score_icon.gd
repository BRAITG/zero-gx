class_name ScoreIcon
extends Control
## Small code-drawn icons for the score breakdown, coloured like the things they count.

enum Kind { FUEL, HULL, TIME }

const COLORS := {
	Kind.FUEL: Color("#ffcf4a"),  # the fuel bar
	Kind.HULL: Color("#5be37d"),  # the hull bar
	Kind.TIME: Color("#dfe9ff"),
}
const SIZE := 30.0

var kind := Kind.FUEL


func _init(icon_kind: Kind) -> void:
	kind = icon_kind
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
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
