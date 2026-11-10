class_name PurchaseScreen
extends RefCounted
## The explicit Play purchase and restore controls, opened from the footer shortcut.

const TERMS_URL := "https://braitg.dev/zero-gx/terms/"
const PRIVACY_URL := "https://braitg.dev/zero-gx/privacy/"


static func open(parent: Node) -> Overlay:
	var overlay := Overlay.open(parent, "Remove ads")
	overlay.paragraph("A one-time purchase removes banner ads permanently. Play shows the price before you confirm.")
	overlay.heading("Legal")
	_button(overlay.body, "Terms of Service", func() -> void: OS.shell_open(TERMS_URL))
	_button(overlay.body, "Privacy Policy", func() -> void: OS.shell_open(PRIVACY_URL))
	var price := Label.new()
	price.add_theme_font_size_override("font_size", 30)
	overlay.body.add_child(price)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.body.add_child(status)
	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(240, 56)
	buy.add_theme_font_size_override("font_size", 24)
	buy.pressed.connect(Monetization.buy)
	overlay.body.add_child(buy)
	_button(overlay.body, "Restore purchases", Monetization.restore)
	var refresh := func() -> void:
		price.text = Monetization.price if Monetization.store_ready else ""
		buy.disabled = not Monetization.store_ready or Monetization.ad_free
		if Monetization.ad_free:
			status.text = "Ads have been removed."
		elif not Monetization.store_ready:
			status.text = Monetization.message if Monetization.message != "" else "Google Play price unavailable."
		else:
			status.text = Monetization.message
	Monetization.changed.connect(refresh)
	overlay.tree_exited.connect(_disconnect_refresh.bind(refresh), CONNECT_ONE_SHOT)
	refresh.call()
	return overlay


static func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func _disconnect_refresh(refresh: Callable) -> void:
	if Monetization.changed.is_connected(refresh):
		Monetization.changed.disconnect(refresh)
