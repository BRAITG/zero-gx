class_name MonetizationChrome
extends CanvasLayer
## The purchase shortcut sits above the game's own controls; only the button receives input.

var _root: Control
var _button: Button
var _surface: Node
const TOUCH_TARGET_BASE_META := &"monetization_touch_target_base_height"
const TOUCH_TARGET_WATCHED_META := &"monetization_touch_target_watched"


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
	var banner_size_px := Vector2i(ceili(320.0 * density), ceili(50.0 * density))
	var ad_size := Vector2(banner_size_px.x / scale_x, banner_size_px.y / scale_y)
	var button_size := Vector2(maxf(button_minimum.x, 0.0), maxf(button_minimum.y, 48.0 * dp.y))
	var button_footer := button_size.y + 2.0 * padding.y
	var banner_footer := ad_size.y + 2.0 * padding.y
	if frame.size.x < button_size.x + 2.0 * padding.x or frame.size.y < button_footer:
		return empty

	var button_rect := Rect2(
		Vector2(frame.end.x - padding.x - button_size.x, frame.end.y - padding.y - button_size.y),
		button_size,
	)
	var screen_frame: Rect2 = screen_transform * frame
	var banner_padding_px := ceili(8.0 * density)
	var ad_pixels := Rect2i(
		Vector2i(
			roundi(screen_frame.get_center().x - banner_size_px.x / 2.0),
			floori(screen_frame.end.y - banner_padding_px) - banner_size_px.y,
		),
		banner_size_px,
	)
	var screen_ad: Rect2 = Rect2(ad_pixels)
	var screen_button: Rect2 = screen_transform * button_rect
	var banner_fits := frame.size.y >= banner_footer
	var show_ad := banner_fits \
		and screen_ad.position.x - screen_frame.position.x >= 8.0 * density \
		and screen_frame.end.x - screen_ad.end.x >= 8.0 * density \
		and screen_ad.position.y - screen_frame.position.y >= 8.0 * density \
		and screen_frame.end.y - screen_ad.end.y >= 8.0 * density \
		and screen_button.position.x - screen_ad.end.x >= ceili(24.0 * density)
	var footer_height := maxf(button_size.y, ad_size.y) + 2.0 * padding.y if banner_fits else button_footer
	return {
		"ad_pixels": ad_pixels if show_ad else Rect2i(),
		"button_rect": button_rect,
		"footer_height": footer_height,
		"show_ad": show_ad,
	}


func button_minimum() -> Vector2:
	return _button.get_combined_minimum_size()


static func ensure_touch_target(control: Control) -> void:
	if not control.is_inside_tree() or not Monetization.available():
		return
	if not control.has_meta(TOUCH_TARGET_BASE_META):
		control.set_meta(TOUCH_TARGET_BASE_META, control.custom_minimum_size.y)
	if not control.has_meta(TOUCH_TARGET_WATCHED_META):
		var viewport: Viewport = control.get_viewport()
		var window: Window = control.get_window()
		var update: Callable = func() -> void:
			MonetizationChrome._update_touch_target(control)
		viewport.size_changed.connect(update)
		if window != null and window != viewport:
			window.size_changed.connect(update)
		var cleanup := Callable(MonetizationChrome, "_disconnect_touch_target").bind(control, viewport, window, update)
		control.tree_exited.connect(cleanup, CONNECT_ONE_SHOT)
		control.set_meta(TOUCH_TARGET_WATCHED_META, true)
	_update_touch_target(control)


static func _update_touch_target(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree() or not Monetization.available():
		return
	var scale_y := control.get_viewport().get_screen_transform().y.length()
	if scale_y <= 0.0:
		return
	var density := float(Monetization.platform.call("getDensity"))
	var base_height := float(control.get_meta(TOUCH_TARGET_BASE_META, control.custom_minimum_size.y))
	control.custom_minimum_size.y = maxf(base_height, 48.0 * density / scale_y)


static func _disconnect_touch_target(control: Control, viewport: Viewport, window: Window, update: Callable) -> void:
	if is_instance_valid(viewport) and viewport.size_changed.is_connected(update):
		viewport.size_changed.disconnect(update)
	if is_instance_valid(window) and window != viewport and window.size_changed.is_connected(update):
		window.size_changed.disconnect(update)
	if is_instance_valid(control):
		control.custom_minimum_size.y = float(control.get_meta(TOUCH_TARGET_BASE_META, control.custom_minimum_size.y))
		if control.has_meta(TOUCH_TARGET_BASE_META):
			control.remove_meta(TOUCH_TARGET_BASE_META)
		if control.has_meta(TOUCH_TARGET_WATCHED_META):
			control.remove_meta(TOUCH_TARGET_WATCHED_META)
