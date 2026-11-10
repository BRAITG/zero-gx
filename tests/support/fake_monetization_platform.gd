extends RefCounted
## Controls the native Godot bridge signals and records its externally visible state.

signal store_state(generation: int, available: bool, formatted_price: String, error: String)
signal purchase_state(generation: int, state: String, purchase_token: String, error: String)
signal purchase_refresh_started(generation: int)
signal ad_state(loaded: bool, privacy_required: bool, consent_open: bool, error: String)

var cached_ad_free := false
var density := 1.0
var advertising_allowed := false
var banner_bounds := Rect2i()
var privacy_options_opened := 0
var starts := 0
var purchase_refreshes := 0
var purchases := 0
var privacy_required := false
var consent_open := false
var ad_error := ""
var native_purchase_generation := 0


func _init() -> void:
	purchase_state.connect(_record_purchase_generation)


func _record_purchase_generation(generation: int, _state: String, _token: String, _error: String) -> void:
	native_purchase_generation = maxi(native_purchase_generation, generation)

func emit_ad_state(loaded: bool, required: bool, open: bool, error: String) -> void:
	privacy_required = required
	consent_open = open
	ad_error = error
	ad_state.emit(loaded, required, open, error)


func start() -> void:
	starts += 1
	begin_purchase_refresh()


func begin_purchase_refresh(announce: bool = true) -> int:
	native_purchase_generation += 1
	if announce:
		announce_purchase_refresh_started(native_purchase_generation)
	return native_purchase_generation


func announce_purchase_refresh_started(generation: int) -> void:
	purchase_refresh_started.emit(generation)


func refreshPurchases() -> void:
	purchase_refreshes += 1
	begin_purchase_refresh()


func buy() -> void:
	purchases += 1


func showPrivacyOptions() -> void:
	privacy_options_opened += 1


func getCachedAdFree() -> bool:
	return cached_ad_free


func setVerifiedAdFree(value: bool, generation: int) -> bool:
	if generation != native_purchase_generation:
		return false
	cached_ad_free = value
	if value:
		emit_ad_state(false, privacy_required, false, ad_error)
	return true

func getDensity() -> float:
	return density


func setBannerBounds(left: int, top: int, width: int, height: int) -> void:
	banner_bounds = Rect2i(left, top, width, height)


func setAdvertisingAllowed(allowed: bool) -> void:
	advertising_allowed = allowed
	if not allowed:
		emit_ad_state(false, privacy_required, consent_open, ad_error)
