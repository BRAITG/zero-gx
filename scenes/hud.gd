class_name Hud
extends CanvasLayer
## Fuel and health bars, flight time, Pause, and the end-of-level panel.

signal retry_requested
signal menu_requested
signal next_requested
signal replay_requested
signal rate_requested
signal board_requested

const INTRO_FADE := 0.6  # s
const INTRO_WIDTH := 860.0  # px; the hint wraps inside this
const LOW_FUEL := 0.2  # fraction of a full tank below which the fuel bar blinks
const BLINK_HZ := 2.0
const WARNING := Color("#ff5a4a")
const METRES_PER_PX := 0.1
const ARROW_MARGIN := 48.0  # px from the screen edge
const GOAL_GREEN := Color(0.4, 1.0, 0.6)
const RESULT_FOCUS_DELAY := 0.4  # s: a fire tap just after the finish must not press Next or Retry
const COUNT_SECONDS := 1.2  # s: the total counts up and the medal slots fill on the way


## The pause card. It runs while the tree is paused, so it, not ShipInput, sees `pause` to resume.
class PauseCard extends PanelContainer:
	signal resume_requested

	func _unhandled_input(event: InputEvent) -> void:
		if visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
			get_viewport().set_input_as_handled()
			resume_requested.emit()


## The label of the buttons that leave the level ("Edit" on a test flight).
var menu_text := "Menu"
## The label of the button that goes on after a win ("End training" after the last training stage).
var next_text := "Next"
var ship: Ship
var goal: Node2D
var pause_button: Button
## Whether the end panel offers a Replay (the level recorded a demo).
var can_replay := false
var _fuel: ProgressBar
var _health: ProgressBar
var _effect: Label
var _speed: Label
var _countdown: VBoxContainer
var _countdown_number: Label
var _countdown_caption: Label
var _countdown_second := -1
var _result: PanelContainer
var _result_frame: Control
var _pause: PauseCard
var _resume: Button
var _prior_focus: Control  # what had focus before the pause card opened
var _result_label: Label
var _result_name: Label
var _detail: Label
var _score: VBoxContainer
var _total: Label
var _best: Label
var _best_pill: PanelContainer
var _medal: HBoxContainer  # three medal slots, filled as the total counts up; only on a stage with a par
var _slots := {}  # Progress.Medal -> ScoreIcon
var _par_box: VBoxContainer
var _par_bar: ParBar
var _par_next: Label
var _count: Tween
var _parts := {}  # ScoreIcon.Kind -> value Label
var _next: Button
var _retry: Button
var _replay: Button
var _rate: Button
var _board: Button
var _standing: Label
var _board_preview: VBoxContainer
var _board_scroll: ScrollContainer
var _time: Label
var _arrow: Control
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
	_fuel = _bar(top, ScoreIcon.Kind.FUEL, maxf(Ship.MAX_FUEL, ship.fuel), ship.fuel_unlimited)
	_health = _bar(top, ScoreIcon.Kind.HULL, ship.hull, ship.hull_unlimited)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	pause_button = _button(top, "Pause", toggle_pause, false)
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

	_result_frame = Style.menu_frame(self)
	_result = PanelContainer.new()
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.hide()
	_result_frame.add_child(_result)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_result.add_child(column)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_override("font", Style.display_font)
	_result_label.add_theme_font_size_override("font_size", 36)
	_result_name = Label.new()  # which stage this was
	_result_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_name.add_theme_font_size_override("font_size", 22)
	_result_name.add_theme_color_override("font_color", Style.INK_DIM)
	column.add_child(_result_name)
	column.add_child(_result_label)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)
	_score = VBoxContainer.new()
	_score.add_theme_constant_override("separation", 10)
	_score.alignment = BoxContainer.ALIGNMENT_CENTER
	_score.custom_minimum_size.x = 340
	body.add_child(_score)
	var score_head := HBoxContainer.new()
	score_head.alignment = BoxContainer.ALIGNMENT_CENTER
	score_head.add_theme_constant_override("separation", 12)
	_score.add_child(score_head)
	_total = Label.new()
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total.add_theme_font_override("font", Style.display_font)
	_total.add_theme_font_size_override("font_size", 52)
	score_head.add_child(_total)
	_best_pill = Style.pill("New best!", Style.ACCENT, false, 16)
	_best = _best_pill.get_child(0) as Label
	score_head.add_child(_best_pill)
	_medal = HBoxContainer.new()
	_medal.alignment = BoxContainer.ALIGNMENT_CENTER
	_medal.add_theme_constant_override("separation", 18)
	_score.add_child(_medal)
	for tier in [Progress.Medal.BRONZE, Progress.Medal.SILVER, Progress.Medal.GOLD]:
		_slots[tier] = ScoreIcon.new(ScoreIcon.Kind.MEDAL, tier, 46.0)
		_medal.add_child(_slots[tier])
	_par_box = VBoxContainer.new()
	_par_box.add_theme_constant_override("separation", 4)
	_score.add_child(_par_box)
	_par_bar = ParBar.new()
	_par_box.add_child(_par_bar)
	_par_next = Label.new()
	_par_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_par_next.add_theme_font_size_override("font_size", 17)
	_par_next.add_theme_color_override("font_color", Style.INK_DIM)
	_par_box.add_child(_par_next)
	var breakdown := PanelContainer.new()
	var bd_box := Style._box(Style.PANEL_INSET, Style.BORDER_SOFT, 10, 10)
	bd_box.set_border_width_all(1)
	breakdown.add_theme_stylebox_override("panel", bd_box)
	_score.add_child(breakdown)
	var parts := GridContainer.new()  # three lines of icon + label + value
	parts.columns = 1
	parts.add_theme_constant_override("v_separation", 8)
	parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breakdown.add_child(parts)
	var part_names := {ScoreIcon.Kind.FUEL: "Fuel", ScoreIcon.Kind.HULL: "Hull", ScoreIcon.Kind.TIME: "Time"}
	for kind in [ScoreIcon.Kind.FUEL, ScoreIcon.Kind.HULL, ScoreIcon.Kind.TIME]:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 10)
		var icon := ScoreIcon.new(kind, Progress.Medal.NONE, 22.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(icon)
		var caption := Label.new()
		caption.text = part_names[kind]
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_font_size_override("font_size", 20)
		caption.add_theme_color_override("font_color", Style.INK_DIM)
		cell.add_child(caption)
		var value := Label.new()
		value.custom_minimum_size.x = 80
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 20)
		if kind == ScoreIcon.Kind.TIME:
			value.add_theme_color_override("font_color", Color("#ff9a90"))
		cell.add_child(value)
		_parts[kind] = value
		parts.add_child(cell)
	_standing = Label.new()
	_standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_standing.add_theme_font_size_override("font_size", 22)
	_standing.add_theme_color_override("font_color", Style.INK_DIM)
	_standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_standing.custom_minimum_size.x = 340
	_standing.hide()
	_board_scroll = ScrollContainer.new()
	_board_scroll.custom_minimum_size = Vector2(700, 440)
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board_scroll.hide()
	body.add_child(_board_scroll)
	_board_preview = VBoxContainer.new()
	_board_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scroll.add_child(_board_preview)
	_board_preview.add_child(_standing)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 24)
	column.add_child(_detail)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_next = Style.primary(_button(actions, next_text, next_requested.emit))
	_retry = _button(actions, "Retry", retry_requested.emit)
	_replay = Style.subtle(_button(actions, "Replay", replay_requested.emit))
	_rate = Style.subtle(_button(actions, "Rate level", rate_requested.emit))
	_board = Style.subtle(_button(actions, "Board", board_requested.emit))
	Style.subtle(_button(actions, menu_text, menu_requested.emit))
	_pause = PauseCard.new()
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.resume_requested.connect(toggle_pause)
	_pause.hide()
	add_child(_pause)
	var pause_column := VBoxContainer.new()
	pause_column.add_theme_constant_override("separation", 12)
	_pause.add_child(pause_column)
	_resume = _button(pause_column, "Resume", toggle_pause)
	_button(pause_column, "Settings", SettingsScreen.open.bind(_pause))
	_button(pause_column, "Restart", retry_requested.emit)
	_button(pause_column, menu_text, menu_requested.emit)
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
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
		var low := not ship.fuel_unlimited and ship.fuel < LOW_FUEL * Ship.MAX_FUEL
		var lit := fmod(Time.get_ticks_msec() * 0.001 * BLINK_HZ, 1.0) < 0.5
		_fuel.modulate.a = 0.25 if low and not lit else 1.0
		_health.value = ship.health
		_effect.text = ship.effect_text()
		_speed.visible = Tuning.show_speedometer
		_speed.text = speed_text(ship.linear_velocity.length())  # world frame: relative to the background
		var left := ship.empty_seconds_left()
		_show_countdown(left)
		_arrow.queue_redraw()
		_time.text = "%.1f s" % ship.flight_time
		if _intro.visible and ship.flight_time > 0.0 and not _intro_fading:
			_intro_fading = true
			var fade := create_tween()
			fade.tween_property(_intro, "modulate:a", 0.0, INTRO_FADE)
			fade.tween_callback(_intro.hide)


## Shows or hides the pause card, pausing or unpausing the tree. Does nothing on the end panel.
func toggle_pause() -> void:
	if _result.visible or not _pause.find_children("*", "Overlay", true, false).is_empty():
		return
	_pause.visible = not _pause.visible
	get_tree().paused = _pause.visible
	if _pause.visible:
		_prior_focus = get_viewport().gui_get_focus_owner()
		_pause.reset_size()
		_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_resume.grab_focus(true)
	elif is_instance_valid(_prior_focus) and _prior_focus.is_visible_in_tree():
		_prior_focus.grab_focus(true)


func _exit_tree() -> void:
	get_tree().paused = false  # a scene change from the pause card must not leave the next scene paused
	Monetization.clear_surface(self)


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


## `result` keys: name; won → points, fuel_points, hull_points, time_points, new_best, has_next, has_par,
## par (the medal slots show only with has_par, and fill as the total counts up to points);
## lost → cause; optional can_rate (a community stage whose feedback the player may give) shows Rate level.
func show_result(won: bool, result: Dictionary) -> void:
	_intro.hide()
	_result_name.text = result.name
	_result_name.visible = result.name != ""
	_result_label.text = "Course clear" if won else "Lost"
	_result_label.add_theme_color_override("font_color", GOAL_GREEN if won else WARNING)
	_score.visible = won
	_detail.visible = not won
	if won:
		_best_pill.visible = result.new_best
		_best.visible = result.new_best
		_parts[ScoreIcon.Kind.FUEL].text = "+%d" % result.fuel_points
		_parts[ScoreIcon.Kind.HULL].text = "+%d" % result.hull_points
		_parts[ScoreIcon.Kind.TIME].text = "−%d" % result.time_points
		_medal.visible = result.has_par
		_par_box.visible = result.has_par
		var par: int = result.get("par", 0)
		_update_par_caption(result.points, par)
		_count_up(result.points, par)
	else:
		_detail.text = result.cause
	_next.visible = won and result.has_next
	_replay.visible = can_replay
	_rate.visible = result.get("can_rate", false)
	_board.visible = won and result.get("can_board", false)
	_board_scroll.visible = _board.visible
	if not _board.visible:
		set_standing("")
	_result.reset_size()
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.show()
	Monetization.set_surface(self, true)
	get_tree().create_timer(RESULT_FOCUS_DELAY).timeout.connect(_focus_result)



## Replaces only the online status, leaving score animation, medals and focus untouched.
func set_standing(text: String) -> void:
	_standing.text = text
	_standing.visible = text != ""


func set_board(board: Dictionary, local_points: int) -> void:
	Leaderboard.preview(_board_preview, board, local_points)

func _focus_result() -> void:
	if not is_inside_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return  # a sheet opened inside the delay already has the focus: the card must not take it
	for button: Button in _next.get_parent().get_children().filter(func(c: Node) -> bool: return c is Button):
		if button.visible and not button.disabled:
			button.grab_focus(true)
			break


## The total counts up from 0 to `points` over COUNT_SECONDS; each medal slot fills the moment the
## count reaches its threshold. Without a par the slots are hidden and only the count runs.
func _count_up(points: int, par: int) -> void:
	if _count:
		_count.kill()
	_set_count(0, par)
	_count = create_tween()
	_count.tween_method(_set_count.bind(par), 0, points, COUNT_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _set_count(value: int, par: int) -> void:
	_total.text = str(value)
	var earned := Progress.medal(value, par)
	for tier in _slots:
		var slot: ScoreIcon = _slots[tier]
		var was_empty := slot.empty
		slot.empty = tier > earned
		if value > 0 and was_empty and not slot.empty:
			slot.scale = Vector2.ONE * 1.28
			create_tween().tween_property(slot, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if par > 0:
		_par_bar.set_progress(float(value) / float(par), earned)


func _update_par_caption(points: int, par: int) -> void:
	if par <= 0:
		_par_next.text = ""
		return
	var next_pts := Progress.next_threshold(points, par)
	if next_pts <= 0:
		_par_next.text = "Gold medal earned!"
		_par_next.add_theme_color_override("font_color", ScoreIcon.MEDAL_COLORS[Progress.Medal.GOLD])
	else:
		var next_tier := Progress.medal(next_pts, par)
		var tier_name: String = Progress.Medal.keys()[next_tier].capitalize()
		_par_next.text = "Next: %s %d (%d pts to go)" % [tier_name, next_pts, next_pts - points]
		_par_next.add_theme_color_override("font_color", Style.INK_DIM)


class ParBar extends Control:
	var _ratio := 0.0
	var _medal := Progress.Medal.NONE

	func _init() -> void:
		custom_minimum_size = Vector2(0, 10)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_progress(ratio: float, earned: Progress.Medal) -> void:
		_ratio = clampf(ratio, 0.0, 1.0)
		_medal = earned
		queue_redraw()

	func _draw() -> void:
		var radius := size.y * 0.5
		var track := StyleBoxFlat.new()
		track.bg_color = Color(Style.BORDER, 0.35)
		track.set_corner_radius_all(int(radius))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		if _ratio > 0.0:
			var fill_w := maxf(size.y, size.x * _ratio)
			var fill := StyleBoxFlat.new()
			fill.bg_color = ScoreIcon.MEDAL_COLORS.get(_medal, Style.ACCENT)
			fill.set_corner_radius_all(int(radius))
			draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(minf(fill_w, size.x), size.y)))
		for mark: float in [Progress.BRONZE_FRACTION, Progress.SILVER_FRACTION]:
			var x := size.x * mark
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.45), 2.0)


## Everything the end panel shows, for tests.
func result_text() -> String:
	var lines := [_result_name.text, _result_label.text]
	if _score.visible:
		lines.append(_total.text)
		if _best.visible:
			lines.append(_best.text)
		if _medal.visible:
			lines.append("Medals: %s" % ", ".join(_slots.keys().filter(func(t: int) -> bool: return not _slots[t].empty).map(func(t: int) -> String: return Progress.Medal.keys()[t].capitalize())))
		for kind in _parts:
			lines.append(_parts[kind].text)
	else:
		lines.append(_detail.text)
	if _standing.visible:
		lines.append(_standing.text)
	if _board_scroll.visible:
		for label: Label in _board_preview.find_children("*", "Label", true, false):
			if label != _standing and label.is_visible_in_tree():
				lines.append(label.text)
	return "\n".join(lines)


## Whether a visible HUD button holds `screen_pos`, so a touch there is the button's, not the ship's.
func blocks(screen_pos: Vector2) -> bool:
	return find_children("", "Button", true, false).any(func(b: Button) -> bool: return b.is_visible_in_tree() and b.get_global_rect().has_point(screen_pos))


## Where the off-screen goal arrow sits: `target` (screen px) pulled in to the screen edge,
## `margin` px inside it, along the line from the screen centre.
static func edge_point(target: Vector2, screen: Vector2, margin: float) -> Vector2:
	var centre := screen / 2.0
	var direction := target - centre
	var half := centre - Vector2(margin, margin)
	var scale := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	return centre + direction * minf(scale, 1.0)


func _draw_arrow() -> void:
	if not ship or not goal or not goal.visible or not visible or _result.visible:
		return
	var screen := _arrow.get_viewport_rect().size
	var target := ship.get_viewport().canvas_transform * goal.global_position
	if Rect2(Vector2.ZERO, screen).grow(-ARROW_MARGIN).has_point(target):
		return  # the goal is on screen
	var at := edge_point(target, screen, ARROW_MARGIN)
	var angle := (target - screen / 2.0).angle()
	var tip := PackedVector2Array([Vector2(22, 0), Vector2(-12, 14), Vector2(-6, 0), Vector2(-12, -14)])
	_arrow.draw_set_transform(at, angle)
	_arrow.draw_colored_polygon(tip, GOAL_GREEN)
	_arrow.draw_set_transform(Vector2.ZERO)
	var text := distance_text(ship.global_position.distance_to(goal.global_position))
	_arrow.draw_string(_arrow.get_theme_default_font(), at - Vector2.from_angle(angle) * 56.0 - Vector2(50, -9), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 24, GOAL_GREEN)


## The game's distance unit: 10 px per metre, so the 32 px ship is about 3 m long.
static func distance_text(px: float) -> String:
	var metres := px * METRES_PER_PX
	return "%.1f km" % (metres / 1000.0) if metres >= 1000.0 else "%d m" % roundi(metres)


static func speed_text(px_per_second: float) -> String:
	return "%d m/s" % roundi(px_per_second * METRES_PER_PX)


## A gauge: the ship-part icon (as on the score panel) and a rounded, bordered bar; "∞" after it
## when the level makes that resource unlimited.
func _bar(parent: Control, icon: ScoreIcon.Kind, maximum: float, unlimited := false) -> ProgressBar:
	var color: Color = ScoreIcon.COLORS[icon]
	var symbol := ScoreIcon.new(icon)
	symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(symbol)
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = maximum
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.06, 0.12, 0.85)
	back.border_color = Color(color, 0.7)
	back.set_border_width_all(2)
	back.set_corner_radius_all(11)
	bar.add_theme_stylebox_override("background", back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(11)
	fill.set_expand_margin_all(-3)  # inset, so the border frames the fill
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	if unlimited:
		var infinite := Label.new()
		infinite.text = "∞"
		infinite.add_theme_font_size_override("font_size", 30)
		infinite.add_theme_color_override("font_color", color)
		parent.add_child(infinite)
	return bar


## `focus` false for buttons that must never hold keyboard focus (the in-level top bar).
func _button(parent: Control, text: String, action: Callable, focus := true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 24)
	if not focus:
		button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button
