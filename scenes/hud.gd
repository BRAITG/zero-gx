class_name Hud
extends CanvasLayer
## Fuel and health bars, flight time, Restart/Menu/Tune buttons, and the end-of-level panel.

signal retry_requested
signal menu_requested
signal next_requested

const INTRO_FADE := 0.6  # s
const INTRO_WIDTH := 860.0  # px; the hint wraps inside this
const LOW_FUEL := 0.2  # fraction of a full tank below which the fuel bar blinks
const BLINK_HZ := 2.0
const WARNING := Color("#ff5a4a")

var ship: Ship
var restart_button: Button
var _fuel: ProgressBar
var _health: ProgressBar
var _effect: Label
var _speed: Label
var _countdown: VBoxContainer
var _countdown_number: Label
var _countdown_caption: Label
var _countdown_second := -1
var _result: PanelContainer
var _result_label: Label
var _detail: Label
var _score: VBoxContainer
var _total: Label
var _best: Label
var _parts := {}  # ScoreIcon.Kind -> value Label
var _next: Button
var _time: Label
var _intro: PanelContainer
var _intro_title: Label
var _intro_hint: Label
var _intro_fading := false


## The empty-tank countdown: a big number that pulses and ticks on each new second.
func _show_countdown(left: float) -> void:
	var shown := left >= 0.0 and ship.health > 0.0 and not _result.visible
	_countdown.visible = shown
	if not shown:
		_countdown_second = -1
		return
	var second := ceili(left)
	_countdown_caption.text = "OUT OF FUEL · BOOST" if ship.boosting else "OUT OF FUEL"
	if second == _countdown_second:
		return
	_countdown_second = second
	_countdown_number.text = str(second)
	_countdown.reset_size()
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	_countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown.pivot_offset = _countdown.size / 2.0
	_countdown.scale = Vector2.ONE * 1.35
	create_tween().tween_property(_countdown, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("tick")


func _ready() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 16)
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	_fuel = _bar(top, "Fuel", Color("#ffcf4a"), Ship.MAX_FUEL)
	_health = _bar(top, "Hull", Color("#5be37d"), Ship.MAX_HEALTH)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	restart_button = _button(top, "Restart", retry_requested.emit)
	_button(top, "Menu", menu_requested.emit)
	_button(top, "Tune", func(): TuningPanel.open(self))
	_effect = Label.new()
	_effect.position = Vector2(16, 64)
	_effect.add_theme_font_size_override("font_size", 24)
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effect)
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", 28)
	_speed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_speed)
	_speed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_speed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_countdown = VBoxContainer.new()
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.add_theme_constant_override("separation", -6)
	_countdown.hide()
	add_child(_countdown)
	_countdown_number = Label.new()
	_countdown_number.add_theme_font_override("font", Style.display_font)
	_countdown_number.add_theme_font_size_override("font_size", 72)
	_countdown_number.add_theme_color_override("font_color", WARNING)
	_countdown_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_child(_countdown_number)
	_countdown_caption = Label.new()
	_countdown_caption.add_theme_font_override("font", Style.display_font)
	_countdown_caption.add_theme_font_size_override("font_size", 20)
	_countdown_caption.add_theme_color_override("font_color", WARNING)
	_countdown_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_child(_countdown_caption)
	_intro = PanelContainer.new()
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the first touch must reach the ship
	_intro.hide()
	var card := VBoxContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.add_child(card)
	_intro_title = Label.new()
	_intro_title.add_theme_font_override("font", Style.display_font)
	_intro_title.add_theme_font_size_override("font_size", 34)
	_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_intro_title)
	_intro_hint = Label.new()
	_intro_hint.add_theme_font_size_override("font_size", 26)
	_intro_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_hint.custom_minimum_size.x = INTRO_WIDTH
	card.add_child(_intro_hint)
	add_child(_intro)

	_result = PanelContainer.new()
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.hide()
	add_child(_result)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_result.add_child(column)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_override("font", Style.display_font)
	_result_label.add_theme_font_size_override("font_size", 36)
	column.add_child(_result_label)
	_score = VBoxContainer.new()
	_score.add_theme_constant_override("separation", 6)
	column.add_child(_score)
	_total = Label.new()
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.add_theme_font_override("font", Style.display_font)
	_total.add_theme_font_size_override("font_size", 52)
	_score.add_child(_total)
	_best = Label.new()
	_best.text = "New best!"
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best.add_theme_color_override("font_color", Style.ACCENT)
	_score.add_child(_best)
	var parts := GridContainer.new()  # two rows of icon + value, well apart
	parts.columns = 2
	parts.add_theme_constant_override("h_separation", 48)
	parts.add_theme_constant_override("v_separation", 10)
	parts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_score.add_child(parts)
	for kind in [ScoreIcon.Kind.FINISH, ScoreIcon.Kind.FUEL, ScoreIcon.Kind.HULL, ScoreIcon.Kind.TIME]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.add_child(ScoreIcon.new(kind))
		var value := Label.new()
		value.custom_minimum_size.x = 80
		cell.add_child(value)
		_parts[kind] = value
		parts.add_child(cell)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 24)
	column.add_child(_detail)
	_next = _button(column, "Next", next_requested.emit)
	_button(column, "Retry", retry_requested.emit)
	_button(column, "Menu", menu_requested.emit)
	_time = Label.new()
	_time.add_theme_font_size_override("font_size", 28)
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time)
	_time.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_time.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_time.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _process(_delta: float) -> void:
	if ship:
		_fuel.value = ship.fuel
		var low := ship.fuel < LOW_FUEL * Ship.MAX_FUEL
		var lit := fmod(Time.get_ticks_msec() * 0.001 * BLINK_HZ, 1.0) < 0.5
		_fuel.modulate.a = 0.25 if low and not lit else 1.0
		_health.value = ship.health
		_effect.text = ship.effect_text()
		_speed.visible = Tuning.show_overlays
		_speed.text = "%d px/s" % roundi(ship.linear_velocity.length())  # world frame: relative to the background
		var left := ship.empty_seconds_left()
		_show_countdown(left)
		_time.text = "%.1f s" % ship.flight_time
		if _intro.visible and ship.flight_time > 0.0 and not _intro_fading:
			_intro_fading = true
			var fade := create_tween()
			fade.tween_property(_intro, "modulate:a", 0.0, INTRO_FADE)
			fade.tween_callback(_intro.hide)


func show_intro(title: String, hint: String) -> void:
	_intro_title.text = title
	_intro_hint.text = hint
	_intro_hint.visible = hint != ""
	_intro.show()
	_intro.reset_size()
	_intro.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 110)
	_intro.grow_horizontal = Control.GROW_DIRECTION_BOTH


## The intro card's text while it is shown, for tests.
func intro_text() -> String:
	return "%s\n%s" % [_intro_title.text, _intro_hint.text] if _intro.visible else ""


## `result` keys: won → points, fuel_points, hull_points, time_points, new_best, has_next;
## lost → cause.
func show_result(won: bool, result: Dictionary) -> void:
	_intro.hide()
	_result_label.text = "Course clear" if won else "Lost"
	_score.visible = won
	_detail.visible = not won
	if won:
		_total.text = str(result.points)
		_best.visible = result.new_best
		_parts[ScoreIcon.Kind.FINISH].text = str(Progress.BASE_POINTS)
		_parts[ScoreIcon.Kind.FUEL].text = "+%d" % result.fuel_points
		_parts[ScoreIcon.Kind.HULL].text = "+%d" % result.hull_points
		_parts[ScoreIcon.Kind.TIME].text = "−%d" % result.time_points
	else:
		_detail.text = result.cause
	_next.visible = won and result.has_next
	_result.reset_size()
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.show()


## Everything the end panel shows, for tests.
func result_text() -> String:
	var lines := [_result_label.text]
	if _score.visible:
		lines.append(_total.text)
		if _best.visible:
			lines.append(_best.text)
		for kind in _parts:
			lines.append(_parts[kind].text)
	else:
		lines.append(_detail.text)
	return "\n".join(lines)


func _bar(parent: Control, title: String, color: Color, maximum: float) -> ProgressBar:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = maximum
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 24)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button
