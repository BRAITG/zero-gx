extends "res://tests/test_case.gd"
## Purchase, footer geometry, and scene lifecycle as visible to a player.

const FAKE_PLATFORM := preload("res://tests/support/fake_monetization_platform.gd")
const CHROME_PATH := "res://scenes/monetization_chrome.gd"
const PURCHASE_SCREEN_PATH := "res://scenes/purchase_screen.gd"
const PURCHASE_ROUTE := "/purchases/ad-free"
const PRICE := "R$ 10,00"
const MAIN := preload("res://scenes/main.gd")


func _boot(cached_ad_free := false) -> Dictionary:
	var money: Variant = tree.root.get_node_or_null("Monetization")
	check(money != null, "the Monetization autoload must be present")
	if money == null:
		return {}
	money.use_defaults()
	var platform: Variant = FAKE_PLATFORM.new()
	platform.cached_ad_free = cached_ad_free
	var transport := FakeTransport.new()
	world.add_child(transport)
	money.platform = platform
	money.transport = transport
	money.start()
	return {"money": money, "platform": platform, "transport": transport}


func _buttons(node: Node, text: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(button: Button) -> bool:
		return button.text == text and button.is_visible_in_tree()
	)


func _button(node: Node, text: String) -> Button:
	var buttons := _buttons(node, text)
	return buttons[0] if not buttons.is_empty() else null


func _touch_height_dp(button: Button, density: float) -> float:
	var physical: Rect2 = button.get_viewport().get_screen_transform() * button.get_global_rect()
	return physical.size.y / density


func _texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			texts.append(label.text)
	for button: Button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			texts.append(button.text)
	return texts


func _purchase_screen(parent: Node) -> Overlay:
	if not ResourceLoader.exists(PURCHASE_SCREEN_PATH):
		check(false, "the purchase screen must provide its player-facing controls")
		return null
	var screen_script: Variant = load(PURCHASE_SCREEN_PATH)
	return screen_script.open(parent)


func _top_overlay(node: Node) -> Overlay:
	var overlays := node.find_children("*", "Overlay", true, false)
	return overlays.back() as Overlay if not overlays.is_empty() else null


func _leave_scene() -> void:
	if tree.current_scene:
		tree.current_scene.free()
		tree.current_scene = null
	tree.paused = false


func test_pending_and_cancelled_purchases_never_grant_ad_free() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	platform.store_state.emit(20, true, PRICE, "")
	var host := Control.new()
	world.add_child(host)
	var purchase := _purchase_screen(host)
	if purchase == null:
		return
	await frames(2)
	var buy := _button(purchase, "Buy")
	check(buy != null and not buy.disabled, "a Play product with a formatted price must permit an explicit Buy")
	if buy == null:
		return
	buy.pressed.emit()
	platform.purchase_state.emit(21, "pending", "", "")
	await frames(2)
	check(not money.ad_free, "a pending purchase must never grant ad-free ownership")
	check(transport.requests.is_empty(), "pending purchases must not be sent for receipt verification")

	buy.pressed.emit()
	platform.purchase_state.emit(22, "cancelled", "", "")
	await frames(2)
	check(not money.ad_free, "a cancelled purchase must never grant ad-free ownership")
	check(purchase.is_inside_tree() and purchase.is_visible_in_tree(), "after Play cancellation the app must return to the purchase screen beneath it")
	var close := _button(purchase, "Close")
	var focus := tree.root.gui_get_focus_owner()
	check(close != null and focus != null and (purchase == focus or purchase.is_ancestor_of(focus)), "cancellation must leave focus on a visible purchase-screen control")
	check(transport.requests.is_empty(), "pending or cancelled purchases must never reach the Worker")


func test_price_comes_from_play_and_unavailable_store_has_no_fallback() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var host := Control.new()
	world.add_child(host)
	var purchase := _purchase_screen(host)
	if purchase == null:
		return
	await frames(2)
	var buy := _button(purchase, "Buy")
	check(buy != null and buy.disabled, "Buy must be disabled until Play supplies a product")
	check(not _texts(purchase).any(func(text: String) -> bool: return text.contains("€3")), "an unavailable store must not show an illustrative price")
	check(_button(purchase, "Restore purchases") != null and _button(purchase, "Close") != null, "Restore purchases and Close must remain explicit controls")

	platform.store_state.emit(100, true, PRICE, "")
	await frames(2)
	check(money.store_ready and money.price == PRICE, "the store's exact formatted price must be retained")
	check(_texts(purchase).any(func(text: String) -> bool: return text.contains(PRICE)), "the purchase UI must display Play's exact formatted price")
	buy = _button(purchase, "Buy")
	check(buy != null and not buy.disabled, "Buy must be enabled when Play supplies the product")

	platform.store_state.emit(101, false, "", "Google Play is unavailable.")
	await frames(2)
	buy = _button(purchase, "Buy")
	check(not money.store_ready and money.price == "", "an unavailable product must not retain a stale price")
	check(buy != null and buy.disabled, "Buy must be disabled when Play has no product")
	check(_texts(purchase).any(func(text: String) -> bool: return text.to_lower().contains("unavailable")), "the unavailable store must have a clear message")
	check(not _texts(purchase).any(func(text: String) -> bool: return text.contains("€3")), "an unavailable store must never fall back to an illustrative price")


func test_safe_frame_layout_tracks_insets_density_and_display_transform() -> void:
	if not ResourceLoader.exists(CHROME_PATH):
		check(false, "the shared monetization chrome layout must exist")
		return
	var chrome: Variant = load(CHROME_PATH)
	for size: Vector2 in [Vector2(1280, 720), Vector2(1680, 720)]:
		var viewport := Rect2(Vector2.ZERO, size)
		var safe_area := Rect2(32, 16, size.x - 64, size.y - 32)
		var safe_frame: Rect2 = Style.call("menu_rect", viewport, safe_area)
		for density: float in [1.0, 2.0, 3.0]:
			var transform := Transform2D(Vector2(density, 0), Vector2(0, density), Vector2(23, 17))
			var layout: Dictionary = chrome.layout(viewport, safe_area, transform, density, Vector2(160, 48))
			if layout.is_empty():
				check(false, "chrome layout must return its full safe-frame geometry")
				return
			var ad: Rect2 = Rect2(layout.ad_pixels)
			var button: Rect2 = layout.button_rect
			var screen_frame: Rect2 = transform * safe_frame
			var screen_button: Rect2 = transform * button
			check(layout.show_ad, "the normal 16:9 frame must fit both controls at density %s" % density)
			check(absf(safe_frame.size.x / safe_frame.size.y - 16.0 / 9.0) < 0.001, "the menu must retain its original safe 16:9 frame")
			check(safe_frame.encloses(button), "the Remove ads target must remain in the unreserved 16:9 safe frame: %s" % button)
			check(screen_frame.encloses(ad), "the physical banner must remain in the transformed safe frame: %s" % ad)
			check(screen_frame.encloses(screen_button), "the transformed shortcut must remain in the safe frame: %s" % screen_button)
			check(is_equal_approx(ad.size.x / density, 320.0) and is_equal_approx(ad.size.y / density, 50.0), "the physical banner must stay 320 × 50 dp at density %s: %s" % [density, ad.size])
			check(button.size.y >= 48.0, "the shortcut must retain its 48 dp minimum touch height: %s" % button.size)
			check((screen_button.position.x - ad.end.x) / density >= 24.0, "the shortcut must stay at least 24 dp right of the banner")
			check((screen_frame.end.x - screen_button.end.x) / density >= 8.0, "the shortcut must keep its 8 dp outer edge padding")
			check((screen_frame.end.y - ad.end.y) / density >= 8.0, "the banner must keep its 8 dp outer footer padding")
			check(absf(ad.get_center().x - screen_frame.get_center().x) <= 1.0, "the banner must be centered after screen translation/scaling")
			check(layout.footer_height >= 66.0, "the fixed footer must reserve 50 dp plus 8 dp outer padding on each edge")


func test_fractional_density_rounds_banner_to_native_pixels() -> void:
	if not ResourceLoader.exists(CHROME_PATH):
		check(false, "the shared monetization chrome layout must exist")
		return
	var chrome: Variant = load(CHROME_PATH)
	var density := 2.75
	var viewport := Rect2(0, 0, 1280, 720)
	var transform := Transform2D(Vector2(density, 0), Vector2(0, density), Vector2(20, 19.5))
	var layout: Dictionary = chrome.layout(viewport, Rect2(), transform, density, Vector2(160, 48))
	var frame: Rect2 = transform * Style.call("menu_rect", viewport, Rect2())
	var ad: Rect2 = Rect2(layout.ad_pixels)
	var screen_button: Rect2 = transform * layout.button_rect
	check(layout.show_ad, "the fractional-density viewport must fit banner and shortcut")
	check(layout.ad_pixels.size == Vector2i(880, 138), "the banner must ceil to native 320 × 50 dp pixels at density 2.75: %s" % layout.ad_pixels.size)
	check(frame.encloses(ad), "rounded native banner bounds must remain inside the transformed safe frame")
	check((screen_button.position.x - ad.end.x) / density >= 24.0, "rounded native banner bounds must preserve 24 dp clearance")
	check((frame.end.y - ad.end.y) / density >= 8.0, "rounded native banner bounds must preserve 8 dp bottom padding")


func test_narrow_safe_frame_omits_banner_and_suppresses_an_unfittable_shortcut() -> void:
	if not ResourceLoader.exists(CHROME_PATH):
		check(false, "the shared monetization chrome layout must exist")
		return
	var chrome: Variant = load(CHROME_PATH)
	var narrow_viewport := Rect2(0, 0, 340, 180)
	var narrow_safe := Rect2(20, 10, 300, 160)
	var narrow: Dictionary = chrome.layout(narrow_viewport, narrow_safe, Transform2D.IDENTITY, 1.0, Vector2(160, 48))
	check(not narrow.show_ad, "an ad that cannot fit beside the shortcut must be omitted")
	check(narrow.footer_height > 0.0 and narrow_safe.encloses(narrow.button_rect), "a fitting shortcut may remain without a banner")

	var tiny: Dictionary = chrome.layout(Rect2(0, 0, 100, 100), Rect2(), Transform2D.IDENTITY, 1.0, Vector2(160, 48))
	check(not tiny.show_ad and tiny.footer_height == 0.0, "an impossible touch target must suppress all footer chrome")
	check(tiny.button_rect.size == Vector2.ZERO, "the impossible shortcut must not be clipped into a misleading touch target")


func test_surface_precedence_clears_freed_owners_and_ignores_late_ad_callbacks() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	platform.store_state.emit(30, true, PRICE, "")
	platform.purchase_state.emit(31, "not_owned", "", "")
	var home := Control.new()
	world.add_child(home)
	money.set_surface(home, true)
	platform.emit_ad_state(true, false, false, "")
	await frames(2)
	check(money.footer_height > 0.0, "an eligible surface must own the footer")

	var modal := Control.new()
	world.add_child(modal)
	money.set_surface(modal, false)
	money.set_surface(home, true)
	check(money.footer_height == 0.0, "updating an older eligible surface must not outrank the newest suppressing modal")
	modal.free()
	await frames(2)
	check(money.footer_height > 0.0, "leaving the tree must remove the modal and restore the previous eligible surface")

	home.free()
	await frames(2)
	platform.emit_ad_state(true, false, false, "late ad callback")
	await frames(2)
	check(money.footer_height == 0.0 and _button(tree.root, "Remove ads") == null, "a late ad callback must not revive chrome after its owner is freed")


func test_home_community_settings_purchase_gameplay_and_pause_surfaces() -> void:
	_leave_scene()
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	platform.store_state.emit(40, true, PRICE, "")
	platform.purchase_state.emit(41, "not_owned", "", "")
	platform.emit_ad_state(true, false, false, "")
	Community.use_defaults()
	Community.platform = FakePlatform.new()
	Community.transport = transport
	transport.answer("GET", "/nonce", 200, {"nonce": "n1"})
	transport.answer("POST", "/session", 200, {"token": "tok1", "player": {"id": "p_1", "name": "Pilot"}})
	transport.answer("GET", "/levels", 200, [])

	var home := MAIN.menu(MAIN.Page.HOME)
	tree.root.add_child(home)
	tree.current_scene = home
	await frames(2)
	check(money.footer_height > 0.0, "Home must be an eligible surface")
	var community_button := _button(home, "Community levels")
	check(community_button != null, "the test device must offer the existing Community entry")	
	if community_button == null:
		_leave_scene()
		return
	community_button.pressed.emit()
	for i in 10:
		if tree.current_scene is CommunityScreen:
			break
		await frames(1)
	var community: Node = tree.current_scene
	check(community is CommunityScreen, "Home must open Community through its existing sign-in flow")
	if not community is CommunityScreen:
		_leave_scene()
		return
	await frames(2)
	check(money.footer_height > 0.0, "Community must be an eligible surface")
	var community_settings_button := _button(community, "Settings")
	if community_settings_button != null:
		community_settings_button.pressed.emit()
	await frames(2)
	var community_settings := _top_overlay(community)
	check(community_settings != null and money.footer_height == 0.0, "the Community account sheet must suppress the footer")	
	if community_settings != null:
		community_settings.close()
	await frames(2)
	check(money.footer_height > 0.0, "closing the Community sheet must restore its eligible owner")
	var back := _button(community, "Back")
	if back != null:
		back.pressed.emit()
	for i in 10:
		if tree.current_scene is Control and not tree.current_scene is CommunityScreen:
			break
		await frames(1)
	home = tree.current_scene as Control
	check(home != null, "Community Back must return to Home")
	if home == null:
		_leave_scene()
		return
	var home_settings_button := _button(home, "Settings")
	check(home_settings_button != null, "Home must keep its Settings entry")
	if home_settings_button == null:
		_leave_scene()
		return
	home_settings_button.pressed.emit()
	await frames(2)
	var settings := _top_overlay(home)
	check(settings != null and money.footer_height > 0.0, "the approved Settings sheet must keep the footer available")
	if settings == null:
		_leave_scene()
		return
	var developer_button := _button(settings, "Developer options")
	if developer_button != null:
		developer_button.pressed.emit()
	await frames(2)
	var developer := _top_overlay(home)
	check(developer != null and developer != settings and money.footer_height == 0.0, "a nested developer sheet must suppress monetization")
	if developer == null or developer == settings:
		_leave_scene()
		return
	var purchase := _purchase_screen(developer)
	if purchase != null:
		await frames(2)
		check(money.footer_height == 0.0 and _button(purchase, "Close") != null, "a nested purchase sheet must suppress ads and retain an explicit Close control")
		purchase.close()
	await frames(2)
	check(money.footer_height == 0.0, "closing the purchase sheet must not reveal through the developer modal")
	developer.close()
	await frames(2)
	check(money.footer_height > 0.0, "closing the developer sheet must restore Settings")
	settings.close()
	await frames(2)
	check(money.footer_height > 0.0, "closing Settings must restore Home")

	var official := _button(home, "Official levels")
	check(official != null, "Home must retain its official list entry")
	if official == null:
		_leave_scene()
		return
	official.pressed.emit()
	await frames(2)
	var list := tree.current_scene as Control
	check(list != null and money.footer_height == 0.0, "the official list root must suppress the footer")
	if list == null:
		_leave_scene()
		return
	var official_levels: Array = Progress.levels()
	var scrolls := list.find_children("*", "ScrollContainer", true, false)
	check(not official_levels.is_empty() and scrolls.size() == 1, "the official menu must contain its stage list")
	if official_levels.is_empty() or scrolls.size() != 1:
		_leave_scene()
		return
	var stage_list := scrolls[0].get_child(0) as VBoxContainer
	check(stage_list.get_child_count() == official_levels.size(), "the menu rows must match the official level list")
	if stage_list.get_child_count() != official_levels.size() or stage_list.get_child_count() == 0:
		_leave_scene()
		return
	var first_level: Button = stage_list.get_child(0)
	check(first_level.is_visible_in_tree() and not first_level.disabled, "the first official stage row must be playable")
	if not first_level.is_visible_in_tree() or first_level.disabled:
		_leave_scene()
		return
	first_level.pressed.emit()
	await frames(3)
	var level := tree.current_scene as Level
	check(level != null and money.footer_height == 0.0, "gameplay must suppress the Home footer")	
	if level == null:
		_leave_scene()
		return
	level.hud.toggle_pause()
	var pause_settings_button := _button(level.hud._pause, "Settings")
	check(pause_settings_button != null, "the pause card must retain Settings")
	if pause_settings_button != null:
		pause_settings_button.pressed.emit()
	await frames(2)
	var pause_settings := _top_overlay(level.hud._pause)
	check(pause_settings != null and money.footer_height > 0.0, "Settings opened from pause must allow the footer")
	if pause_settings != null:
		pause_settings.close()
	await frames(2)
	check(money.footer_height == 0.0, "closing pause Settings must immediately restore gameplay suppression")	
	_leave_scene()


func test_result_footer_is_reserved_before_ad_load_and_paid_completion_keeps_game_controls() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	platform.store_state.emit(50, true, PRICE, "")
	platform.purchase_state.emit(51, "not_owned", "", "")
	var root := Node2D.new()
	root.set_script(load("res://scenes/level.gd"))
	var ship: Node = load("res://scenes/ship.tscn").instantiate()
	var goal: Node2D = load("res://scenes/goal.tscn").instantiate()
	goal.position = Vector2(3000, 0)
	root.add_child(ship)
	root.add_child(goal)
	world.add_child(root)
	var level := root as Level
	await frames(2)
	level.hud.show_result(true, {"name": "Test stage", "points": 20, "fuel_points": 10, "hull_points": 10, "time_points": 0, "new_best": false, "has_next": true, "has_par": false})
	await frames(2)
	var next := _button(level.hud, "Next")
	var retry := _button(level.hud, "Retry")
	check(next != null and retry != null, "the result card must retain its Next and Retry controls")
	check(money.footer_height > 0.0 and not money.ad_loaded, "an eligible result must reserve a fixed footer before its banner arrives")
	if next == null or retry == null:
		return
	var next_before := next.get_global_rect()
	var retry_before := retry.get_global_rect()
	platform.emit_ad_state(true, false, false, "")
	await frames(2)
	check(next.get_global_rect().is_equal_approx(next_before) and retry.get_global_rect().is_equal_approx(retry_before), "ad arrival must not move Next or Retry")

	var remove_ads := _button(tree.root, "Remove ads")
	check(remove_ads != null, "the eligible result must expose the purchase shortcut")	
	if remove_ads != null:
		remove_ads.grab_focus(true)
	transport.answer("POST", PURCHASE_ROUTE, 200, {"ad_free": true})
	platform.purchase_state.emit(52, "purchased", "result-card-token", "")
	await frames(3)
	check(money.ad_free and money.footer_height == 0.0, "verified paid completion must reclaim the result footer")
	var focus := tree.root.gui_get_focus_owner()
	check(focus is Button and focus.is_visible_in_tree() and ["Next", "Retry"].has(focus.text), "paid completion must focus a remaining visible result control, not the hidden shortcut: %s" % focus)
	check(_button(tree.root, "Remove ads") == null, "paid completion must hide the purchase shortcut")


func test_required_privacy_choices_remain_explicit_when_ads_are_disallowed() -> void:
	var host := Control.new()
	world.add_child(host)
	for cached_ad_free: bool in [false, true]:
		var setup := _boot(cached_ad_free)
		if setup.is_empty():
			return
		var money: Variant = setup.money
		var platform: Variant = setup.platform
		var settings := SettingsScreen.open(host)
		await frames(2)
		check(_button(settings, "Privacy choices") == null, "Privacy choices must stay out of Settings unless the native bridge requires them")
		settings.close()
		await frames(2)
		platform.emit_ad_state(false, true, false, "Consent information could not be refreshed.")
		await frames(2)
		check(money.privacy_required and not money.consent_open, "a required choice must not be opened automatically")
		settings = SettingsScreen.open(host)
		await frames(2)
		var privacy := _button(settings, "Privacy choices")
		check(privacy != null, "required privacy choices must remain accessible for unknown and paid ownership")
		if privacy != null:
			privacy.pressed.emit()
		check(platform.privacy_options_opened == 1, "Privacy choices must be an explicit user action")
		check(not money.ad_loaded and not money.consent_open, "unavailable consent must leave Settings usable without an automatic prompt")
		settings.close()
		await frames(2)


func test_consent_dialog_suppresses_chrome_and_restores_focus_after_close() -> void:
	_leave_scene()
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	platform.store_state.emit(70, true, PRICE, "")
	platform.purchase_state.emit(71, "not_owned", "", "")
	platform.emit_ad_state(true, false, false, "")
	var home: Control = MAIN.menu(MAIN.Page.HOME)
	tree.root.add_child(home)
	tree.current_scene = home
	money.set_surface(home, true)
	await frames(2)

	var shortcut := _button(tree.root, "Remove ads")
	check(shortcut != null, "an eligible unpaid Home surface must expose its purchase shortcut")
	if shortcut == null:
		_leave_scene()
		return
	shortcut.grab_focus()
	check(tree.root.gui_get_focus_owner() == shortcut, "the shortcut must own focus before the consent dialog opens")

	platform.emit_ad_state(false, false, true, "")
	await frames(2)
	check(money.consent_open and money.footer_height == 0.0, "an open consent dialog must suppress the Godot footer")
	check(_button(tree.root, "Remove ads") == null, "an open consent dialog must hide the purchase shortcut")
	check(not platform.advertising_allowed and not money.ad_loaded, "an open consent dialog must suppress advertising")
	var focus_during_consent: Control = tree.root.gui_get_focus_owner() as Control
	check(focus_during_consent != null and focus_during_consent.is_visible_in_tree() and focus_during_consent != shortcut, "focus must leave the hidden shortcut while consent is open")

	platform.emit_ad_state(true, false, false, "")
	await frames(2)
	check(not money.consent_open and money.footer_height > 0.0, "closing consent must restore eligible Home chrome")
	check(_button(tree.root, "Remove ads") == shortcut, "closing consent must restore the purchase shortcut")
	check(tree.root.gui_get_focus_owner() == shortcut, "closing consent must restore the prior focus")
	_leave_scene()


func test_editor_root_suppresses_monetization() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	platform.store_state.emit(60, true, PRICE, "")
	platform.purchase_state.emit(61, "not_owned", "", "")
	platform.emit_ad_state(true, false, false, "")
	var id := MyLevels.new_id()
	MyLevels.save(id, LevelDoc.blank())
	var editor := LevelEditor.create(id)
	world.add_child(editor)
	await frames(2)
	check(money.footer_height == 0.0 and _button(tree.root, "Remove ads") == null, "the editor root must suppress ads and purchase chrome")
	editor.free()
	MyLevels.delete(id)


func test_payment_and_privacy_controls_keep_48dp_touch_height() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	platform.density = 3.0
	var previous_window_size: Vector2i = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	await frames(2)
	var display_scale := tree.root.get_viewport().get_screen_transform().y.length()
	check(is_equal_approx(display_scale, 1.5), "48 dp UI fixture must use an actual 1.5 screen scale")
	platform.store_state.emit(110, true, PRICE, "")
	platform.purchase_state.emit(111, "not_owned", "", "")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.add_child(host)
	var purchase := _purchase_screen(host)
	if purchase == null:
		tree.root.size = previous_window_size
		return
	await frames(2)
	for text: String in ["Terms of Service", "Privacy Policy", "Buy", "Restore purchases", "Close"]:
		var button := _button(purchase, text)
		check(button != null, "purchase screen must show %s" % text)
		if button != null:
			check(_touch_height_dp(button, platform.density) >= 48.0, "%s must remain at least 48 dp high" % text)
	tree.root.size = Vector2i(1280, 720)
	await frames(2)
	for text: String in ["Terms of Service", "Privacy Policy", "Buy", "Restore purchases", "Close"]:
		var button := _button(purchase, text)
		if button != null:
			check(_touch_height_dp(button, platform.density) >= 48.0, "%s must stay 48 dp after screen resize" % text)
	purchase.close()
	await frames(2)

	platform.emit_ad_state(false, true, false, "")
	await frames(1)
	tree.root.size = Vector2i(1920, 1080)
	await frames(2)
	var settings := SettingsScreen.open(host)
	await frames(2)
	for text: String in ["Restore purchases", "Privacy choices", "Close"]:
		var button := _button(settings, text)
		check(button != null, "Settings must show %s in this state" % text)
		if button != null:
			check(_touch_height_dp(button, platform.density) >= 48.0, "Settings %s must remain at least 48 dp high" % text)
	tree.root.size = Vector2i(1280, 720)
	await frames(2)
	for text: String in ["Restore purchases", "Privacy choices", "Close"]:
		var button := _button(settings, text)
		if button != null:
			check(_touch_height_dp(button, platform.density) >= 48.0, "Settings %s must stay 48 dp after screen resize" % text)
	settings.close()
	await frames(2)
	tree.root.size = previous_window_size
	await frames(2)


func test_shortcut_purchase_close_restores_focus_before_and_after_payment() -> void:
	_leave_scene()
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	platform.store_state.emit(120, true, PRICE, "")
	platform.purchase_state.emit(121, "not_owned", "", "")
	platform.emit_ad_state(true, false, false, "")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var continue_button := Button.new()
	continue_button.text = "Continue"
	host.add_child(continue_button)
	world.add_child(host)
	money.set_surface(host, true)
	await frames(2)
	var shortcut := _button(tree.root, "Remove ads")
	check(shortcut != null, "eligible surface must expose Remove ads")
	if shortcut == null:
		return
	shortcut.grab_focus(true)
	shortcut.pressed.emit()
	await frames(2)
	var purchase := _top_overlay(host)
	check(purchase != null, "the real shortcut must open the purchase sheet")
	if purchase == null:
		return
	var close := _button(purchase, "Close")
	if close != null:
		close.pressed.emit()
	await frames(2)
	check(shortcut.is_visible_in_tree() and tree.root.gui_get_focus_owner() == shortcut, "closing an unpaid purchase sheet must restore focus to the eligible shortcut")

	shortcut.grab_focus(true)
	shortcut.pressed.emit()
	await frames(2)
	purchase = _top_overlay(host)
	if purchase == null:
		check(false, "the shortcut must reopen the purchase sheet")
		return
	transport.answer("POST", PURCHASE_ROUTE, 200, {"ad_free": true})
	var buy := _button(purchase, "Buy")
	check(buy != null and not buy.disabled, "Buy must remain an explicit available action")
	if buy != null:
		buy.pressed.emit()
	platform.purchase_state.emit(122, "purchased", "focus-test-token", "")
	await frames(3)
	check(money.ad_free and _button(tree.root, "Remove ads") == null, "verified payment must hide the shortcut")
	close = _button(purchase, "Close")
	if close != null:
		close.pressed.emit()
	await frames(2)
	var focus := tree.root.gui_get_focus_owner()
	check(focus == continue_button and focus.is_visible_in_tree() and not continue_button.disabled, "after payment, focus must return to a visible underlying control instead of the hidden shortcut")


func test_touch_target_minimum_uses_density_separate_from_screen_scale() -> void:
	if not ResourceLoader.exists(CHROME_PATH):
		check(false, "the shared monetization chrome layout must exist")
		return
	var chrome: Variant = load(CHROME_PATH)
	var viewport := Rect2(0, 0, 1280, 720)
	var transform := Transform2D(Vector2(1.5, 0), Vector2(0, 1.5), Vector2(11, 7))
	var layout: Dictionary = chrome.layout(viewport, Rect2(), transform, 3.0, Vector2(160, 48))
	var screen_button: Rect2 = transform * layout.button_rect
	check(layout.button_rect.size.y >= 96.0, "a 48 dp target at density 3 and scale 1.5 needs 96 viewport pixels")
	check(is_equal_approx(screen_button.size.y / 3.0, 48.0), "the transformed shortcut must remain 48 dp high at independent density and scale")




func test_android_back_closes_purchase_sheet_before_list_navigation() -> void:
	_leave_scene()
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	platform.store_state.emit(130, true, PRICE, "")
	var main: Control = MAIN.menu(MAIN.Page.OFFICIAL)
	tree.root.add_child(main)
	tree.current_scene = main
	await frames(2)
	var back: Button = _button(main, "Back")
	check(back != null, "the safe Back test page must have its underlying list control")
	if back == null:
		_leave_scene()
		money.use_defaults()
		return
	back.grab_focus(true)
	var purchase: Overlay = _purchase_screen(main)
	check(purchase != null, "the actual Remove ads sheet must open on the main scene")
	if purchase == null:
		_leave_scene()
		money.use_defaults()
		return
	await frames(2)

	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	var stayed_on_page := is_instance_valid(main) and tree.current_scene == main
	check(stayed_on_page, "Back over a purchase sheet must not replace its underlying page")
	if stayed_on_page:
		check(_top_overlay(main) == null, "Android Back must close the top purchase sheet")
		check(tree.root.gui_get_focus_owner() == back, "closing by Android Back must restore focus to the prior control")
	_leave_scene()
	money.use_defaults()
