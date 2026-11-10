extends "res://tests/test_case.gd"
## Ownership is granted only by the current native purchase and its Worker verification.

const FAKE_PLATFORM := preload("res://tests/support/fake_monetization_platform.gd")
const PURCHASE_ROUTE := "/purchases/ad-free"
const TOKEN := "test-play-purchase-token"
const PRICE := "R$ 10,00"


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


func _header(request: Dictionary, name: String) -> String:
	for header: String in request.headers:
		if header.to_lower().begins_with(name.to_lower() + ": "):
			return header.trim_prefix(header.get_slice(":", 0) + ": ")
	return ""


func _purchase_requests(transport: FakeTransport) -> Array:
	return transport.requests.filter(func(request: Dictionary) -> bool:
		return request.method == "POST" and String(request.url).get_slice("?", 0).ends_with(PURCHASE_ROUTE)
	)


func _visible_button(node: Node, text: String) -> Button:
	var buttons := node.find_children("*", "Button", true, false).filter(func(button: Button) -> bool:
		return button.text == text and button.is_visible_in_tree()
	)
	return buttons[0] if not buttons.is_empty() else null

func test_purchase_is_granted_only_after_verified_acknowledged_success() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	var surface := Control.new()
	world.add_child(surface)
	var next := Button.new()
	next.text = "Next"
	surface.add_child(next)
	money.set_surface(surface, true)
	platform.store_state.emit(90, true, PRICE, "")
	platform.purchase_state.emit(100, "not_owned", "", "")
	platform.emit_ad_state(true, false, false, "")
	await frames(2)
	check(money.ad_loaded, "the eligible unpaid surface must show its loaded banner")
	check(money.footer_height > 0.0, "the eligible surface must reserve its footer before purchase")
	check(_visible_button(tree.root, "Remove ads") != null, "an eligible unpaid surface must expose the purchase shortcut")

	transport.hold("POST", PURCHASE_ROUTE)
	transport.answer("POST", PURCHASE_ROUTE, 200, {"ad_free": true})
	platform.purchase_state.emit(101, "purchased", TOKEN, "")
	await frames(2)
	check(not money.ad_free, "a Play purchase is not an entitlement while Worker verification is held")
	var requests := _purchase_requests(transport)
	check(requests.size() == 1, "the purchase token must be verified once without Community sign-in: %s" % [transport.requests])
	if requests.size() == 1:
		var request: Dictionary = requests[0]
		check(JSON.parse_string(request.body.get_string_from_utf8()) == {"purchaseToken": TOKEN}, "verification must post only the purchase token: %s" % request.body.get_string_from_utf8())
		check(_header(request, "Authorization") == "", "purchase verification must not use Community authentication")
		check(request.url.get_slice("?", 0).ends_with(PURCHASE_ROUTE), "verification must use the permanent-purchase route: %s" % request.url)
	check(not Community.signed_in(), "verified ownership must not depend on a Community account")

	transport.release_hold("POST", PURCHASE_ROUTE)
	await frames(3)
	check(money.ad_free, "an acknowledged Worker success must grant ad-free ownership")
	check(platform.cached_ad_free, "verified ownership must be persisted through the native bridge")
	check(not platform.advertising_allowed and not money.ad_loaded, "a verified purchase must disable and hide advertising")
	check(money.footer_height == 0.0, "paid ownership must reclaim the reserved footer")
	check(_visible_button(tree.root, "Remove ads") == null, "paid ownership must hide the purchase shortcut")
	check(_purchase_requests(transport).size() == 1, "verification must not retry or submit a second purchase")


func test_old_purchase_queries_and_verification_responses_cannot_reverse_newer_state() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	transport.hold("POST", PURCHASE_ROUTE)
	transport.answer("POST", PURCHASE_ROUTE, 200, {"ad_free": true})
	platform.purchase_state.emit(50, "purchased", "older-token", "")
	await frames(2)
	check(_purchase_requests(transport).size() == 1, "the older token verification must be in flight")
	platform.purchase_state.emit(51, "not_owned", "", "")
	check(not money.ad_free, "a newer authoritative no-ownership query must clear the cached entitlement")
	transport.release_hold("POST", PURCHASE_ROUTE)
	await frames(3)
	check(not money.ad_free, "an older held success must not restore ownership after newer revocation")
	var request_count := _purchase_requests(transport).size()
	platform.purchase_state.emit(49, "purchased", "stale-query-token", "")
	await frames(2)
	check(_purchase_requests(transport).size() == request_count, "an older native purchase query must not start verification")

	platform.store_state.emit(75, true, PRICE, "")
	platform.store_state.emit(74, false, "", "older product query")
	check(money.store_ready and money.price == PRICE, "an older store query must not replace the current Play price")

	transport.hold("POST", PURCHASE_ROUTE)
	transport.answer("POST", PURCHASE_ROUTE, 200, {"ad_free": true})
	platform.purchase_state.emit(52, "purchased", "reset-token", "")
	await frames(2)
	money.use_defaults()
	var current_platform: Variant = FAKE_PLATFORM.new()
	var current_transport := FakeTransport.new()
	world.add_child(current_transport)
	money.platform = current_platform
	money.transport = current_transport
	money.start()
	transport.release_hold("POST", PURCHASE_ROUTE)
	await frames(3)
	check(not money.ad_free and not current_platform.cached_ad_free, "a held verification from before reset must not revive ownership")
	check(not current_platform.advertising_allowed, "a stale success must not revive advertising after reset")


func test_refresh_start_invalidates_held_paid_verification_and_preserves_state() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	transport.hold("POST", PURCHASE_ROUTE)
	transport.answer("POST", PURCHASE_ROUTE, 409, {"error": "Inactive.", "code": "purchase_inactive"})
	platform.purchase_state.emit(50, "purchased", "held-inactive-token", "")
	await frames(2)
	check(_purchase_requests(transport).size() == 1, "the paid token verification must be held in flight")

	var newer_query: int = platform.begin_purchase_refresh()
	check(platform.native_purchase_generation == newer_query, "the newer native query must be pending while A remains held")
	transport.release_hold("POST", PURCHASE_ROUTE)
	await frames(3)
	check(money.ad_free and platform.cached_ad_free, "A's inactive response must not revoke paid ownership after B starts")
	platform.purchase_state.emit(newer_query, "error", "", "Play query failed.")
	await frames(2)
	check(money.ad_free and platform.cached_ad_free, "B's query error must preserve the cached paid entitlement")


func test_native_refresh_generation_rejects_verification_before_start_signal_arrives() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	transport.hold("POST", PURCHASE_ROUTE)
	transport.answer("POST", PURCHASE_ROUTE, 409, {"error": "Inactive.", "code": "purchase_inactive"})
	platform.purchase_state.emit(60, "purchased", "race-inactive-token", "")
	await frames(2)
	check(_purchase_requests(transport).size() == 1, "the older token verification must be held in flight")

	var newer_query: int = platform.begin_purchase_refresh(false)
	transport.release_hold("POST", PURCHASE_ROUTE)
	await frames(3)
	check(money.ad_free and platform.cached_ad_free, "the native generation must reject A's write before Godot receives B's start signal")
	platform.announce_purchase_refresh_started(newer_query)
	platform.purchase_state.emit(newer_query, "error", "", "Play query failed.")
	await frames(2)
	check(money.ad_free and platform.cached_ad_free, "B's later start and error must leave cached paid ownership intact")


func test_refresh_start_accepts_its_same_generation_ownership_result() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var current_query: int = platform.begin_purchase_refresh()
	platform.purchase_state.emit(current_query, "not_owned", "", "")
	await frames(2)
	check(not money.ad_free and not platform.cached_ad_free, "B's current same-generation not-owned result must revoke cached ownership")


func test_offline_or_503_preserves_verified_ownership_but_authoritative_revocation_clears_it() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	transport.answer("POST", PURCHASE_ROUTE, 0, "")
	platform.purchase_state.emit(60, "purchased", "offline-token", "")
	await frames(2)
	check(money.ad_free, "an offline verification must preserve cached verified ownership")
	transport.answer("POST", PURCHASE_ROUTE, 503, {"error": "Purchase verification is temporarily unavailable."})
	platform.purchase_state.emit(61, "purchased", "unavailable-token", "")
	await frames(2)
	check(money.ad_free, "a Worker outage must preserve cached verified ownership")

	transport.answer("POST", PURCHASE_ROUTE, 409, {"error": "The purchase is no longer active.", "code": "purchase_inactive"})
	platform.purchase_state.emit(62, "purchased", "current-token", "")
	await frames(2)
	check(not money.ad_free, "the current token's authoritative inactive response must revoke ownership")

	setup = _boot(true)
	if setup.is_empty():
		return
	money = setup.money
	platform = setup.platform
	platform.purchase_state.emit(70, "not_owned", "", "")
	check(not money.ad_free, "a successful current owned-purchases query with no item must revoke cached ownership")


func test_generic_404_or_conflict_is_not_purchase_revocation() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	transport.answer("POST", PURCHASE_ROUTE, 404, {"error": "Route not found"})
	platform.purchase_state.emit(80, "purchased", "generic-404-token", "")
	await frames(2)
	check(money.ad_free, "a generic 404 must not revoke cached verified ownership")
	transport.answer("POST", PURCHASE_ROUTE, 409, {"error": "Conflict"})
	platform.purchase_state.emit(81, "purchased", "generic-conflict-token", "")
	await frames(2)
	check(money.ad_free, "a generic conflict without a purchase rejection code must not revoke ownership")

	transport.answer("POST", PURCHASE_ROUTE, 404, {"error": "The purchase token is invalid.", "code": "purchase_invalid"})
	platform.purchase_state.emit(82, "purchased", "current-invalid-token", "")
	await frames(2)
	check(not money.ad_free, "only the explicit current-token purchase_invalid code may revoke ownership")


func test_unknown_or_paid_ownership_does_not_initialize_advertising() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var home: Control = load("res://scenes/main.tscn").instantiate()
	world.add_child(home)
	money.set_surface(home, true)
	await frames(2)
	var official_buttons: Array = home.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Official levels")
	check(not official_buttons.is_empty(), "Home must retain an ordinary gameplay control when consent is unavailable")
	if official_buttons.is_empty():
		return
	var official: Button = official_buttons[0]
	check(not money.ad_free and not platform.advertising_allowed and not money.ad_loaded, "unknown ownership must suppress advertising on an otherwise eligible Home surface")
	platform.emit_ad_state(false, true, false, "Consent information could not be refreshed.")
	await frames(2)
	check(not money.consent_open and not platform.advertising_allowed and not money.ad_loaded, "unavailable or refused consent must not open an automatic prompt or initialize ads")
	check(not official.disabled and official.is_visible_in_tree(), "unavailable consent must leave ordinary gameplay accessible")

	setup = _boot(true)
	if setup.is_empty():
		return
	money = setup.money
	platform = setup.platform
	money.set_surface(home, true)
	platform.emit_ad_state(false, true, false, "Consent is required.")
	await frames(2)
	check(money.ad_free and not platform.advertising_allowed and not money.ad_loaded, "cached paid ownership must never initialize advertising")
	check(not money.consent_open and not official.disabled, "paid ownership and required consent must not block gameplay")


func test_community_deletion_and_reset_leave_ad_free_ownership_untouched() -> void:
	var setup := _boot(true)
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	Community.use_defaults()
	Community.platform = FakePlatform.new()
	Community.transport = transport
	var session := ConfigFile.new()
	session.set_value("session", "token", "community-session")
	session.set_value("session", "expires", int(Time.get_unix_time_from_system()) + 3600)
	session.set_value("player", "id", "p_1")
	session.save(Community.session_path)
	transport.answer("DELETE", "/me", 200, "")
	var error: String = await Community.delete_account()
	check(error == "", "the isolated Community account must be deleted successfully: %s" % error)
	check(not Community.signed_in(), "Community deletion must clear only its own account")
	check(money.ad_free and platform.cached_ad_free, "Community account deletion must preserve independently verified ad-free ownership")
	Community.use_defaults()
	check(money.ad_free and platform.cached_ad_free, "Community reset must not mutate the purchase")


func test_malformed_or_pending_worker_responses_never_grant_ad_free() -> void:
	var setup := _boot()
	if setup.is_empty():
		return
	var money: Variant = setup.money
	var platform: Variant = setup.platform
	var transport: FakeTransport = setup.transport
	transport.answer("POST", PURCHASE_ROUTE, 200, {"ad_free": "true"})
	platform.purchase_state.emit(90, "purchased", "malformed-success-token", "")
	await frames(2)
	check(not money.ad_free and not platform.cached_ad_free, "a malformed 200 response must not create verified ownership")

	transport.answer("POST", PURCHASE_ROUTE, 202, {"pending": true})
	platform.purchase_state.emit(91, "purchased", "worker-pending-token", "")
	await frames(2)
	check(not money.ad_free and not platform.cached_ad_free, "a Worker pending response must not create verified ownership")
