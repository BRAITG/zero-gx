class_name LevelEditor
extends Node2D
## The in-app level editor: a tool palette over a snapping grid. One finger runs the tool; two
## fingers pan and pinch-zoom. Spec: docs/superpowers/specs/2026-10-16-level-editor-design.md.

const PREVIEW := preload("res://scenes/level_preview.gd")
const TOOLS := ["select", "wall", "planet", "black_hole", "star", "asteroid", "pickup", "start", "goal", "erase"]
const TOOL_LABELS := {"select": "Select", "wall": "Wall", "planet": "Planet", "black_hole": "Black hole", "star": "Star", "asteroid": "Asteroid", "pickup": "Pickup", "start": "Start", "goal": "Goal", "erase": "Erase"}
const ZOOM_RANGE := Vector2(0.1, 1.5)
const DRIFT_PER_PX := 1.0  # px/s of asteroid drift per px dragged
const MAX_DRIFT := 400.0  # px/s
const DRAG_START := 12.0  # screen px a finger must move before a press becomes a drag
const GRID_COLOR := Color(1, 1, 1, 0.06)

var level_id := ""
var doc: LevelDoc
var tool := "select"
var wall_kind := "blue"
var pickup_kind := "thrust_up"
var fine_snap := false

var _camera: Camera2D
var _preview: Node2D
var _marks: Node2D
var _error_label: Label
var _tool_buttons := {}
var _wall_bar: HBoxContainer
var _touches := {}  # touch index -> screen position
var _pinch_start := {}
var _pressed_at := Vector2.ZERO  # screen
var _dragging := false
var _held: Dictionary = {}  # the ref a select drag is moving, or the asteroid being aimed


## The editor for the player's level `id` (a new blank level if there is none yet).
static func create(id: String) -> LevelEditor:
	var editor := LevelEditor.new()
	editor.level_id = id
	var data := MyLevels.load_level(id)
	editor.doc = LevelDoc.new(data)
	return editor


func _ready() -> void:
	add_child(Starfield.new())
	_preview = Node2D.new()
	add_child(_preview)
	_marks = Node2D.new()
	_marks.z_index = 50
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	_camera = Camera2D.new()
	_camera.zoom = Vector2.ONE * 0.5
	_camera.position = LevelDoc._v(doc.data.ship.position)
	add_child(_camera)
	_build_ui()
	_refresh()


## Save the level to the device.
func save() -> void:
	doc.finish_wall()
	MyLevels.save(level_id, doc.data)


func select_tool(name: String) -> void:
	doc.finish_wall()
	tool = name
	for key: String in _tool_buttons:
		_tool_buttons[key].button_pressed = key == name
	_wall_bar.visible = name == "wall"
	_refresh()


## One-finger actions in world coordinates: what a press, a drag and a release do with the tool.
func press(world: Vector2) -> void:
	var at := LevelDoc.snap(world, fine_snap)
	_held = {}
	match tool:
		"select":
			_held = doc.hit(world)
			if not _held.is_empty():
				doc.begin_move()
		"planet", "black_hole", "star":
			doc.place(tool, at)
		"pickup":
			doc.place(pickup_kind, at)
		"asteroid":
			_held = doc.place("asteroid", at)
		"start", "goal":
			doc.begin_move()
			doc.move({"type": "ship" if tool == "start" else "goal", "index": 0}, at)
	_refresh()


func drag(world: Vector2) -> void:
	if _held.is_empty():
		return
	if tool == "select":
		doc.move(_held, LevelDoc.snap(world, fine_snap))
	elif tool == "asteroid" and not doc.data.asteroids[_held.index].has("orbit"):
		var rock: Dictionary = doc.data.asteroids[_held.index]
		var velocity := ((world - LevelDoc._v(rock.position)) * DRIFT_PER_PX).limit_length(MAX_DRIFT)
		rock.velocity = LevelDoc._p(velocity)
	_refresh()


func release(world: Vector2, was_drag: bool) -> void:
	match tool:
		"wall":
			if not was_drag:
				doc.add_wall_point(LevelDoc.snap(world, fine_snap), wall_kind)
		"erase":
			var ref := doc.hit(world)
			if not ref.is_empty():
				doc.erase(ref)
		"select":
			if not was_drag and not _held.is_empty():
				_open_sheet(_held)
	_held = {}
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			_held = {}  # a second finger turns the gesture into pan and zoom
			_pinch_start = {"distance": _touches.values()[0].distance_to(_touches.values()[1]), "zoom": _camera.zoom.x, "mid": (_touches.values()[0] + _touches.values()[1]) / 2.0, "camera": _camera.position}
		elif event.index == 0 or _touches.size() <= 1:
			_one_finger(event.pressed, event.position)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2 and not _pinch_start.is_empty():
			var a: Vector2 = _touches.values()[0]
			var b: Vector2 = _touches.values()[1]
			var zoom := clampf(_pinch_start.zoom * a.distance_to(b) / maxf(_pinch_start.distance, 1.0), ZOOM_RANGE.x, ZOOM_RANGE.y)
			_camera.zoom = Vector2.ONE * zoom
			_camera.position = _pinch_start.camera - ((a + b) / 2.0 - _pinch_start.mid) / zoom
			_marks.queue_redraw()
		elif _touches.size() == 1:
			if not _dragging and event.position.distance_to(_pressed_at) > DRAG_START:
				_dragging = true
			if _dragging:
				drag(_to_world(event.position))
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		# A mouse on desktop: the wheel zooms; the left button acts like a finger.
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_camera.zoom = Vector2.ONE * clampf(_camera.zoom.x * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9), ZOOM_RANGE.x, ZOOM_RANGE.y)
			_marks.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_one_finger(event.pressed, event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _dragging and event.position.distance_to(_pressed_at) > DRAG_START:
			_dragging = true
		if _dragging:
			drag(_to_world(event.position))


func _one_finger(down: bool, screen: Vector2) -> void:
	if down:
		_pressed_at = screen
		_dragging = false
		_pinch_start = {}
		press(_to_world(screen))
	elif _pinch_start.is_empty():
		release(_to_world(screen), _dragging)


func _to_world(screen: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen


## Rebuild the frozen preview from the data and show the level's problems.
func _refresh() -> void:
	for old in _preview.get_children():
		old.free()
	_preview.add_child(LevelFormat.build(doc.data, PREVIEW))
	_camera.make_current()
	var problems := doc.errors()
	_error_label.text = "" if problems.is_empty() else "⚠ " + problems[0] + ("  (+%d more)" % (problems.size() - 1) if problems.size() > 1 else "")
	_marks.queue_redraw()


func _draw_marks() -> void:
	var view := get_viewport_rect().size / _camera.zoom
	var corner := (_camera.position - view / 2.0).snapped(Vector2.ONE * LevelDoc.COARSE_SNAP)
	var step := LevelDoc.COARSE_SNAP * (1 if _camera.zoom.x >= 0.3 else 10)
	var lines := ceili(maxf(view.x, view.y) / step) + 2
	for i in lines:
		var x := corner.x + i * step
		var y := corner.y + i * step
		_marks.draw_line(Vector2(x, corner.y - step), Vector2(x, corner.y + view.y + step), GRID_COLOR, 1.0 / _camera.zoom.x)
		_marks.draw_line(Vector2(corner.x - step, y), Vector2(corner.x + view.x + step, y), GRID_COLOR, 1.0 / _camera.zoom.x)
	var width := 2.0 / _camera.zoom.x
	for rock in doc.data.get("asteroids", []):  # drift arrows
		if rock.has("velocity") and not rock.has("orbit"):
			var from := LevelDoc._v(rock.position)
			_marks.draw_line(from, from + LevelDoc._v(rock.velocity), Color(1, 1, 1, 0.6), width)
	if doc.drawing >= 0:
		var points: Array = doc.data.walls[doc.drawing].points
		_marks.draw_circle(LevelDoc._v(points[0]), LevelDoc.CLOSE_DISTANCE, Color(1, 1, 1, 0.15))
	if not _held.is_empty() and tool == "select":
		_marks.draw_arc(doc.position_of(_held), 60.0, 0.0, TAU, 32, Style.ACCENT, width)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	top.add_theme_constant_override("separation", 10)
	ui.add_child(top)
	_button(top, "Back", func() -> void:
		save()
		get_tree().change_scene_to_node(MyLevelsScreen.new()))
	_button(top, "Undo", func() -> void:
		doc.undo()
		_refresh())
	_button(top, "Settings", _open_settings)
	var fine := CheckButton.new()
	fine.text = "1 m grid"
	fine.toggled.connect(func(on: bool) -> void: fine_snap = on)
	top.add_child(fine)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_button(top, "Test", _test)
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color("#ff8a6a"))
	_error_label.add_theme_font_size_override("font_size", 20)
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_error_label)
	_error_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	_error_label.offset_top = -120
	_error_label.offset_bottom = -84
	_wall_bar = HBoxContainer.new()
	_wall_bar.add_theme_constant_override("separation", 10)
	_wall_bar.hide()
	ui.add_child(_wall_bar)
	var kind_button := _button(_wall_bar, "Colour: blue", func() -> void: pass)
	kind_button.pressed.connect(func() -> void:
		wall_kind = LevelFormat.WALL_KINDS[(LevelFormat.WALL_KINDS.find(wall_kind) + 1) % 3]
		kind_button.text = "Colour: " + wall_kind)
	_button(_wall_bar, "Done", func() -> void:
		doc.finish_wall()
		_refresh())
	var palette := HBoxContainer.new()
	palette.add_theme_constant_override("separation", 6)
	ui.add_child(palette)
	var group := ButtonGroup.new()
	for name: String in TOOLS:
		var button := _button(palette, TOOL_LABELS[name], select_tool.bind(name))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 64)
		_tool_buttons[name] = button
	_tool_buttons.pickup.pressed.connect(func() -> void:
		if tool == "pickup":  # a second tap cycles the kind
			pickup_kind = LevelFormat.PICKUP_KINDS[(LevelFormat.PICKUP_KINDS.find(pickup_kind) + 1) % 3]
		_tool_buttons.pickup.text = "Pickup: " + pickup_kind.replace("_", " "))
	_tool_buttons.select.button_pressed = true
	palette.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	palette.offset_left = 8
	palette.offset_right = -8
	palette.offset_top = -72
	palette.offset_bottom = -8
	_wall_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 84)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 56)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _test() -> void:
	if not doc.errors().is_empty():
		_error_label.modulate = Color(2, 2, 2)
		create_tween().tween_property(_error_label, "modulate", Color.WHITE, 0.5)
		return
	save()
	Progress.open(level_id, true)


func _open_settings() -> void:
	var o := Overlay.open(self, "Level settings")
	_line(o, "Title", doc.data.get("title", ""), LevelFormat.MAX_TITLE, func(text: String) -> void: doc.set_setting("title", text))
	_line(o, "Hint", doc.data.get("hint", ""), LevelFormat.MAX_TEXT, func(text: String) -> void: doc.set_setting("hint", text))
	for tank: String in ["fuel", "hull"]:
		_tank(o, tank)
	var arrow := CheckButton.new()
	arrow.text = "Show the velocity arrow"
	arrow.button_pressed = doc.data.get("show_velocity", false)
	arrow.toggled.connect(func(on: bool) -> void:
		doc.set_setting("show_velocity", on)
		_refresh())
	o.body.add_child(arrow)
	o.tree_exited.connect(_refresh)


func _line(o: Overlay, label: String, value: String, limit: int, apply: Callable) -> void:
	o.paragraph(label, 20, Style.INK_DIM)
	var edit := LineEdit.new()
	edit.text = value
	edit.max_length = limit
	edit.custom_minimum_size = Vector2(Overlay.WIDTH, 52)
	edit.text_changed.connect(apply)
	o.body.add_child(edit)


func _tank(o: Overlay, tank: String) -> void:
	var value: Variant = doc.data.ship.get(tank, 100)
	var unlimited := LevelFormat.is_unlimited(value)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	o.body.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 260
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = LevelFormat.TANK_RANGE.x
	slider.max_value = LevelFormat.TANK_RANGE.y
	slider.step = 1
	slider.value = 100 if unlimited else value
	slider.editable = not unlimited
	slider.custom_minimum_size = Vector2(480, 48)
	row.add_child(slider)
	var forever := CheckButton.new()
	forever.text = "Unlimited"
	forever.button_pressed = unlimited
	row.add_child(forever)
	var show := func() -> void:
		label.text = "%s: %s" % [tank.capitalize(), "∞" if forever.button_pressed else str(int(slider.value))]
	slider.value_changed.connect(func(v: float) -> void:
		doc.set_setting(tank, int(v))
		show.call())
	forever.toggled.connect(func(on: bool) -> void:
		slider.editable = not on
		doc.set_setting(tank, LevelFormat.UNLIMITED if on else int(slider.value))
		show.call())
	show.call()


## The sheet for one thing in the level: its kind and the numbers its kind may change.
func _open_sheet(ref: Dictionary) -> void:
	if ref.type in ["ship", "goal", "wall_point"]:
		return  # nothing to set beyond position
	var o := Overlay.open(self, TOOL_LABELS.get(ref.type, ref.type.capitalize()) if ref.type != "body" else doc.data.bodies[ref.index].kind.replace("_", " ").capitalize())
	o.tree_exited.connect(_refresh)
	match ref.type:
		"wall":
			_choice(o, "Colour", LevelFormat.WALL_KINDS, doc.data.walls[ref.index].kind, func(kind: String) -> void: doc.set_property(ref, "kind", kind))
		"pickup":
			_choice(o, "Kind", LevelFormat.PICKUP_KINDS, doc.data.pickups[ref.index].kind, func(kind: String) -> void: doc.set_property(ref, "kind", kind))
		"asteroid":
			var rock: Dictionary = doc.data.asteroids[ref.index]
			if rock.has("orbit"):
				_slider(o, "Orbit speed (rad/s, negative = clockwise)", Vector2(-3, 3), 0.1, rock.orbit.speed, func(v: float) -> void:
					rock.orbit.speed = v)
			else:
				o.paragraph("Drag outward from an asteroid with the Asteroid tool to set its drift.", 20, Style.INK_DIM)
		"body":
			var body: Dictionary = doc.data.bodies[ref.index]
			var limits: Dictionary = LevelFormat.KIND_LIMITS[body.kind]
			_slider(o, "Radius (px)", limits.radius, 4, LevelFormat.body_value(body, "radius"), func(v: float) -> void: doc.set_property(ref, "radius", v))
			_slider(o, "Surface pull (px/s²)", limits.get("strength", Vector2(100, 20000)), 50, LevelFormat.body_value(body, "strength"), func(v: float) -> void: doc.set_property(ref, "strength", v))
			_slider(o, "Reach (px)", limits.reach, 50, LevelFormat.body_value(body, "reach"), func(v: float) -> void: doc.set_property(ref, "reach", v))
			if body.kind == "planet":
				var breakable := CheckButton.new()
				breakable.text = "Destructible (asteroids can shatter it)"
				breakable.button_pressed = body.get("destructible", false)
				breakable.toggled.connect(func(on: bool) -> void:
					doc.set_property(ref, "destructible", on)
					if on and not body.has("health"):
						doc.set_property(ref, "health", 100))
				o.body.add_child(breakable)
				_slider(o, "Health", Vector2(1, 1000), 1, body.get("health", 100), func(v: float) -> void: doc.set_property(ref, "health", v))
			o.paragraph("Total pull from afar must stay within this kind's limits; problems show at the bottom of the editor.", 18, Style.INK_DIM)


func _choice(o: Overlay, label: String, options: Array, current: String, apply: Callable) -> void:
	o.paragraph(label, 20, Style.INK_DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	o.body.add_child(row)
	var group := ButtonGroup.new()
	for option: String in options:
		var button := _button(row, option.replace("_", " "), apply.bind(option))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = option == current


func _slider(o: Overlay, label: String, bounds: Vector2, step: float, value: float, apply: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	o.body.add_child(row)
	var slider := HSlider.new()
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(520, 48)
	row.add_child(slider)
	var text := Label.new()
	row.add_child(text)
	var show := func(v: float) -> void: text.text = "%s: %s" % [label, snappedf(v, step)]
	slider.value_changed.connect(apply)
	slider.value_changed.connect(show)
	show.call(value)


## Android's back gesture leaves like Back: save, then the level list.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save()
		get_tree().change_scene_to_node(MyLevelsScreen.new())
