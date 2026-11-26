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
	var pad_l := 56.0
	var pad_r := 12.0
	var pad_t := 14.0
	var pad_b := 26.0
	var w := maxf(1.0, size.x - pad_l - pad_r)
	var h := maxf(1.0, size.y - pad_t - pad_b)
	var font := get_theme_default_font()
	var fsize := 15
	draw_line(Vector2(pad_l, pad_t), Vector2(pad_l + w, pad_t), Color(Style.BORDER, 0.35), 1.0)
	draw_dashed_line(Vector2(pad_l, pad_t + h * 0.5), Vector2(pad_l + w, pad_t + h * 0.5), Color(Style.INK_DIM, 0.65), 1.0, 6.0)
	draw_line(Vector2(pad_l, pad_t + h), Vector2(pad_l + w, pad_t + h), Color(Style.BORDER, 0.55), 1.0)
	if font:
		draw_string(font, Vector2(0, pad_t + 5), "100%", HORIZONTAL_ALIGNMENT_RIGHT, pad_l - 8, fsize, Style.INK_DIM)
		draw_string(font, Vector2(0, pad_t + h * 0.5 + 5), "50%", HORIZONTAL_ALIGNMENT_RIGHT, pad_l - 8, fsize, Style.INK_DIM)
		draw_string(font, Vector2(0, pad_t + h + 5), "0%", HORIZONTAL_ALIGNMENT_RIGHT, pad_l - 8, fsize, Style.INK_DIM)
		var base_y := size.y - 5.0
		draw_string(font, Vector2(pad_l, base_y), "1 try", HORIZONTAL_ALIGNMENT_LEFT, 60, fsize, Style.INK_DIM)
		draw_string(font, Vector2(pad_l + w * (9.0 / (MAX_TRIES - 1)) - 14, base_y), "10", HORIZONTAL_ALIGNMENT_CENTER, 28, fsize, Style.INK_DIM)
		draw_string(font, Vector2(pad_l + w * (19.0 / (MAX_TRIES - 1)) - 14, base_y), "20", HORIZONTAL_ALIGNMENT_CENTER, 28, fsize, Style.INK_DIM)
		draw_string(font, Vector2(pad_l + w - 64, base_y), "%d tries" % MAX_TRIES, HORIZONTAL_ALIGNMENT_RIGHT, 64, fsize, Style.INK_DIM)
	var points := PackedVector2Array()
	for i in shares.size():
		points.append(Vector2(pad_l + w * i / (MAX_TRIES - 1), pad_t + h * (1.0 - shares[i])))
	var fill_top := Color(Style.ACCENT, 0.24)
	var fill_bot := Color(Style.ACCENT, 0.0)
	var bottom_y := pad_t + h
	for i in range(points.size() - 1):
		var s0 := shares[i]
		var s1 := shares[i + 1]
		if s0 <= 0.0 and s1 <= 0.0:
			continue
		var a := points[i]
		var b := points[i + 1]
		if s0 <= 0.0:
			draw_polygon(PackedVector2Array([a, b, Vector2(b.x, bottom_y)]), PackedColorArray([fill_bot, fill_top, fill_bot]))
		elif s1 <= 0.0:
			draw_polygon(PackedVector2Array([a, b, Vector2(a.x, bottom_y)]), PackedColorArray([fill_top, fill_bot, fill_bot]))
		else:
			draw_polygon(PackedVector2Array([a, b, Vector2(b.x, bottom_y), Vector2(a.x, bottom_y)]), PackedColorArray([fill_top, fill_top, fill_bot, fill_bot]))
	draw_polyline(points, Style.ACCENT, 3.0, true)
