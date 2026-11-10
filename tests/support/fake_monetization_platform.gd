extends RefCounted
## Controls the native Godot bridge signals and records its externally visible state.

signal store_state(generation: int, available: bool, formatted_price: String, error: String)
signal purchase_state(generation: int, state: String, purchase_token: String, error: String)
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

func emit_ad_state(loaded: bool, required: bool, open: bool, error: String) -> void:
	privacy_required = required
	consent_open = open
	ad_error = error
	ad_state.emit(loaded, required, open, error)


func start() -> void:
	starts += 1


func refreshPurchases() -> void:
	purchase_refreshes += 1


func buy() -> void:
	purchases += 1


func showPrivacyOptions() -> void:
	privacy_options_opened += 1


func getCachedAdFree() -> bool:
	return cached_ad_free


func setVerifiedAdFree(value: bool) -> void:
	cached_ad_free = value
	if value:
		emit_ad_state(false, privacy_required, false, ad_error)

func getDensity() -> float:
	return density


func setBannerBounds(left: int, top: int, width: int, height: int) -> void:
	banner_bounds = Rect2i(left, top, width, height)


func setAdvertisingAllowed(allowed: bool) -> void:
	advertising_allowed = allowed
	if not allowed:
		emit_ad_state(false, privacy_required, consent_open, ad_error)
