class_name DifficultyChip
extends PanelContainer
## The one difficulty label of a community level row, with its source in the text: "Rated Normal–Hard" (filled), "Reviewed Hard" or "Voted Hard" (outlined). Colour is never the only signal.

const LABELS := ["easy", "normal", "hard", "expert"]
const ORANGE := Color("#ff9a3a")
const COLORS := {"easy": Hud.GOAL_GREEN, "normal": Style.ACCENT, "hard": ORANGE, "expert": Hud.WARNING}
const FONT_SIZE := 18


## "Rated Hard", "Rated Normal–Hard", "Reviewed Hard", "Voted Hard" or "" when the row has no source.
static func text_of(row: Dictionary) -> String:
	var rated: Variant = row.get("rated")
	if rated in LABELS:
		var high: Variant = row.get("rated_high")
		return "Rated %s%s" % [rated.capitalize(), "–" + high.capitalize() if high in LABELS and high != rated else ""]
	var reviewed: Variant = row.get("reviewed_difficulty")
	if reviewed in LABELS:
		return "Reviewed " + reviewed.capitalize()
	var voted: Variant = row.get("community_difficulty")
	var value: Variant = voted.get("value") if voted is Dictionary else null
	return "Voted " + value.capitalize() if value in LABELS else ""


## The chip of a `list` row, null when it has no difficulty source. A range takes the colour of its easier end.
static func of(row: Dictionary) -> DifficultyChip:
	var text := text_of(row)
	if text == "":
		return null
	var chip := DifficultyChip.new()
	var color: Color = COLORS[text.get_slice(" ", 1).get_slice("–", 0).to_lower()]
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(6)
	box.set_content_margin_all(6)
	var filled := text.begins_with("Rated")
	box.bg_color = color if filled else Color(0, 0, 0, 0)
	box.set_border_width_all(0 if filled else 2)
	box.border_color = color
	chip.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color("#06101f") if filled else color)
	chip.add_child(label)
	return chip
