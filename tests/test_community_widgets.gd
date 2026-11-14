extends "res://tests/test_case.gd"
## The difficulty chip and the clear curve.


func test_text_of_picks_rated_then_reviewed_then_voted_with_5_plus_voters_else_empty() -> void:
	var voted := {"value": "expert", "votes": 9}
	check(DifficultyChip.text_of({"rated": "hard", "reviewed_difficulty": "easy", "community_difficulty": voted}) == "Rated Hard", "rated first")
	check(DifficultyChip.text_of({"rated": "normal", "rated_high": "hard"}) == "Rated Normal–Hard", "range with an en dash")
	check(DifficultyChip.text_of({"rated": "normal", "rated_high": "normal"}) == "Rated Normal", "equal ends are one label")
	check(DifficultyChip.text_of({"rated": null, "reviewed_difficulty": "hard", "community_difficulty": voted}) == "Reviewed Hard", "then reviewed")
	check(DifficultyChip.text_of({"reviewed_difficulty": null, "community_difficulty": voted}) == "Voted Expert", "then voted")
	check(DifficultyChip.text_of({"community_difficulty": {"value": null, "votes": 2}}) == "", "no value, no chip")
	check(DifficultyChip.text_of({"rated": "bogus", "reviewed_difficulty": 3, "community_difficulty": "x"}) == "", "malformed is empty")
	check(DifficultyChip.text_of({}) == "", "empty row")
	check(DifficultyChip.of({}) == null, "no chip without a source")


func test_of_builds_a_filled_chip_for_rated_and_an_outlined_one_for_fallbacks() -> void:
	var rated := DifficultyChip.of({"rated": "hard"})
	var reviewed := DifficultyChip.of({"reviewed_difficulty": "hard"})
	check(rated != null and reviewed != null, "chips exist")
	var fill: StyleBoxFlat = rated.get_theme_stylebox("panel")
	var line: StyleBoxFlat = reviewed.get_theme_stylebox("panel")
	check(fill.bg_color.a > 0.9 and line.bg_color.a == 0.0 and line.border_width_left > 0, "filled vs outlined")
	var label: Label = rated.find_children("*", "Label", true, false)[0]
	check(label.text == "Rated Hard" and label.get_theme_font_size("font_size") == 18, "label text and size")
	rated.free()
	reviewed.free()


func test_a_range_is_coloured_by_its_easier_band() -> void:
	var range_chip := DifficultyChip.of({"rated": "normal", "rated_high": "hard"})
	var normal_chip := DifficultyChip.of({"rated": "normal"})
	check(range_chip.get_theme_stylebox("panel").bg_color == normal_chip.get_theme_stylebox("panel").bg_color, "range uses the lower band's colour")
	range_chip.free()
	normal_chip.free()


func test_clear_curve_ignores_malformed_entries() -> void:
	var curve := ClearCurve.new([0.1, "x", null, 2.0, -1.0] + range(40).map(func(_i: int) -> float: return 0.5))
	check(curve.shares.size() == 30, "length capped at 30: %d" % curve.shares.size())
	check(curve.shares[0] == 0.1 and curve.shares[1] == 0.0 and curve.shares[2] == 0.0 and curve.shares[3] == 1.0 and curve.shares[4] == 0.0, "non-numbers are 0, shares clamp to 0..1: %s" % [curve.shares.slice(0, 5)])
	check(curve.custom_minimum_size == Vector2(480, 160), "minimum size")
	curve.free()
	var none := ClearCurve.new(null)
	check(none.shares.is_empty(), "null draws nothing")
	none.free()
