extends Node
## The game's look in one place: the UI theme (fonts, panels, buttons) and the 2D bloom.
## Autoloaded as `Style`.

const INK := Color("#dfe9ff")
const INK_DIM := Color("#6f7d96")
const ACCENT := Color("#3aa0ff")
const PANEL := Color(0.04, 0.06, 0.12, 0.88)
const BORDER := Color("#2a4a7a")

## Orbitron, for titles and big numbers.
var display_font: Font
## Whether the player touches the screen; tests set it.
var touchscreen := DisplayServer.is_touchscreen_available()


func _ready() -> void:
	display_font = _weight(load("res://assets/fonts/Orbitron.ttf"), 700)
	# Into the engine default theme, not root.theme: controls under a CanvasLayer (HUD, menu)
	# stop inheriting at the layer and fall back to the default theme.
	var theme := _theme()
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.get_default_theme().default_font_size = theme.default_font_size
	add_child(_bloom())
	get_tree().node_added.connect(_fit_button_to_touch)


## Godot turns each touch into an emulated mouse as well, which hovers whatever lies under the finger, even
## after it lifts. A finger has no hover, so on a touchscreen a button's hover look is its look at rest,
## copied as it enters the tree: override a button's own looks before adding it.
## A button stops touches by default, so a drag that starts on one never scrolls its list and lifts as a tap.
## PASS lets the list see it; once the drag passes the scroll deadzone, the list cancels the button's press.
func _fit_button_to_touch(node: Node) -> void:
	if touchscreen and node is Button:
		node.add_theme_stylebox_override("hover", node.get_theme_stylebox("normal"))
		node.add_theme_stylebox_override("hover_pressed", node.get_theme_stylebox("pressed"))
		node.add_theme_color_override("font_hover_color", node.get_theme_color("font_color"))
		node.add_theme_color_override("font_hover_pressed_color", node.get_theme_color("font_pressed_color"))
	if not (node is BaseButton and node.mouse_filter == Control.MOUSE_FILTER_STOP):
		return
	var parent := node.get_parent()
	while parent:
		if parent is ScrollContainer:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
			return
		parent = parent.get_parent()


## Gives keyboard and gamepad focus to the first enabled button under `root`, if any, with the
## ring hidden until the player navigates (a phone never shows it).
func focus_first(root: Node) -> void:
	for button: Button in root.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode == Control.FOCUS_ALL:
			button.grab_focus(true)
			return


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
		_layout()

	func _layout() -> void:
		var safe := Rect2()
		if OS.has_feature("mobile"):
			safe = get_viewport().get_screen_transform().affine_inverse() * Rect2(DisplayServer.get_display_safe_area())
		var area := Style.menu_rect(get_viewport_rect(), safe)
		position = area.position
		size = area.size


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
