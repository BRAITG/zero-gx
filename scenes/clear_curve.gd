class_name ClearCurve
extends Control
## The share of starters who cleared on or before attempt t, for t = 1..30, with a dashed line at 50%.

const MAX_TRIES := 30

## Shares in 0..1, at most `MAX_TRIES`; anything that is not a number counts as 0.
var shares: Array[float] = []


func _init(curve: Variant = null) -> void:
	custom_minimum_size = Vector2(480, 160)
	if curve is Array:
		for value: Variant in curve.slice(0, MAX_TRIES):
			shares.append(clampf(value, 0.0, 1.0) if value is int or value is float else 0.0)


func _draw() -> void:
	if shares.size() < 2:  # one point draws no line
		return
	draw_dashed_line(Vector2(0, size.y / 2), Vector2(size.x, size.y / 2), Style.INK_DIM, 1.0, 6.0)
	var points := PackedVector2Array()
	for i in shares.size():
		points.append(Vector2(size.x * i / (MAX_TRIES - 1), size.y * (1.0 - shares[i])))
	draw_polyline(points, Style.ACCENT, 3.0, true)
