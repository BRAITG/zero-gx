class_name DemoViewer
extends Node2D
## Plays a recorded Demo back over its level, built frozen: nothing is simulated, every frame
## places the ship and the asteroids where the demo says they were.

const PREVIEW := preload("res://scenes/level_preview.gd")

var speed := 1.0
var paused := false:
	set(value):
		paused = value
		if _play:
			_play.text = "Play" if paused else "Pause"
## The built level; its ship is moved, its asteroids replaced by ones made from the demo, and
## its pickups and planets hidden by events.
var level: Level
## The playback position in frames, fractional while playing.
var cursor := 0.0
## The built ship (the preview script does not set Level.ship).
var ship: Ship

var _demo: Demo
var _back: Callable
var _camera: Camera2D
var _rocks := {}  # demo asteroid id -> Asteroid node
var _hidden_from := {}  # pickup or planet node -> the frame its event hid it
var _play: Button
var _slider: HSlider


## `back` runs when the player leaves the viewer.
static func create(data: Dictionary, demo: Demo, back: Callable) -> DemoViewer:
	var viewer := DemoViewer.new()
	viewer._demo = demo
	viewer._back = back
	viewer.level = LevelFormat.build(data, PREVIEW)
	viewer.add_child(viewer.level)
	return viewer


func _ready() -> void:
	add_child(Starfield.new())
	move_child(get_child(-1), 0)  # behind the level
	var pickups := level.get_children().filter(func(n: Node) -> bool: return n is Pickup)
	var planets := level.get_children().filter(func(n: Node) -> bool: return n is GravityBody)
	for event: Array in _demo.events():
		if event[1] == Demo.Event.PICKUP_TAKEN:
			_hidden_from[pickups[event[2][0]]] = event[0]
		elif event[1] == Demo.Event.PLANET_SHATTERED:
			_hidden_from[planets[event[2][0]]] = event[0]
	ship = level.get_children().filter(func(n: Node) -> bool: return n is Ship)[0]
	# The demo's ids need not match the built level's asteroids (one may be gone before the first
	# thrust), so every asteroid is made from the demo.
	for rock in level.get_children().filter(func(n: Node) -> bool: return n is Asteroid):
		rock.free()
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()  # the built ship carries a camera of its own
	_build_ui()
	seek(0)


func _process(delta: float) -> void:
	if paused:
		return
	var last := _demo.frame_count() - 1
	cursor = minf(cursor + delta * speed / Demo.STEP, last)
	_show(cursor)
	_slider.set_value_no_signal(cursor)
	if cursor >= last:
		paused = true


## Puts everything exactly where it was at `frame`.
func seek(frame: int) -> void:
	cursor = clampi(frame, 0, _demo.frame_count() - 1)
	_show(cursor)
	_slider.set_value_no_signal(cursor)


## Places the scene at `at` frames, blending from the frame before to the next.
func _show(at: float) -> void:
	var f := floori(at)
	var next := mini(f + 1, _demo.frame_count() - 1)
	var t := at - f
	var now := _demo.ship_at(f)
	var after := _demo.ship_at(next)
	ship.global_position = now.position.lerp(after.position, t)
	ship.global_rotation = lerp_angle(now.rotation, after.rotation, t)
	if ship.firing != now.firing:
		ship.firing = now.firing
		ship.queue_redraw()
	_camera.position = ship.global_position
	for node: Node2D in _hidden_from:
		node.visible = f < _hidden_from[node]
	var here := _demo.asteroids_at(f)
	var ahead := _demo.asteroids_at(next)
	for id in here:
		var node := rock(id)
		var xform: Transform2D = here[id]
		var to: Transform2D = ahead.get(id, xform)
		node.visible = true
		node.global_position = xform.origin.lerp(to.origin, t)
		node.global_rotation = lerp_angle(xform.get_rotation(), to.get_rotation(), t)
	for id in _rocks:
		if not here.has(id):
			_rocks[id].visible = false


## The node for asteroid `id`, made the first time it is needed.
func rock(id: int) -> Asteroid:
	if not _rocks.has(id):
		_rocks[id] = LevelFormat.ASTEROID.instantiate()
		level.add_child(_rocks[id])
	return _rocks[id]


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 16)
	ui.add_child(top)
	_button(top, "Back", _back)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 16)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 12)
	ui.add_child(bottom)
	_play = _button(bottom, "Pause", func() -> void:
		if paused and cursor >= _demo.frame_count() - 1:
			seek(0)  # play again from the start
		paused = not paused)
	var group := ButtonGroup.new()
	for rate in [0.5, 1.0, 2.0]:
		var button := _button(bottom, "%s×" % String.num(rate), func() -> void: speed = rate)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = rate == speed
	_slider = HSlider.new()
	_slider.max_value = _demo.frame_count() - 1
	_slider.step = 1.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(value: float) -> void: seek(int(value)))
	bottom.add_child(_slider)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back.call()
