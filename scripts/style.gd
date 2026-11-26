extends Node
## The game's look in one place: the UI theme (fonts, panels, buttons) and the 2D bloom.
## Autoloaded as `Style`.

const INK := Color("#dfe9ff")
const INK_DIM := Color("#6f7d96")
const ACCENT := Color("#3aa0ff")
const LIKE := Color("#ff5c8a")
const WARNING := Color("#ffcf4a")
const PANEL := Color(0.04, 0.06, 0.12, 0.88)
const PANEL_INSET := Color(0.02, 0.035, 0.075, 0.82)
const PANEL_SUBTLE := Color(0.035, 0.055, 0.11, 0.65)
const BORDER := Color("#2a4a7a")
const BORDER_SOFT := Color(0.165, 0.29, 0.478, 0.55)
const PRESS_DELAY := 0.1  # s: Android's tap timeout, before a listed button looks pressed

## Orbitron, for titles and big numbers.
var display_font: Font
## Whether the player last pointed with a finger rather than a mouse: buttons then have no hover look.
var touch := DisplayServer.is_touchscreen_available():
	set(value):
		if value == touch:
			return
		touch = value
		if is_inside_tree():
			for button: Button in get_tree().root.find_children("*", "Button", true, false):
				_fit_hover(button)


func _ready() -> void:
	display_font = _weight(load("res://assets/fonts/Orbitron.ttf"), 700)
	# Into the engine default theme, not root.theme: controls under a CanvasLayer (HUD, menu)
	# stop inheriting at the layer and fall back to the default theme.
	var theme := _theme()
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.get_default_theme().default_font_size = theme.default_font_size
	add_child(_bloom())
	process_mode = Node.PROCESS_MODE_ALWAYS  # the pause card's buttons follow the pointer too
	get_tree().node_added.connect(_fit_button_to_touch)


## The last pointer decides, as in ShipInput: a touch, or a real mouse moving. A touch's emulated mouse
## and the engine's internal events do not count, and keys and pads leave the look as it is (their focus
## ring is a separate look).
func _input(event: InputEvent) -> void:
	if event.device < 0:  # DEVICE_ID_EMULATION or DEVICE_ID_INTERNAL
		return
	if event is InputEventScreenTouch:
		touch = true
	elif event is InputEventMouseMotion:
		touch = false


## A button stops touches by default, so a drag that starts on one never scrolls its list and lifts as a tap.
## PASS lets the list see it; once the drag passes the scroll deadzone, the list cancels the button's press.
func _fit_button_to_touch(node: Node) -> void:
	if node is Button:
		_fit_hover(node)
	if not (node is BaseButton and node.mouse_filter == Control.MOUSE_FILTER_STOP):
		return
	var parent := node.get_parent()
	while parent:
		if parent is ScrollContainer:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
			if node is Button:
				node.button_down.connect(_delay_press_look.bind(node))
			return
		parent = parent.get_parent()


## A finger that lands on a listed button may be starting a scroll, which only shows once it passes the
## deadzone. As Android's lists do, the button looks pressed only once the finger has rested for a moment,
## so a scroll never flashes it. Toggles keep their look: theirs says whether they are on.
func _delay_press_look(button: Button) -> void:
	if not touch or button.toggle_mode:
		return
	var own_look := button.has_theme_stylebox_override("pressed") or button.has_theme_color_override("font_pressed_color")
	if own_look and not button.has_meta(&"press_delay"):
		return
	var press: int = button.get_meta(&"press_delay", 0) + 1  # a press again within the delay restarts it
	button.set_meta(&"press_delay", press)
	button.add_theme_stylebox_override("pressed", button.get_theme_stylebox("normal"))
	button.add_theme_color_override("font_pressed_color", button.get_theme_color("font_color"))
	await get_tree().create_timer(PRESS_DELAY, true).timeout
	if is_instance_valid(button) and button.get_meta(&"press_delay", 0) == press:
		button.remove_meta(&"press_delay")
		button.remove_theme_stylebox_override("pressed")
		button.remove_theme_color_override("font_pressed_color")


## Godot turns each touch into an emulated mouse as well, which hovers whatever lies under the finger, even
## after it lifts. A finger has no hover, so after a touch a button's hover look is its look at rest, copied
## from it: override a button's own looks before adding it. A button's own hover looks are left alone unless
## Style itself installed them (`style_hover`).
func _fit_hover(button: Button) -> void:
	if button.has_theme_stylebox_override("hover") and not button.has_meta(&"touch_hover") and not button.has_meta(&"style_hover"):
		return
	if touch:
		if button.has_meta(&"style_hover") and not button.has_meta(&"touch_hover"):
			button.set_meta(&"saved_hover", button.get_theme_stylebox("hover"))
			button.set_meta(&"saved_hover_pressed", button.get_theme_stylebox("hover_pressed"))
			button.set_meta(&"saved_font_hover", button.get_theme_color("font_hover_color"))
			button.set_meta(&"saved_font_hover_pressed", button.get_theme_color("font_hover_pressed_color"))
		button.set_meta(&"touch_hover", true)
		button.add_theme_stylebox_override("hover", button.get_theme_stylebox("normal"))
		button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
		button.add_theme_color_override("font_hover_color", button.get_theme_color("font_color"))
		button.add_theme_color_override("font_hover_pressed_color", button.get_theme_color("font_pressed_color"))
	elif button.has_meta(&"touch_hover"):
		button.remove_meta(&"touch_hover")
		if button.has_meta(&"saved_hover"):
			button.add_theme_stylebox_override("hover", button.get_meta(&"saved_hover"))
			button.add_theme_stylebox_override("hover_pressed", button.get_meta(&"saved_hover_pressed"))
			button.add_theme_color_override("font_hover_color", button.get_meta(&"saved_font_hover"))
			button.add_theme_color_override("font_hover_pressed_color", button.get_meta(&"saved_font_hover_pressed"))
			for key in [&"saved_hover", &"saved_hover_pressed", &"saved_font_hover", &"saved_font_hover_pressed"]:
				button.remove_meta(key)
		else:
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_stylebox_override("hover_pressed")
			button.remove_theme_color_override("font_hover_color")
			button.remove_theme_color_override("font_hover_pressed_color")


## Gives keyboard and gamepad focus to the first enabled button under `root`, if any, with the
## ring hidden until the player navigates (a phone never shows it).
func focus_first(root: Node) -> void:
	for button: Button in root.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode == Control.FOCUS_ALL:
			button.grab_focus(true)
			return


## Primary CTA button: strong accent fill with distinct hover and pressed states.
func primary(button: Button) -> Button:
	button.set_meta(&"style_hover", true)
	button.add_theme_stylebox_override("normal", _box(Color("#1658a6"), Color("#60b8ff"), 10))
	button.add_theme_stylebox_override("hover", _box(Color("#206dc7"), Color("#96d2ff"), 10))
	button.add_theme_stylebox_override("pressed", _box(Color("#0f407d"), ACCENT, 10))
	button.add_theme_stylebox_override("hover_pressed", _box(Color("#154f96"), Color("#60b8ff"), 10))
	for color in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color, Color.WHITE)
	_fit_hover(button)
	return button


## Quiet secondary button (Back, Close, Settings, secondary actions).
func subtle(button: Button) -> Button:
	button.set_meta(&"style_hover", true)
	button.add_theme_stylebox_override("normal", _box(PANEL_SUBTLE, BORDER_SOFT, 10))
	button.add_theme_stylebox_override("hover", _box(Color(0.07, 0.12, 0.22, 0.92), ACCENT, 10))
	button.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.2, 0.36, 0.95), ACCENT, 10))
	button.add_theme_stylebox_override("hover_pressed", _box(Color(0.1, 0.2, 0.36, 0.95), ACCENT, 10))
	button.add_theme_color_override("font_color", Color("#b7c8e6"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	_fit_hover(button)
	return button


## Marks a destructive button: warning colour text and subtle red-tinted border/fill.
func danger(button: Button) -> Button:
	button.set_meta(&"style_hover", true)
	button.add_theme_stylebox_override("normal", _box(Color(0.19, 0.055, 0.075, 0.78), Color(Hud.WARNING, 0.55), 10))
	button.add_theme_stylebox_override("hover", _box(Color(0.35, 0.085, 0.11, 0.92), Hud.WARNING, 10))
	button.add_theme_stylebox_override("pressed", _box(Color(0.45, 0.1, 0.13, 0.96), Hud.WARNING, 10))
	button.add_theme_stylebox_override("hover_pressed", _box(Color(0.45, 0.1, 0.13, 0.96), Hud.WARNING, 10))
	for color in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color, Hud.WARNING if color == "font_color" or color == "font_focus_color" else Color.WHITE)
	_fit_hover(button)
	return button


## Styles a toggle button so its active (pressed) state stands out with `color`.
func toggle_tint(button: Button, color: Color, radius := 10) -> Button:
	button.set_meta(&"style_hover", true)
	var active_text := color.lightened(0.35)
	button.add_theme_stylebox_override("normal", _box(PANEL_SUBTLE, BORDER_SOFT, radius))
	button.add_theme_stylebox_override("hover", _box(Color(0.07, 0.12, 0.22, 0.92), Color(color, 0.75), radius))
	button.add_theme_stylebox_override("pressed", _box(Color(color, 0.22), color, radius))
	button.add_theme_stylebox_override("hover_pressed", _box(Color(color, 0.28), color.lightened(0.2), radius))
	button.add_theme_color_override("font_color", INK_DIM)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", active_text)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	_fit_hover(button)
	return button


## Compact rounded pill badge for status, likes, or metadata.
static func pill(text: String, color: Color, filled := false, font_size := 18) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(12)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	box.bg_color = color if filled else Color(color, 0.14)
	box.border_color = color if filled else Color(color, 0.5)
	box.set_border_width_all(0 if filled else 1)
	panel.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#06101f") if filled else color.lightened(0.28))
	panel.add_child(label)
	return panel


## Inset stat tile: large display number over a dim caption.
func kpi_tile(value: String, caption: String, value_color := INK) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := _box(PANEL_INSET, BORDER_SOFT, 10, 10)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var num := Label.new()
	num.text = value
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_override("font", display_font)
	num.add_theme_font_size_override("font_size", 26)
	num.add_theme_color_override("font_color", value_color)
	col.add_child(num)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_font_size_override("font_size", 16)
	cap.add_theme_color_override("font_color", INK_DIM)
	col.add_child(cap)
	return panel


## Coroutine: runs `work` while `button` says `label` and cannot be tapped again, so the player sees the wait; afterwards the button is as it was, if it is still on screen.
func busy(button: Button, label: String, work: Callable) -> void:
	var text := button.text
	button.text = label
	button.disabled = true
	await work.call()
	if is_instance_valid(button) and button.is_inside_tree():
		button.text = text
		button.disabled = false


## A shared content frame; backgrounds and modal input blockers stay outside it.
func menu_frame(parent: Node) -> Control:
	var frame := MenuFrame.new()
	parent.add_child(frame)
	return frame


## Fit menu content without stretching it or entering cutout/system-bar insets.
static func menu_rect(viewport: Rect2, safe_area := Rect2()) -> Rect2:
	var available := viewport.intersection(safe_area) if safe_area.has_area() else viewport
	var fitted := available.size
	fitted.x = minf(fitted.x, fitted.y * 16.0 / 9.0)
	fitted.y = minf(fitted.y, fitted.x * 9.0 / 16.0)
	return Rect2(available.position + (available.size - fitted) / 2.0, fitted)


class MenuFrame extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		get_viewport().size_changed.connect(_layout)
		Monetization.changed.connect(_layout)
		_layout()

	func _exit_tree() -> void:
		if is_instance_valid(Monetization) and Monetization.changed.is_connected(_layout):
			Monetization.changed.disconnect(_layout)

	func _layout() -> void:
		var safe := Rect2()
		if OS.has_feature("mobile"):
			safe = get_viewport().get_screen_transform().affine_inverse() * Rect2(DisplayServer.get_display_safe_area())
		var area := Style.menu_rect(get_viewport_rect(), safe)
		var footer := Monetization.footer_height if is_instance_valid(Monetization) else 0.0
		position = area.position
		size = Vector2(area.size.x, maxf(0.0, area.size.y - footer))


## Bright things (lasers, flames, the ship) glow. Only the game world blooms: HUD and menus sit
## on canvas layers above `background_canvas_max_layer` and stay crisp.
func _bloom() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = 0
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world := WorldEnvironment.new()
	world.environment = env
	return world


func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = _weight(load("res://assets/fonts/Exo2.ttf"), 500)
	theme.default_font_size = 24
	for type in ["Label", "Button", "CheckButton"]:
		theme.set_color("font_color", type, INK)
	theme.set_color("font_disabled_color", "Button", INK_DIM)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_stylebox("normal", "Button", _box(PANEL, BORDER, 10))
	theme.set_stylebox("hover", "Button", _box(Color(0.07, 0.12, 0.22, 0.92), ACCENT, 10))
	theme.set_stylebox("pressed", "Button", _box(Color(0.1, 0.2, 0.36, 0.95), ACCENT, 10))
	theme.set_stylebox("disabled", "Button", _box(Color(0.03, 0.04, 0.08, 0.7), Color(BORDER, 0.5), 10))
	theme.set_stylebox("focus", "Button", _focus_ring(10))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 14, 18))
	theme.set_stylebox("background", "ProgressBar", _box(Color(0.06, 0.09, 0.16, 0.9), Color(BORDER, 0.6), 6, 0))
	return theme


static func _box(fill: Color, border: Color, radius: int, margin := 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


## An outline just outside a button's own border, so the focused one shows for keyboard and gamepad.
static func _focus_ring(radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = INK
	box.set_border_width_all(3)
	box.set_corner_radius_all(radius + 3)
	box.set_expand_margin_all(3)
	return box


static func _weight(font: FontFile, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return variation
