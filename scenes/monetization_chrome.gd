class_name MonetizationChrome
extends CanvasLayer
## The purchase shortcut sits above the game's own controls; only the button receives input.

var _root: Control
var _button: Button
var _surface: Node


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_button = Button.new()
	_button.text = "Remove ads"
	_button.custom_minimum_size = Vector2(160, 48)
	_button.add_theme_font_size_override("font_size", 20)
	_button.visible = false
	_button.pressed.connect(_open_purchase)
	_root.add_child(_button)


func update(layout: Dictionary, shown: bool, surface: Node) -> void:
	_surface = surface
	var target: Rect2 = layout.get("button_rect", Rect2())
	var visible := shown and target.size.x > 0.0 and target.size.y > 0.0
	if _button.visible and not visible and get_viewport().gui_get_focus_owner() == _button:
		_button.release_focus()
		if is_instance_valid(_surface):
			Style.focus_first(_surface)
	_button.visible = visible
	if visible:
		_button.position = target.position
		_button.size = target.size


func _open_purchase() -> void:
	if is_instance_valid(_surface) and _surface.is_inside_tree() and _button.visible:
		PurchaseScreen.open(_surface)


## `ad_pixels` is in physical screen pixels; Godot controls remain in viewport coordinates.
static func layout(viewport: Rect2, safe_area: Rect2, screen_transform: Transform2D, density: float, button_minimum: Vector2) -> Dictionary:
	var empty := {"ad_pixels": Rect2i(), "button_rect": Rect2(), "footer_height": 0.0, "show_ad": false}
	var scale_x := screen_transform.x.length()
	var scale_y := screen_transform.y.length()
	if density <= 0.0 or scale_x <= 0.0 or scale_y <= 0.0:
		return empty

	var frame := Style.menu_rect(viewport, safe_area)
	var dp := Vector2(density / scale_x, density / scale_y)
	var padding := 8.0 * dp
	var ad_size := Vector2(320.0, 50.0) * dp
	var button_size := Vector2(maxf(button_minimum.x, 0.0), maxf(button_minimum.y, 48.0 * dp.y))
	var footer_height := maxf(ad_size.y, button_size.y) + 2.0 * padding.y
	if frame.size.x < button_size.x + 2.0 * padding.x or frame.size.y < footer_height:
		return empty

	var button_rect := Rect2(
		Vector2(frame.end.x - padding.x - button_size.x, frame.end.y - padding.y - button_size.y),
		button_size,
	)
	var ad_rect := Rect2(
		Vector2(frame.get_center().x - ad_size.x / 2.0, frame.end.y - padding.y - ad_size.y),
		ad_size,
	)
	var show_ad := ad_rect.position.x >= frame.position.x + padding.x \
		and ad_rect.end.x <= frame.end.x - padding.x \
		and button_rect.position.x - ad_rect.end.x >= 24.0 * dp.x
	return {
		"ad_pixels": Rect2i(screen_transform * ad_rect) if show_ad else Rect2i(),
		"button_rect": button_rect,
		"footer_height": footer_height,
		"show_ad": show_ad,
	}


func button_minimum() -> Vector2:
	return _button.get_combined_minimum_size()
