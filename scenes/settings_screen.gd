class_name SettingsScreen
extends RefCounted
## Shared display, sound and control settings, opened from the menu or a paused flight.


static func open(parent: Node) -> Overlay:
	var o := Overlay.open(parent, "Settings")
	_setting(o, "Show the velocity arrow in levels",
		"The arrow points where your ship is going; its length shows how fast. The training stages always show it.",
		Settings.show_velocity, func(on: bool): Settings.show_velocity = on)
	_setting(o, "Show gravity fields",
		"Faint discs show how far each planet, black hole and star pulls.",
		Settings.show_gravity, func(on: bool): Settings.show_gravity = on)
	var sound := o.card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	sound.add_child(row)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 26)
	label.custom_minimum_size.x = 260
	row.add_child(label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volume
	slider.custom_minimum_size = Vector2(520, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var show := func(v: float): label.text = "Sound: %d%%" % roundi(v * 100.0)
	show.call(slider.value)
	slider.value_changed.connect(show)
	slider.value_changed.connect(func(v: float): Settings.volume = v)
	slider.drag_ended.connect(func(_changed: bool): Sfx.play("tap"))
	_button(o.body, "Controls", func(): ControlsScreen.open(o))
	_button(o.body, "Developer options", func():
		var options := Overlay.open(o, "Developer options")
		options.paragraph("Tuning changes last until the app closes. Reset progress permanently deletes saved best scores.")
		_button(options.body, "Tune", func(): TuningPanel.open(options)))
	return o


static func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 52)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)


## One panelled card: an enlarged toggle over a dim explanation of what it does.
static func _setting(o: Overlay, title: String, description: String, on: bool, set_on: Callable) -> void:
	var box := o.card()
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.add_theme_font_size_override("font_size", 26)
	toggle.button_pressed = on
	toggle.toggled.connect(set_on)
	toggle.toggled.connect(func(_on: bool): Sfx.play("tap"))
	_big_switch(toggle)
	box.add_child(toggle)
	o.paragraph(description, 20, Style.INK_DIM, box)


const SWITCH_SCALE := 1.6
## The engine's default switch graphic is tiny next to 26 px text; redraw it larger.
static func _big_switch(toggle: CheckButton) -> void:
	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored"]:
		var icon: Texture2D = toggle.get_theme_icon(icon_name)
		if icon == null:
			continue
		var image := icon.get_image()
		if image == null:
			continue
		image.resize(int(image.get_width() * SWITCH_SCALE), int(image.get_height() * SWITCH_SCALE), Image.INTERPOLATE_LANCZOS)
		toggle.add_theme_icon_override(icon_name, ImageTexture.create_from_image(image))
