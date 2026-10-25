extends "res://tests/test_case.gd"


func test_ultrawide_menu_keeps_a_centered_sixteen_by_nine_area() -> void:
	if not Style.has_method("menu_rect"):
		check(false, "menus need shared aspect-constrained layout")
		return
	var area: Rect2 = Style.call("menu_rect", Rect2(0, 0, 1680, 720), Rect2())
	check(area.is_equal_approx(Rect2(200, 0, 1280, 720)), "ultrawide menu area: %s" % area)


func test_menu_area_stays_inside_cutout_and_system_bar_insets() -> void:
	if not Style.has_method("menu_rect"):
		check(false, "menus need shared safe-area layout")
		return
	var viewport := Rect2(0, 0, 1280, 720)
	var safe := Rect2(80, 20, 1200, 680)
	var area: Rect2 = Style.call("menu_rect", viewport, safe)
	check(safe.encloses(area) and viewport.encloses(area), "menu must not overlap excluded edges: %s" % area)
	check(is_equal_approx(area.size.x / area.size.y, 16.0 / 9.0), "inset menu retains its aspect: %s" % area)
	check(area.get_center().is_equal_approx(safe.get_center()), "inset menu is centered in usable space: %s" % area)


func test_taller_windows_and_oversized_safe_rects_still_fit() -> void:
	if not Style.has_method("menu_rect"):
		check(false, "menus need shared bounded layout")
		return
	var area: Rect2 = Style.call("menu_rect", Rect2(0, 0, 1280, 960), Rect2())
	check(area.is_equal_approx(Rect2(0, 120, 1280, 720)), "taller window fits without stretching: %s" % area)
	area = Style.call("menu_rect", Rect2(0, 0, 1680, 720), Rect2(-30, -40, 1800, 800))
	check(area.is_equal_approx(Rect2(200, 0, 1280, 720)), "safe bounds cannot expand beyond the viewport: %s" % area)


func test_menu_frame_follows_its_own_viewport_resize() -> void:
	if not Style.has_method("menu_frame"):
		check(false, "menu frames must track viewport size")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1680, 720)
	world.add_child(viewport)
	var frame: Control = Style.call("menu_frame", viewport)
	await frames(2)
	check(frame.get_rect().is_equal_approx(Rect2(200, 0, 1280, 720)), "initial frame geometry: %s" % frame.get_rect())
	viewport.size = Vector2i(1280, 720)
	await frames(2)
	check(frame.get_rect().is_equal_approx(Rect2(0, 0, 1280, 720)), "resized frame geometry: %s" % frame.get_rect())
