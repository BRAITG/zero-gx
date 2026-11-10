extends Node
## Android purchase ownership and consent-gated banner access; Community identity is not involved.

signal changed

const NATIVE_SINGLETON := "ZeroGxMonetization"
const PURCHASE_PATH := "/purchases/ad-free"
const DEFAULT_API_URL := "https://zerogx.braitg.dev"
const MonetizationChromeScript := preload("res://scenes/monetization_chrome.gd")

var platform: Object
var transport: CommunityTransport

var _http: CommunityTransport
var _connected_platform: Object
var _store_callback: Callable
var _purchase_callback: Callable
var _ad_callback: Callable
var _callback_epoch := 0
var _started := false
var _last_store_generation := -1
var _last_purchase_generation := -1
var _verification_generation := 0
var _verification_token := ""
var _store_ready := false
var _price := ""
var _message := ""
var _ad_free := false
var _ownership_known := false
var _purchase_unverified := false
var _privacy_required := false
var _consent_open := false
var _ad_loaded := false
var _footer_height := 0.0
var _surfaces: Dictionary = {}
var _surface_order := 0
var _last_advertising_allowed := false
var _advertising_allowed_known := false
var _last_banner_bounds := Rect2i()
var _banner_bounds_known := false
var _chrome: MonetizationChrome

var ad_free: bool:
	get:
		return _ad_free
var store_ready: bool:
	get:
		return _store_ready
var price: String:
	get:
		return _price
var message: String:
	get:
		return _message
var privacy_required: bool:
	get:
		return _privacy_required
var consent_open: bool:
	get:
		return _consent_open
var ad_loaded: bool:
	get:
		return _ad_loaded
var footer_height: float:
	get:
		return _footer_height


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = CommunityTransport.new()
	_http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_http)
	_chrome = MonetizationChromeScript.new()
	add_child(_chrome)
	get_viewport().size_changed.connect(_refresh)
	use_defaults()
	start()


## Returns true only when the enabled Android export installed the native component.
func available() -> bool:
	return platform != null and is_instance_valid(platform)


func start() -> void:
	if _started or not available():
		return
	_connect_platform()
	_ad_free = bool(platform.call("getCachedAdFree")) if platform.has_method("getCachedAdFree") else false
	_ownership_known = _ad_free
	_store_ready = false
	_price = ""
	_purchase_unverified = false
	_started = true
	_refresh()
	if platform.has_method("start"):
		platform.call("start")


func buy() -> void:
	if not _started or not available() or not _store_ready or _ad_free:
		return
	if platform.has_method("buy"):
		platform.call("buy")


func restore() -> void:
	if not _started or not available() or not platform.has_method("refreshPurchases"):
		return
	_verification_generation += 1
	_verification_token = ""
	_purchase_unverified = false
	if not _ad_free:
		_ownership_known = false
	_message = ""
	_refresh()
	changed.emit()
	platform.call("refreshPurchases")


func show_privacy_options() -> void:
	if _started and available() and platform.has_method("showPrivacyOptions"):
		platform.call("showPrivacyOptions")


## Tests and lifecycle resets restore the actual bridge and plain HTTP transport.
func use_defaults() -> void:
	_disconnect_platform()
	if _started and available():
		if platform.has_method("setAdvertisingAllowed"):
			platform.call("setAdvertisingAllowed", false)
		if platform.has_method("setBannerBounds"):
			platform.call("setBannerBounds", 0, 0, 0, 0)
	_verification_generation += 1
	_verification_token = ""
	_started = false
	_last_store_generation = -1
	_last_purchase_generation = -1
	_store_ready = false
	_price = ""
	_message = ""
	_ad_free = false
	_ownership_known = false
	_purchase_unverified = false
	_privacy_required = false
	_consent_open = false
	_ad_loaded = false
	_footer_height = 0.0
	for id: int in _surfaces.keys():
		var entry: Dictionary = _surfaces[id]
		var reference: WeakRef = entry.owner
		var owner: Variant = reference.get_ref()
		var exited: Callable = entry.exited
		if owner != null and is_instance_valid(owner) and owner.tree_exited.is_connected(exited):
			owner.tree_exited.disconnect(exited)
	_surfaces.clear()
	_surface_order = 0
	_active_surface_eligible = false
	_advertising_allowed_known = false
	_banner_bounds_known = false
	transport = _http
	platform = _native_platform()
	_refresh()
	changed.emit()


func set_surface(owner: Node, eligible: bool) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var id := owner.get_instance_id()
	var entry: Dictionary = _surfaces.get(id, {})
	if entry.is_empty():
		_surface_order += 1
		var exited := Callable(self, "_surface_exited").bind(id)
		owner.tree_exited.connect(exited, CONNECT_ONE_SHOT)
		entry = {"owner": weakref(owner), "eligible": eligible, "order": _surface_order, "exited": exited}
	else:
		entry.eligible = eligible
	_surfaces[id] = entry
	_refresh()


func clear_surface(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var id := owner.get_instance_id()
	if not _surfaces.has(id):
		return
	var entry: Dictionary = _surfaces[id]
	var exited: Callable = entry.exited
	if owner.tree_exited.is_connected(exited):
		owner.tree_exited.disconnect(exited)
	_surfaces.erase(id)
	_refresh()


func _surface_exited(id: int) -> void:
	_surfaces.erase(id)
	_refresh()


func _latest_surface() -> Node:
	var selected: Dictionary = {}
	var newest := -1
	for id: int in _surfaces.keys():
		var entry: Dictionary = _surfaces[id]
		var reference: WeakRef = entry.owner
		var owner: Variant = reference.get_ref()
		if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
			_surfaces.erase(id)
			continue
		if int(entry.order) > newest:
			newest = int(entry.order)
			selected = entry
	if selected.is_empty():
		_active_surface_eligible = false
		return null
	_active_surface_eligible = bool(selected.eligible)
	var reference: WeakRef = selected.owner
	return reference.get_ref()


var _active_surface_eligible := false


func _refresh() -> void:
	var old_footer := _footer_height
	var old_ad_loaded := _ad_loaded
	var owner := _latest_surface()
	var chrome_visible := available() and owner != null and _active_surface_eligible and not _ad_free
	var layout := {"ad_pixels": Rect2i(), "button_rect": Rect2(), "footer_height": 0.0, "show_ad": false}
	if chrome_visible and _chrome != null and is_inside_tree():
		var viewport := get_viewport()
		var safe_area := Rect2()
		if OS.has_feature("mobile"):
			safe_area = viewport.get_screen_transform().affine_inverse() * Rect2(DisplayServer.get_display_safe_area())
		var density := float(platform.call("getDensity")) if platform.has_method("getDensity") else 1.0
		layout = MonetizationChromeScript.layout(
			viewport.get_visible_rect(),
			safe_area,
			viewport.get_screen_transform(),
			density,
			_chrome.button_minimum(),
		)
	_footer_height = float(layout.footer_height)
	if _chrome != null:
		_chrome.update(layout, chrome_visible, owner)
	var allowed := chrome_visible and bool(layout.show_ad) and _ownership_known and not _ad_free and not _purchase_unverified
	var bounds: Rect2i = layout.ad_pixels if allowed else Rect2i()
	_set_banner_bounds(bounds)
	_set_advertising_allowed(allowed)
	if not allowed:
		_ad_loaded = false
	if old_footer != _footer_height or old_ad_loaded != _ad_loaded:
		changed.emit()


func _set_advertising_allowed(allowed: bool) -> void:
	if not _started or not available() or not platform.has_method("setAdvertisingAllowed"):
		return
	if _advertising_allowed_known and _last_advertising_allowed == allowed:
		return
	_advertising_allowed_known = true
	_last_advertising_allowed = allowed
	platform.call("setAdvertisingAllowed", allowed)


func _set_banner_bounds(bounds: Rect2i) -> void:
	if not _started or not available() or not platform.has_method("setBannerBounds"):
		return
	if _banner_bounds_known and _last_banner_bounds == bounds:
		return
	_banner_bounds_known = true
	_last_banner_bounds = bounds
	platform.call("setBannerBounds", bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y)


func _connect_platform() -> void:
	if _connected_platform == platform:
		return
	_disconnect_platform()
	_store_callback = Callable(self, "_store_state").bind(_callback_epoch)
	_purchase_callback = Callable(self, "_purchase_state").bind(_callback_epoch)
	_ad_callback = Callable(self, "_ad_state").bind(_callback_epoch)
	for signal_name in ["store_state", "purchase_state", "ad_state"]:
		if platform.has_signal(signal_name):
			var callback: Callable = _store_callback if signal_name == "store_state" else (_purchase_callback if signal_name == "purchase_state" else _ad_callback)
			platform.connect(signal_name, callback)
	_connected_platform = platform


func _disconnect_platform() -> void:
	if _connected_platform != null and is_instance_valid(_connected_platform):
		for pair in [["store_state", _store_callback], ["purchase_state", _purchase_callback], ["ad_state", _ad_callback]]:
			if _connected_platform.has_signal(pair[0]) and _connected_platform.is_connected(pair[0], pair[1]):
				_connected_platform.disconnect(pair[0], pair[1])
	_callback_epoch += 1
	_connected_platform = null


func _native_platform() -> Object:
	if OS.has_feature("android") and Engine.has_singleton(NATIVE_SINGLETON):
		return Engine.get_singleton(NATIVE_SINGLETON)
	return null


func _store_state(generation: int, available_on_play: bool, formatted_price: String, error: String, epoch: int) -> void:
	if epoch != _callback_epoch or generation <= _last_store_generation:
		return
	_last_store_generation = generation
	_store_ready = available_on_play and formatted_price != ""
	_price = formatted_price if _store_ready else ""
	_message = "" if _store_ready else (error if error != "" else "Remove ads is unavailable on Google Play.")
	_refresh()
	changed.emit()


func _purchase_state(generation: int, status: String, token: String, error: String, epoch: int) -> void:
	if epoch != _callback_epoch or generation <= _last_purchase_generation:
		return
	_last_purchase_generation = generation
	_verification_generation += 1
	_verification_token = ""
	_purchase_unverified = false
	match status:
		"not_owned":
			_ownership_known = true
			_ad_free = false
			_message = ""
			_set_verified_ad_free(false)
		"purchased":
			if token == "":
				if not _ad_free:
					_ownership_known = false
				_purchase_unverified = true
				_message = "Google Play did not provide a purchase token."
			else:
				if not _ad_free:
					_ownership_known = false
				_purchase_unverified = true
				_verification_token = token
				_message = "Verifying purchase…"
				_verify_purchase(token, _verification_generation)
		"pending":
			if not _ad_free:
				_ownership_known = false
			_message = "Purchase pending."
		"cancelled":
			_message = "Purchase cancelled."
		"error":
			if not _ad_free:
				_ownership_known = false
			_message = error if error != "" else "Google Play could not complete the purchase."
		_:
			if not _ad_free:
				_ownership_known = false
			_message = "Google Play returned an unrecognized purchase state."
	_refresh()
	changed.emit()


func _ad_state(loaded: bool, privacy_needed: bool, consent_dialog_open: bool, error: String, epoch: int) -> void:
	if epoch != _callback_epoch:
		return
	var next_loaded := loaded and _last_advertising_allowed
	var changed_state := _ad_loaded != next_loaded or _privacy_required != privacy_needed or _consent_open != consent_dialog_open
	_ad_loaded = next_loaded
	_privacy_required = privacy_needed
	_consent_open = consent_dialog_open
	if error != "":
		_message = error
	_refresh()
	if changed_state or error != "":
		changed.emit()


func _verify_purchase(token: String, generation: int) -> void:
	var sender := transport
	if sender == null:
		_verification_token = ""
		_message = "Purchase verification is unavailable. Existing verified ownership has not changed."
		_refresh()
		changed.emit()
		return
	var url := str(ProjectSettings.get_setting("community/api_url", DEFAULT_API_URL)).trim_suffix("/") + PURCHASE_PATH
	var body := JSON.stringify({"purchaseToken": token}).to_utf8_buffer()
	var response: Dictionary = await sender.send("POST", url, PackedStringArray(["Content-Type: application/json"]), body)
	if generation != _verification_generation or token != _verification_token:
		return
	_verification_token = ""
	var status := int(response.get("status", 0))
	var data: Variant = _parse_json(response.get("body", PackedByteArray()))
	if status == 200 and data is Dictionary and data.size() == 1 and data.get("ad_free") is bool and data.ad_free:
		_ad_free = true
		_ownership_known = true
		_purchase_unverified = false
		_verification_token = ""
		_ad_loaded = false
		_message = "Purchase verified. Ads have been removed."
		_set_verified_ad_free(true)
	elif status == 202 and data is Dictionary and data.size() == 1 and data.get("pending") is bool and data.pending:
		_message = "Purchase pending. Ads will be removed after Google Play confirms it."
	elif status == 404 and data is Dictionary and data.get("code") == "purchase_invalid":
		_revoke_purchase()
		_message = "Google Play did not recognize this purchase."
	elif status == 409 and data is Dictionary and data.get("code") == "purchase_inactive":
		_revoke_purchase()
		_message = "This purchase is no longer active."
	else:
		_message = "Purchase verification is unavailable. Existing verified ownership has not changed."
	_refresh()
	changed.emit()


func _revoke_purchase() -> void:
	_ad_free = false
	_ownership_known = true
	_purchase_unverified = false
	_verification_token = ""
	_ad_loaded = false
	_set_verified_ad_free(false)


func _set_verified_ad_free(value: bool) -> void:
	if available() and platform.has_method("setVerifiedAdFree"):
		platform.call("setVerifiedAdFree", value)


func _parse_json(bytes: Variant) -> Variant:
	if not bytes is PackedByteArray:
		return null
	var json := JSON.new()
	return json.data if json.parse(bytes.get_string_from_utf8()) == OK else null
