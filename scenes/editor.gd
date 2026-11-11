class_name LevelEditor
extends Node2D
## The in-app level editor: a tool palette over a snapping grid. One finger runs the tool; two
## fingers pan and pinch-zoom. Spec: docs/superpowers/specs/2026-11-11-editor-interaction-design.md.
## A mouse pans with the right or middle button and zooms with the wheel; a Mac trackpad swipes to pan and pinches to zoom. Ctrl/Cmd+Z undoes, Ctrl/Cmd+S saves, T test-flies (none while a menu or text field is modal).

const PREVIEW := preload("res://scenes/level_preview.gd")
const TOOLS := ["select", "wall", "planet", "black_hole", "star", "asteroid", "pickup", "start", "goal", "erase"]
const TOOL_LABELS := {"select": "Select", "wall": "Wall", "planet": "Planet", "black_hole": "Black hole", "star": "Star", "asteroid": "Asteroid", "pickup": "Pickup", "start": "Start", "goal": "Goal", "erase": "Erase"}
const PLACING := ["planet", "black_hole", "star", "asteroid", "pickup"]  # tools that add a thing
const ZOOM_RANGE := Vector2(0.1, 1.5)
const DRIFT_PER_PX := 1.0  # px/s of asteroid drift per px dragged
const MAX_DRIFT := 400.0  # px/s
const DRAG_START := 12.0  # viewport units a finger must move before a press becomes a drag
const LONG_PRESS := 0.5  # s a finger rests on a thing before opening its context menu
const GRID_COLOR := Color(1, 1, 1, 0.06)
const MAJOR_GRID_COLOR := Color(1, 1, 1, 0.14)
const FINE_GRID_MIN_PX := 3.0  # screen px between 1 m lines below which they would merge into a fill
const PICKUP_LABELS := {"thrust_up": "Thrust up", "thrust_down": "Thrust down", "boost": "Boost"}
const WALL_LABELS := {"blue": "Blue", "orange": "Orange", "red": "Red"}
const WALL_COLORS := {"blue": Barrier.COLORS[Barrier.Kind.BLUE], "orange": Barrier.COLORS[Barrier.Kind.ORANGE], "red": Barrier.COLORS[Barrier.Kind.RED]}
const HINTS := {  # the gestures of each tool, one line above the palette
	"select": "Click to select · drag to move · right-click for properties",
	"wall": "Click to add points · click the first point to close · Enter, Done or Esc finishes",
	"planet": "Tap to place · drag a thing to move it · hold it to edit it",
	"black_hole": "Tap to place · drag a thing to move it · hold it to edit it",
	"star": "Tap to place · drag a thing to move it · hold it to edit it",
	"asteroid": "Tap to place · drag outward to set its drift · hold it to edit it",
	"pickup": "Tap to place this kind · drag a pickup to move it · hold it to edit it",
	"start": "Tap to place the ship · hold it to set its heading and speed",
	"goal": "Tap to place the goal",
	"erase": "Tap a thing to erase it",
}

## The editor left for a test flight: {id, doc, view}. Only one test flight runs at a time.
static var _kept := {}

var level_id := ""
var doc: LevelDoc
var tool := "select"
var wall_kind := "blue"
var pickup_kind := "thrust_up"
var fine_snap := false

var _camera: Camera2D
var _preview: Node2D
var _marks: Node2D
var _marks_clip: Control
var _error_label: Label
var _top_bar: HBoxContainer
var _hint_backing: PanelContainer
var _palette: HBoxContainer
var _ui_layer: CanvasLayer
var _modal_layer: CanvasLayer
var _ui_scale := 1.0
var _keyboard_height := -1.0
var _menu_panel: PanelContainer
var _menu_ref: Dictionary = {}
var _menu_anchor := Vector2.ZERO
var _menu_touch := false
var _menu_content_height := 0.0
var _property_panel: EditorPropertyPanel
var _panel_ref: Dictionary = {}
var _panel_property := ""
var _panel_radius := 0.0
var _panel_mass := 0.0
var _panel_direction := 0.0
var _panel_speed := 0.0
var _tool_buttons := {}
var _wall_bar: PanelContainer
var _wall_buttons := {}
var _wall_checks := {}
var _wall_done_button: Button
var _pickup_bar: HBoxContainer
var _undo_button: Button
var _title_label: Label
var _state_label: Label
var _hint_label: Label
var _saved := {}  # the level as the file holds it, so a draft knows whether it has unsaved changes
var _dirty := false
var _touches := {}  # touch index -> screen position
var _pinch_start := {}
var _pressed_at := Vector2.ZERO  # screen
var _dragging := false
var _presses := 0  # counts finger downs and ups, so a long-press timer can tell its press is still down
var _long_pressed := false  # the press opened a context menu, so its release does nothing
var _held: Dictionary = {}  # the ref being edited by this gesture
var _view := []  # [camera position, zoom] to restore, or empty for the start
var _moving := false  # a placing tool pressed on an existing thing, which it now drags
var _pan_from := {}  # {"screen", "camera"} while a right or middle drag pans the view
var _right_press_at := Vector2.ZERO
var _right_press_ref: Dictionary = {}
var _right_dragged := false
var selection: Dictionary = {}
var _touch_input: bool = false
var _selection_before_insert: Dictionary = {}
var _inserted_wall_point: bool = false
var _hover: Dictionary = {}
var _press_ref: Dictionary = {}
var _press_world: Vector2 = Vector2.ZERO
var _press_position: Vector2 = Vector2.ZERO
var _press_offset: Vector2 = Vector2.ZERO
var _gesture_cancelled: bool = false

var _active_body_handle: Dictionary = {}


## The editor for the player's level `id` (a new blank level if there is none yet).
## After a test flight, the editor comes back with the same undo history and view.
static func create(id: String) -> LevelEditor:
	var editor := LevelEditor.new()
	editor.level_id = id
	var kept: Dictionary = _kept if _kept.get("id") == id else {}
	_kept = {}
	var saved := MyLevels.load_level(id)
	editor.doc = kept.get("doc", LevelDoc.new(saved))
	editor._saved = saved
	editor._view = kept.get("view", [])
	return editor


func _ready() -> void:
	add_child(Starfield.new())
	_preview = Node2D.new()
	add_child(_preview)
	_marks = Node2D.new()
	_marks_clip = Control.new()
	_marks_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks_clip.clip_contents = true
	add_child(_marks_clip)
	_marks_clip.add_child(_marks)
	_marks.z_index = 50
	_marks.draw.connect(_draw_marks)
	var dpi: float = float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = 96.0
	var viewport_size: Vector2 = get_viewport_rect().size
	var window_size: Vector2 = DisplayServer.window_get_size()
	var stretch: float = maxf(window_size.x / maxf(viewport_size.x, 1.0), 1.0) if window_size.x > 0.0 else 1.0
	_ui_scale = dpi / 160.0 / stretch
	_camera = Camera2D.new()
	_camera.zoom = Vector2.ONE * 0.5 if _view.is_empty() else _view[1]
	_camera.position = LevelDoc._v(doc.data.ship.position) if _view.is_empty() else _view[0]
	add_child(_camera)
	_build_ui()
	_refresh()


func _process(_delta: float) -> void:
	var keyboard_height: float = float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	var keyboard_hidden_hint: bool = keyboard_height == 0.0
	if _hint_backing.visible != keyboard_hidden_hint:
		_hint_backing.visible = keyboard_hidden_hint
	if not is_equal_approx(_keyboard_height, keyboard_height):
		_keyboard_height = keyboard_height
		if is_instance_valid(_property_panel):
			_position_property_panel(_panel_ref, _free_canvas_rect())
	_layout_hint_backing()
	_layout_canvas_clip()


func save() -> bool:
	_close_context_menu()
	_close_property_panel()
	_invalidate_gesture()
	_end_edit()
	selection = {}
	_hover = {}
	doc.finish_wall()
	MyLevels.save(level_id, doc.data)
	var written: bool = LevelFormat.sha256(MyLevels.load_level(level_id)) == LevelFormat.sha256(doc.data)
	if written:
		_saved = doc.data.duplicate(true)
	else:
		Overlay.open(self, "Cannot save").paragraph("The level could not be written to the device.")
	_refresh()
	return written


func select_tool(name: String) -> void:
	_close_context_menu()
	_close_property_panel()
	_invalidate_gesture()
	_end_edit()
	_hover = {}
	if name != tool:
		selection = {}
	doc.finish_wall()
	tool = name
	for key: String in _tool_buttons:
		_tool_buttons[key].button_pressed = key == name
	_pickup_bar.visible = name == "pickup"
	_refresh()


func select(ref: Dictionary) -> void:
	if selection == ref:
		_end_edit()
		return
	_close_context_menu()
	_close_property_panel()
	_end_edit()
	selection = ref
	_refresh()


func pick(screen: Vector2, mouse: bool) -> Dictionary:
	return _pick_world(_to_world(screen), mouse)


func _pick_world(world: Vector2, mouse: bool) -> Dictionary:
	var slop: float = (LevelDoc.HIT_SLOP_MOUSE if mouse else LevelDoc.HIT_SLOP) / _camera.zoom.x
	var picked: Dictionary = doc.hit(world, slop)
	var handle: Dictionary = _pick_wall_handle(world, slop)
	if handle.is_empty():
		handle = _pick_body_handle(world, slop)
	if handle.is_empty():
		return picked
	if picked.get("type", "") in ["wall_point", "ship", "asteroid", "pickup"]:
		var handle_at: Vector2 = _wall_segment_midpoint(handle.index, handle.after) if handle.type == "wall_handle" else handle.at
		if doc.position_of(picked).distance_to(world) <= handle_at.distance_to(world):
			return picked
	return handle


func _pick_body_handle(world: Vector2, slop: float) -> Dictionary:
	if selection.get("type", "") != "body":
		return {}
	var body_index: int = selection.index
	var nearest: float = INF
	var picked: Dictionary = {}
	for role: String in ["radius", "reach"]:
		var at: Vector2 = _body_handle_position(body_index, role, slop)
		var distance: float = at.distance_to(world)
		if distance <= slop and distance < nearest:
			nearest = distance
			picked = {"type": "body_handle", "index": body_index, "role": role, "at": at}
	return picked

func _body_handle_position(body_index: int, role: String, slop: float) -> Vector2:
	var body: Dictionary = doc.data.bodies[body_index]
	var direction: Vector2 = Vector2(1, -1).normalized() if role == "radius" else Vector2(1, 1).normalized()
	var distance: float = maxf(LevelFormat.body_value(body, role), slop + 1.0 / _camera.zoom.x)
	return doc.position_of({"type": "body", "index": body_index}) + direction * distance

func _pick_wall_handle(world: Vector2, slop: float) -> Dictionary:
	if selection.get("type", "") not in ["wall", "wall_point"]:
		return {}
	var wall_index: int = selection.index
	var walls: Array = doc.data.get("walls", [])
	if wall_index < 0 or wall_index >= walls.size():
		return {}
	var wall: Dictionary = walls[wall_index]
	var points: Array = wall.points
	var nearest: float = INF
	var picked_after: int = -1
	for after in range(points.size() - 1):
		var distance: float = _wall_segment_midpoint(wall_index, after).distance_to(world)
		if distance <= slop and distance < nearest:
			nearest = distance
			picked_after = after
	if wall.get("closed", false) and points.size() > 1:
		var closing_distance: float = _wall_segment_midpoint(wall_index, points.size() - 1).distance_to(world)
		if closing_distance <= slop and closing_distance < nearest:
			nearest = closing_distance
			picked_after = points.size() - 1
	if picked_after < 0:
		return {}
	return {"type": "wall_handle", "index": wall_index, "after": picked_after}


func _wall_segment_midpoint(wall_index: int, after: int) -> Vector2:
	var points: Array = doc.data.walls[wall_index].points
	return (LevelDoc._v(points[after]) + LevelDoc._v(points[(after + 1) % points.size()])) / 2.0


func _wall_segment_after(wall_index: int, at: Vector2) -> int:
	var wall: Dictionary = doc.data.walls[wall_index]
	var points: Array = wall.points
	var nearest: float = INF
	var picked_after: int = -1
	for after in range(points.size() - 1):
		var distance: float = Geometry2D.get_closest_point_to_segment(at, LevelDoc._v(points[after]), LevelDoc._v(points[after + 1])).distance_to(at)
		if distance < nearest:
			nearest = distance
			picked_after = after
	if wall.get("closed", false) and points.size() > 1:
		var closing_distance: float = Geometry2D.get_closest_point_to_segment(at, LevelDoc._v(points[-1]), LevelDoc._v(points[0])).distance_to(at)
		if closing_distance < nearest:
			picked_after = points.size() - 1
	return picked_after




## One-finger actions in world coordinates: what a press, drag and release do with the tool.
func press(world: Vector2, mouse: bool = false) -> void:
	_close_context_menu()
	_close_property_panel()
	var at: Vector2 = _place_at(world, tool)
	_press_world = world
	_press_ref = _pick_world(world, mouse)
	if mouse:
		_hover = _press_ref
	_held = {}
	_active_body_handle = {}
	_moving = false
	_press_offset = Vector2.ZERO
	_press_position = world
	if tool == "select":
		if _press_ref.get("type", "") == "body_handle":
			var body_ref: Dictionary = {"type": "body", "index": _press_ref.index}
			var body: Dictionary = doc.data.bodies[_press_ref.index]
			_active_body_handle = _press_ref.duplicate()
			_active_body_handle["value"] = LevelFormat.body_value(body, _press_ref.role)
			_active_body_handle["distance"] = doc.position_of(body_ref).distance_to(world)
			_active_body_handle["total_pull"] = LevelFormat.total_pull(body)
			doc.begin_edit()
		elif _press_ref.get("type", "") == "wall_handle":
			_insert_wall_point(_press_ref.index, _press_ref.after, _wall_segment_midpoint(_press_ref.index, _press_ref.after))
		else:
			select(_press_ref)
			if not _press_ref.is_empty():
				_held = selection
				_press_position = doc.position_of(_held)
				if _held.type != "wall_point":
					_press_offset = _press_position - world
				doc.begin_edit()
	elif tool in PLACING and not _press_ref.is_empty() and not _press_ref.type in ["wall", "wall_point"]:
		_held = _press_ref
		_moving = true
		_press_position = doc.position_of(_held)
		_press_offset = _press_position - world
		doc.begin_edit()
	elif tool == "wall":
		doc.begin_edit()
	elif tool in ["planet", "black_hole", "star", "pickup", "asteroid"]:
		doc.begin_edit()
		if tool == "asteroid":
			_held = doc.place("asteroid", at)
		elif tool == "pickup":
			doc.place(pickup_kind, at)
		else:
			doc.place(tool, at)
	elif tool == "start":
		_held = {"type": "ship", "index": 0}
		_press_position = doc.position_of(_held)
		doc.begin_edit()
	elif tool == "goal":
		_held = {"type": "goal", "index": 0}
		_press_position = doc.position_of(_held)
		doc.begin_edit()
	_refresh()


func _insert_wall_point(wall_index: int, after: int, at: Vector2) -> bool:
	if not doc.editing():
		doc.begin_edit()
	var ref: Dictionary = doc.insert_wall_point(wall_index, after, at)
	if ref.is_empty():
		_held = {}
		_press_ref = {}
		return false
	_selection_before_insert = selection.duplicate()
	_inserted_wall_point = true
	selection = ref
	_hover = {}
	_held = ref
	_press_ref = ref
	_press_position = doc.position_of(ref)
	_press_offset = Vector2.ZERO
	return true

func drag(world: Vector2) -> void:
	if not _active_body_handle.is_empty():
		_drag_body_handle(world)
		_refresh()
		return
	if _held.is_empty():
		return
	if tool == "select" or _moving or tool in ["start", "goal"]:
		var target: Vector2
		if _held.type == "wall":
			target = _press_position + LevelDoc.snap(world - _press_world, fine_snap)
		elif _held.type == "wall_point":
			target = _place_at(world, "wall_point")
		else:
			target = _place_at(world + _press_offset, _held.type)
		doc.move(_held, target)
	elif tool == "asteroid":
		var rock: Dictionary = doc.data.asteroids[_held.index]
		if not rock.has("orbit"):
			var velocity: Vector2 = ((world - LevelDoc._v(rock.position)) * DRIFT_PER_PX).limit_length(MAX_DRIFT)
			doc.set_property(_held, "velocity", LevelDoc._p(velocity))
	_refresh()


func _drag_body_handle(world: Vector2) -> void:
	var body_index: int = _active_body_handle.index
	var ref: Dictionary = {"type": "body", "index": body_index}
	var body: Dictionary = doc.data.bodies[body_index]
	var role: String = _active_body_handle.role
	var limits: Dictionary = LevelFormat.KIND_LIMITS[body.kind]
	var value_range: Vector2 = limits[role]
	var center: Vector2 = doc.position_of(ref)
	var value_at_press: float = _active_body_handle.value
	var press_distance: float = _active_body_handle.distance
	var value: float = clampf(roundf(value_at_press + world.distance_to(center) - press_distance), value_range.x, value_range.y)
	if is_equal_approx(value, LevelFormat.body_value(body, role)):
		return
	if role == "radius":
		var total_pull: float = _active_body_handle.total_pull
		doc.set_property(ref, "radius", value)
		doc.set_property(ref, "strength", total_pull / pow(value / 1000.0, 2))
	else:
		doc.set_property(ref, role, value)


func release(world: Vector2, was_drag: bool, mouse: bool = false) -> void:
	if not _gesture_cancelled and not _long_pressed:
		_cancel_duplicate_insert()
		match tool:
			"wall":
				if not was_drag:
					doc.add_wall_point(LevelDoc.snap(world, fine_snap), wall_kind, LevelDoc.CLOSE_DISTANCE / _camera.zoom.x)
			"erase":
				_erase_ref(_pick_world(world, mouse), _to_screen(world))
			"start", "goal":
				if not was_drag:
					doc.move(_held, _place_at(_press_world, tool))
	if doc.editing():
		doc.end_edit()
	_held = {}
	_active_body_handle = {}
	_press_ref = {}
	_moving = false
	_inserted_wall_point = false
	_selection_before_insert = {}
	_refresh()


func _cancel_duplicate_insert() -> void:
	if not _inserted_wall_point or _held.is_empty():
		return
	var wall: Dictionary = doc.data.walls[_held.index]
	var points: Array = wall.points
	var point_index: int = _held.point
	var previous_index: int = point_index - 1
	var next_index: int = point_index + 1
	if wall.get("closed", false):
		if previous_index < 0:
			previous_index = points.size() - 1
		if next_index >= points.size():
			next_index = 0
	if (previous_index >= 0 and points[previous_index] == points[point_index]) or (next_index < points.size() and points[next_index] == points[point_index]):
		doc.cancel_edit()
		selection = _selection_before_insert.duplicate()


func _erase_ref(ref: Dictionary, screen := Vector2(-1, -1)) -> void:
	if ref.is_empty() or ref.type in ["ship", "goal"]:
		return
	_close_property_panel()
	_invalidate_gesture()
	var wall: Dictionary = doc.data.walls[ref.index] if ref.type == "wall_point" else {}
	if wall.get("closed", false) and wall.points.size() >= 4:
		var at: Vector2 = _to_screen(doc.position_of(ref)) if screen.x < 0.0 else screen
		_show_context_menu(ref, at, _touch_input, true)
		return
	doc.erase(ref)
	selection = {}
	_hover = {}
	_close_context_menu()
	_refresh()


func _undo() -> void:
	_close_context_menu()
	_close_property_panel()
	_invalidate_gesture()
	selection = {}
	_hover = {}
	doc.undo()
	_refresh()


func _invalidate_gesture() -> void:
	var active: bool = not _held.is_empty() or not _press_ref.is_empty() or _dragging or doc.editing()
	if active:
		_presses += 1
		_gesture_cancelled = true
	if doc.editing():
		doc.end_edit()
	_held = {}
	_active_body_handle = {}
	_press_ref = {}
	_moving = false
	_dragging = false
	_long_pressed = false
	_inserted_wall_point = false
	_selection_before_insert = {}




func _end_edit() -> void:
	if doc.editing():
		doc.end_edit()

func _text_field_focused() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit



func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _property_panel != null:
		_close_property_panel()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_one_finger(true, event.position)
			elif _touches.size() == 2:
				_cancel_one_finger()
				var touch_positions: Array = _touches.values()
				var touch_first: Vector2 = touch_positions[0]
				var touch_second: Vector2 = touch_positions[1]
				_pinch_start = {"distance": touch_first.distance_to(touch_second), "zoom": _camera.zoom.x, "mid": (touch_first + touch_second) / 2.0, "camera": _camera.position}
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				if not _gesture_cancelled:
					_one_finger(false, event.position)
				_pinch_start = {}
				_gesture_cancelled = false
			elif _touches.size() == 1 and not _gesture_cancelled:
				_one_finger(false, event.position)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2 and not _pinch_start.is_empty():
			var drag_positions: Array = _touches.values()
			var drag_first: Vector2 = drag_positions[0]
			var drag_second: Vector2 = drag_positions[1]
			var zoom: float = clampf(_pinch_start.zoom * drag_first.distance_to(drag_second) / maxf(_pinch_start.distance, 1.0), ZOOM_RANGE.x, ZOOM_RANGE.y)
			_camera.zoom = Vector2.ONE * zoom
			_camera.position = _pinch_start.camera - ((drag_first + drag_second) / 2.0 - _pinch_start.mid) / zoom
			_marks.queue_redraw()
		elif _touches.size() == 1 and not _gesture_cancelled:
			if not _dragging and event.position.distance_to(_pressed_at) > DRAG_START:
				_dragging = true
			if _dragging:
				drag(_to_world(event.position))
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _touch_input:
			_touch_input = false
			_marks.queue_redraw()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_zoom_at(1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_press_at = event.position
				_right_press_ref = _menu_target(_pick_world(_to_world(event.position), true))
				_right_dragged = false
				_pan_from = {"screen": event.position, "camera": _camera.position, "button": MOUSE_BUTTON_RIGHT}
			else:
				if not _right_dragged and not _right_press_ref.is_empty():
					_show_context_menu(_right_press_ref, event.position, false)
				_pan_from = {}
				_right_press_ref = {}
				_right_dragged = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_from = {"screen": event.position, "camera": _camera.position, "button": MOUSE_BUTTON_MIDDLE} if event.pressed else {}
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.double_click and tool == "select":
				var at: Vector2 = _to_world(event.position)
				var slop: float = LevelDoc.HIT_SLOP_MOUSE / _camera.zoom.x
				var segment: Dictionary = doc.hit(at, slop)
				if segment.get("type", "") == "wall":
					selection = {}
				_one_finger(true, event.position, true)
				if segment.get("type", "") == "wall" and _press_ref.get("type", "") == "wall":
					var after: int = _wall_segment_after(segment.index, at)
					_insert_wall_point(segment.index, after, _place_at(at, "wall_point"))
					_refresh()
			else:
				_one_finger(event.pressed, event.position, true)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_mask & MOUSE_BUTTON_MASK_RIGHT and not _pan_from.is_empty():
		if not _right_dragged and event.position.distance_to(_right_press_at) > DRAG_START:
			_right_dragged = true
		if _right_dragged:
			_camera.position = _pan_from.camera - (event.position - _pan_from.screen) / _camera.zoom.x
			_marks.queue_redraw()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE and not _pan_from.is_empty():
		_camera.position = _pan_from.camera - (event.position - _pan_from.screen) / _camera.zoom.x
		_marks.queue_redraw()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _dragging and event.position.distance_to(_pressed_at) > DRAG_START:
			_dragging = true
		if _dragging:
			drag(_to_world(event.position))
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		var touch_size_changed: bool = _touch_input
		_touch_input = false
		var hovered: Dictionary = pick(event.position, true)
		if hovered != _hover or touch_size_changed:
			_hover = hovered
			_marks.queue_redraw()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
	elif event is InputEventPanGesture:
		_camera.position += event.delta / _camera.zoom.x
		_marks.queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if not find_children("*", "Overlay", true, false).is_empty():
			return
		if event.keycode != KEY_ESCAPE and _text_field_focused():
			return
		var command: bool = event.is_command_or_control_pressed()
		if command and not event.shift_pressed and event.keycode == KEY_Z:
			_undo()
		elif command and event.keycode == KEY_S:
			save()
		elif _menu_panel != null and not command and event.keycode in [KEY_DELETE, KEY_BACKSPACE, KEY_T]:
			get_viewport().set_input_as_handled()
		elif not command and event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
			_invalidate_gesture()
			_erase_ref(selection)
		elif event.keycode == KEY_ESCAPE:
			if _menu_panel != null:
				_close_context_menu()
			elif _property_panel != null:
				_close_property_panel()
			elif doc.drawing >= 0:
				doc.finish_wall()
				_hover = {}
				_refresh()
			elif not selection.is_empty():
				select({})
			else:
				return
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and doc.drawing >= 0:
			doc.finish_wall()
			_hover = {}
			_refresh()
		elif not command and event.keycode == KEY_T:
			_test()
		else:
			return
		get_viewport().set_input_as_handled()
## Zoom by `factor`, clamped to ZOOM_RANGE, keeping the world point under the screen position `cursor` still.
func _zoom_at(factor: float, cursor: Vector2) -> void:
	var offset := cursor - get_viewport().get_visible_rect().size / 2.0  # the camera is centred on the view
	var zoom := clampf(_camera.zoom.x * factor, ZOOM_RANGE.x, ZOOM_RANGE.y)
	_camera.position += offset / _camera.zoom.x - offset / zoom
	_camera.zoom = Vector2.ONE * zoom
	_marks.queue_redraw()


func _one_finger(down: bool, screen: Vector2, mouse: bool = false) -> void:
	_presses += 1
	if down:
		_touch_input = not mouse
		_pressed_at = screen
		_dragging = false
		_long_pressed = false
		_gesture_cancelled = false
		_pinch_start = {}
		if not mouse:
			get_tree().create_timer(LONG_PRESS).timeout.connect(_long_press.bind(_presses))
		press(_to_world(screen), mouse)
	elif not _gesture_cancelled and _pinch_start.is_empty() and not _long_pressed:
		release(_to_world(screen), _dragging, mouse)


func _cancel_one_finger() -> void:
	_presses += 1
	_gesture_cancelled = true
	if doc.editing():
		doc.cancel_edit()
	if _inserted_wall_point:
		selection = _selection_before_insert
	_held = {}
	_active_body_handle = {}
	_press_ref = {}
	_moving = false
	_dragging = false
	_inserted_wall_point = false
	_selection_before_insert = {}
	_refresh()


## A finger held on a thing opens its context menu without completing the tool press.
func _long_press(press_number: int) -> void:
	if press_number != _presses or _dragging or _gesture_cancelled or not _pinch_start.is_empty() or _menu_panel != null:
		return
	if _press_ref.is_empty():
		return
	var target: Dictionary = {"type": "wall", "index": _press_ref.index} if _inserted_wall_point else _menu_target(_press_ref)
	if target.is_empty():
		return
	_long_pressed = true
	_touches.clear()
	if doc.editing():
		doc.cancel_edit()
	if _inserted_wall_point:
		selection = _selection_before_insert.duplicate()
	_inserted_wall_point = false
	_selection_before_insert = {}
	_refresh()
	_held = {}
	_active_body_handle = {}
	_moving = false
	_press_ref = {}
	_show_context_menu(target, _pressed_at, true)



## Walls, the start and the goal snap to the grid; everything else goes exactly where it is put.
func _place_at(world: Vector2, kind: String) -> Vector2:
	return LevelDoc.snap(world, fine_snap) if kind in ["wall", "wall_point", "start", "goal", "ship"] else world.round()


func _to_world(screen: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * screen


func _to_screen(world: Vector2) -> Vector2:
	return get_viewport().canvas_transform * world


func _free_canvas_rect() -> Rect2:
	var viewport: Rect2 = get_viewport_rect()
	var top: float = 0.0
	var bottom: float = viewport.size.y
	if is_instance_valid(_top_bar):
		top = maxf(top, _top_bar.get_global_rect().end.y)
	if is_instance_valid(_wall_bar) and _wall_bar.is_visible_in_tree():
		top = maxf(top, _wall_bar.get_global_rect().end.y)
	if is_instance_valid(_pickup_bar) and _pickup_bar.is_visible_in_tree():
		top = maxf(top, _pickup_bar.get_global_rect().end.y)
	if is_instance_valid(_error_label):
		bottom = minf(bottom, _error_label.get_global_rect().position.y)
	if is_instance_valid(_hint_backing):
		bottom = minf(bottom, _hint_backing.get_global_rect().position.y)
	if is_instance_valid(_palette):
		bottom = minf(bottom, _palette.get_global_rect().position.y)
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var keyboard_height: float = float(DisplayServer.virtual_keyboard_get_height())
		var screen_scale: float = absf(get_viewport().get_screen_transform().y.y)
		if keyboard_height > 0.0 and screen_scale > 0.0:
			bottom = minf(bottom, viewport.size.y - keyboard_height / screen_scale)
	var free := Rect2(Vector2(0, top), Vector2(viewport.size.x, maxf(0.0, bottom - top)))
	if OS.has_feature("mobile"):
		var safe: Rect2 = get_viewport().get_screen_transform().affine_inverse() * Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			free = free.intersection(safe)
	return free


func _layout_canvas_clip() -> void:
	if not is_instance_valid(_marks_clip) or not is_instance_valid(_camera):
		return
	var free: Rect2 = _free_canvas_rect()
	var world_position: Vector2 = _to_world(free.position)
	var world_end: Vector2 = _to_world(free.end)
	_marks_clip.position = world_position
	_marks_clip.size = (world_end - world_position).max(Vector2.ZERO)
	_marks.position = -world_position


## Rebuild the frozen preview from the data and show the level's problems.
func _refresh(rebuild_preview := true) -> void:
	if rebuild_preview:
		for old in _preview.get_children():
			old.free()
		_preview.add_child(LevelFormat.build(doc.data, PREVIEW))
	_camera.make_current()
	var problems: PackedStringArray = doc.errors()
	_error_label.text = "" if problems.is_empty() else "⚠ " + problems[0] + ("  (+%d more)" % (problems.size() - 1) if problems.size() > 1 else "")
	_marks.queue_redraw()
	_undo_button.disabled = not doc.can_undo()
	_dirty = doc.data != _saved
	_title_label.text = str(doc.data.get("title", ""))
	_state_label.text = "Unsaved" if _dirty else "Saved"
	_sync_wall_bar()
	_hint_label.text = _hint_text() + "  ·  " + ("Two fingers pan and pinch to zoom" if DisplayServer.is_touchscreen_available() else "Right-drag pans · wheel zooms")
	_layout_hint_backing()
	_layout_canvas_clip()


func _hint_text() -> String:
	if tool == "select" and selection.get("type", "") == "body":
		return "Drag Radius or Reach to resize"
	if tool == "select" and selection.get("type", "") in ["wall", "wall_point"]:
		return "+ adds a point"
	if tool == "select":
		return "Tap to select · drag to move · hold for properties" if DisplayServer.is_touchscreen_available() else str(HINTS[tool])
	if tool == "wall":
		return "Tap to add points · tap the first point to close · Done" if DisplayServer.is_touchscreen_available() else str(HINTS[tool])
	return str(HINTS[tool])


func _sync_wall_bar() -> void:
	var wall_selection: bool = selection.get("type", "") in ["wall", "wall_point"]
	_wall_bar.visible = tool == "wall" or wall_selection
	_wall_done_button.visible = doc.drawing >= 0
	var selected_kind: String = doc.data.walls[selection.index].kind if wall_selection else wall_kind
	for kind: String in _wall_buttons:
		var selected: bool = kind == selected_kind
		_wall_buttons[kind].button_pressed = selected
		_wall_checks[kind].visible = selected


func _set_wall_kind(kind: String) -> void:
	if selection.get("type", "") in ["wall", "wall_point"]:
		doc.set_property(_wall_ref(selection), "kind", kind)
	else:
		wall_kind = kind
	_refresh()

## Grid lines `step` px apart, their corner snapped to `snap_size`, over the visible area.
func _draw_grid(snap_size: float, step: float, color: Color) -> void:
	var view := get_viewport_rect().size / _camera.zoom
	var corner := (_camera.position - view / 2.0).snapped(Vector2.ONE * snap_size)
	var lines := ceili(maxf(view.x, view.y) / step) + 2
	for i in lines:
		var x := corner.x + i * step
		var y := corner.y + i * step
		_marks.draw_line(Vector2(x, corner.y - step), Vector2(x, corner.y + view.y + step), color, 1.0 / _camera.zoom.x)
		_marks.draw_line(Vector2(corner.x - step, y), Vector2(corner.x + view.x + step, y), color, 1.0 / _camera.zoom.x)


func _draw_marks() -> void:
	if fine_snap and LevelDoc.FINE_SNAP * _camera.zoom.x >= FINE_GRID_MIN_PX:
		_draw_grid(LevelDoc.FINE_SNAP, LevelDoc.FINE_SNAP, GRID_COLOR)
		_draw_grid(LevelDoc.COARSE_SNAP, LevelDoc.COARSE_SNAP, MAJOR_GRID_COLOR)
	else:
		_draw_grid(LevelDoc.COARSE_SNAP, LevelDoc.COARSE_SNAP * (1 if _camera.zoom.x >= 0.3 else 10), GRID_COLOR)
	var width: float = 2.0 / _camera.zoom.x
	for rock: Dictionary in doc.data.get("asteroids", []) + [doc.data.ship]:
		if rock.has("velocity") and not rock.has("orbit"):
			var from: Vector2 = LevelDoc._v(rock.position)
			_marks.draw_line(from, from + LevelDoc._v(rock.velocity), Color(1, 1, 1, 0.6), width)
	if doc.drawing >= 0:
		var points: Array = doc.data.walls[doc.drawing].points
		_marks.draw_circle(LevelDoc._v(points[0]), LevelDoc.CLOSE_DISTANCE / _camera.zoom.x, Color(1, 1, 1, 0.15))
	if not _hover.is_empty() and _hover != selection:
		_draw_outline(_hover, Style.INK_DIM, false)
	if not selection.is_empty():
		_draw_outline(selection, Style.ACCENT, true)
		if selection.type in ["wall", "wall_point"]:
			_draw_wall_handles(selection.index)
		elif selection.type == "body":
			_draw_body_handles(selection.index)
	if not _held.is_empty() and _moving:
		_marks.draw_arc(doc.position_of(_held), 60.0, 0.0, TAU, 32, Style.ACCENT, width)


func _draw_wall_handles(wall_index: int) -> void:
	var wall: Dictionary = doc.data.walls[wall_index]
	var points: Array = wall.points
	var zoom: float = _camera.zoom.x
	var point_radius: float = (9.0 if _touch_input else 6.0) / zoom
	var plus_radius: float = (9.0 if _touch_input else 7.0) / zoom
	for i in points.size():
		var at: Vector2 = LevelDoc._v(points[i])
		_marks.draw_circle(at, point_radius + 1.0 / zoom, Color("#080E1D"))
		_marks.draw_circle(at, point_radius, Color("#E5EFFF"))
		if selection.type == "wall_point" and selection.index == wall_index and selection.point == i:
			var selected_radius: float = (12.0 if _touch_input else 10.0) / zoom
			_marks.draw_arc(at, selected_radius, 0.0, TAU, 24, Style.ACCENT, 2.0 / zoom)
	for after in range(points.size() - 1):
		_draw_plus_handle(_wall_segment_midpoint(wall_index, after), plus_radius)
	if wall.get("closed", false) and points.size() > 1:
		_draw_plus_handle(_wall_segment_midpoint(wall_index, points.size() - 1), plus_radius)


func _draw_plus_handle(at: Vector2, radius: float) -> void:
	var zoom: float = _camera.zoom.x
	var width: float = 2.0 / zoom
	var arm: float = 4.0 / zoom
	_marks.draw_circle(at, radius, Color("#080E1D"))
	_marks.draw_arc(at, radius, 0.0, TAU, 24, Color("#E5EFFF"), width)
	_marks.draw_line(at - Vector2(arm, 0), at + Vector2(arm, 0), Color("#E5EFFF"), width)
	_marks.draw_line(at - Vector2(0, arm), at + Vector2(0, arm), Color("#E5EFFF"), width)


func _draw_body_handles(body_index: int) -> void:
	var body: Dictionary = doc.data.bodies[body_index]
	var center: Vector2 = doc.position_of({"type": "body", "index": body_index})
	var zoom: float = _camera.zoom.x
	var slop: float = (LevelDoc.HIT_SLOP if _touch_input else LevelDoc.HIT_SLOP_MOUSE) / zoom
	var radius: float = LevelFormat.body_value(body, "radius")
	var reach: float = LevelFormat.body_value(body, "reach")
	var active_role: String = ""
	if not _active_body_handle.is_empty() and _active_body_handle.index == body_index:
		active_role = _active_body_handle.role
	var inactive_color := Color("#E5EFFF")
	var radius_color: Color = Style.ACCENT if active_role == "radius" else inactive_color
	var reach_color: Color = Style.ACCENT if active_role == "reach" else inactive_color
	_draw_body_ring(center, radius, radius_color, zoom)
	_draw_body_ring(center, reach, reach_color, zoom)
	_draw_body_knob(body_index, "radius", radius, _body_handle_position(body_index, "radius", slop), active_role == "radius")
	_draw_body_knob(body_index, "reach", reach, _body_handle_position(body_index, "reach", slop), active_role == "reach")


func _draw_body_ring(center: Vector2, radius: float, color: Color, zoom: float) -> void:
	if radius <= 0.0:
		return
	_draw_dashed_arc(center, radius, Color("#080E1D"), 4.0 / zoom)
	_draw_dashed_arc(center, radius, color, 2.0 / zoom)


func _draw_dashed_arc(center: Vector2, radius: float, color: Color, width: float) -> void:
	var zoom: float = _camera.zoom.x
	var half_view: Vector2 = get_viewport_rect().size / (2.0 * zoom)
	if absf(center.distance_to(_camera.position) - radius) > half_view.length():
		return
	var dash_length: float = 8.0
	var step_angle: float = 14.0 / (radius * zoom)
	var dash_angle: float = dash_length / (radius * zoom)
	for dash in ceili(TAU / step_angle):
		var start: float = dash * step_angle
		if start >= TAU:
			break
		var finish: float = minf(start + dash_angle, TAU)
		var segments: int = maxi(2, ceili((finish - start) * radius * zoom / 3.0))
		_marks.draw_arc(center, radius, start, finish, segments, color, width, true)


func _draw_body_knob(body_index: int, role: String, radius: float, target: Vector2, active: bool) -> void:
	var zoom: float = _camera.zoom.x
	var direction: Vector2 = Vector2(1, -1).normalized() if role == "radius" else Vector2(1, 1).normalized()
	var ring_point: Vector2 = doc.position_of({"type": "body", "index": body_index}) + direction * radius
	var marker: float = (9.0 if _touch_input else 6.0) / zoom
	var width: float = 2.0 / zoom
	var color: Color = Style.ACCENT if active else Color("#E5EFFF")
	if not ring_point.is_equal_approx(target):
		_marks.draw_line(ring_point, target, Color("#080E1D"), 4.0 / zoom)
		_marks.draw_line(ring_point, target, color, 2.0 / zoom)
	_marks.draw_circle(target, marker, Color("#080E1D"))
	_marks.draw_circle(target, marker - 1.0 / zoom, color)
	_marks.draw_arc(target, marker, 0.0, TAU, 24, Color("#080E1D"), width, true)
	var body: Dictionary = doc.data.bodies[body_index]
	var value: float = LevelFormat.body_value(body, role)
	var label: String = role.capitalize()
	if active:
		label += "  %d px" % roundi(value)
	_draw_body_handle_label(target, label)


func _draw_body_handle_label(at: Vector2, text: String) -> void:
	var zoom: float = _camera.zoom.x
	var free: Rect2 = _free_canvas_rect()
	var target_screen: Vector2 = _to_screen(at)
	if not free.has_point(target_screen):
		return
	var font_size: int = roundi(20.0 / zoom)
	var font: Font = ThemeDB.get_default_theme().default_font
	var text_world: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_size: Vector2 = text_world * zoom
	var label_size: Vector2 = text_size + Vector2(12, 8)
	var gap: float = 8.0
	var label_position := target_screen + Vector2(gap, -label_size.y / 2.0)
	if label_position.x + label_size.x > free.end.x:
		label_position.x = target_screen.x - gap - label_size.x
	if label_position.y < free.position.y:
		label_position.y = target_screen.y + gap
	label_position.x = clampf(label_position.x, free.position.x, free.end.x - label_size.x)
	label_position.y = clampf(label_position.y, free.position.y, free.end.y - label_size.y)
	var label_world: Vector2 = _to_world(label_position)
	var backing := Rect2(label_world, label_size / zoom)
	_marks.draw_rect(backing, Color("#080E1D"), true)
	var baseline: Vector2 = _to_world(label_position + Vector2(6, 4 + text_size.y))
	_marks.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#E5EFFF"))



func _draw_outline(ref: Dictionary, color: Color, selected: bool) -> void:
	if ref.get("type", "") == "body_handle":
		ref = {"type": "body", "index": ref.index}
	var zoom: float = _camera.zoom.x
	if ref.type == "wall_point":
		if not selected:
			var center: Vector2 = doc.position_of(ref)
			var radius: float = 10.0 / zoom
			_marks.draw_arc(center, radius, 0.0, TAU, 24, Color("#080E1D"), 2.5 / zoom)
			_marks.draw_arc(center, radius, 0.0, TAU, 24, color, 0.8 / zoom)
		return
	var under_width: float = (5.0 if selected and ref.type == "wall" else 4.0 if selected else 2.5) / zoom
	var stroke_width: float = (2.0 if selected and ref.type == "wall" else 1.5 if selected else 0.8) / zoom
	var under_color := Color("#080E1D")
	if ref.type == "wall_handle":
		var center: Vector2 = _wall_segment_midpoint(ref.index, ref.after)
		var radius: float = (9.0 if _touch_input else 7.0) / zoom
		_marks.draw_arc(center, radius, 0.0, TAU, 24, under_color, under_width)
		_marks.draw_arc(center, radius, 0.0, TAU, 24, color, stroke_width)
		return
	if ref.type == "wall":
		var wall: Dictionary = doc.data.walls[ref.index]
		var points: Array = wall.points
		for i in range(points.size() - 1):
			var segment_start: Vector2 = LevelDoc._v(points[i])
			var segment_end: Vector2 = LevelDoc._v(points[i + 1])
			_marks.draw_line(segment_start, segment_end, under_color, under_width)
			_marks.draw_line(segment_start, segment_end, color, stroke_width)
		if wall.get("closed", false) and points.size() > 1:
			var closing_start: Vector2 = LevelDoc._v(points[-1])
			var closing_end: Vector2 = LevelDoc._v(points[0])
			_marks.draw_line(closing_start, closing_end, under_color, under_width)
			_marks.draw_line(closing_start, closing_end, color, stroke_width)
		return
	var center: Vector2 = doc.position_of(ref)
	var radius: float
	match ref.type:
		"ship":
			radius = Ship.RADIUS + 8.0
		"goal":
			radius = Goal.RADIUS + 8.0
		"body":
			radius = LevelFormat.body_value(doc.data.bodies[ref.index], "radius") + 8.0
		"asteroid":
			radius = Asteroid.RADIUS + 8.0
		"pickup":
			radius = Pickup.RADIUS + 8.0
		_:
			radius = 12.0 / zoom
	_marks.draw_arc(center, radius, 0.0, TAU, 48, under_color, under_width)
	_marks.draw_arc(center, radius, 0.0, TAU, 48, color, stroke_width)

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 1
	add_child(_ui_layer)
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	_top_bar.add_theme_constant_override("separation", 10)
	_ui_layer.add_child(_top_bar)
	_button(_top_bar, "Back", func() -> void:
		if save():
			get_tree().change_scene_to_node(MyLevelsScreen.new()))
	_undo_button = _button(_top_bar, "Undo", _undo)
	_button(_top_bar, "Settings", _open_settings)
	var fine := CheckButton.new()
	fine.text = "Fine grid"
	fine.toggled.connect(func(on: bool) -> void:
		fine_snap = on
		_marks.queue_redraw())
	_top_bar.add_child(fine)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(_title_label)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 20)
	_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(_state_label)
	_button(_top_bar, "Test", _test)
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color("#ff8a6a"))
	_error_label.add_theme_font_size_override("font_size", 20)
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_error_label)
	_error_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	_error_label.offset_top = -146
	_error_label.offset_bottom = -110
	_hint_backing = PanelContainer.new()
	_hint_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color("#080E1D")
	hint_style.set_content_margin_all(0)
	hint_style.content_margin_left = 8
	hint_style.content_margin_right = 8
	hint_style.content_margin_top = 4
	hint_style.content_margin_bottom = 4
	_hint_backing.add_theme_stylebox_override("panel", hint_style)
	_ui_layer.add_child(_hint_backing)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color("#E5EFFF"))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_backing.add_child(_hint_label)
	_wall_bar = PanelContainer.new()
	_wall_bar.add_theme_stylebox_override("panel", _opaque_panel())
	_wall_bar.hide()
	_ui_layer.add_child(_wall_bar)
	var wall_controls := HBoxContainer.new()
	wall_controls.add_theme_constant_override("separation", 8)
	_wall_bar.add_child(wall_controls)
	var wall_group := ButtonGroup.new()
	var wall_normal := _wall_button_style(false)
	var wall_selected := _wall_button_style(true)
	for kind: String in LevelFormat.WALL_KINDS:
		var button := _button(wall_controls, WALL_LABELS[kind], _set_wall_kind.bind(kind))
		button.toggle_mode = true
		button.button_group = wall_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(144.0, maxf(56.0, _dp_scale(48.0)))
		button.icon = _wall_chip(kind)
		button.add_theme_constant_override("h_separation", 8)
		button.add_theme_stylebox_override("normal", wall_normal)
		button.add_theme_stylebox_override("pressed", wall_selected)
		button.add_theme_stylebox_override("hover_pressed", wall_selected)
		var check := Label.new()
		check.text = "✓"
		check.visible = false
		check.add_theme_color_override("font_color", Style.INK)
		check.add_theme_font_size_override("font_size", 20)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		check.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
		button.add_child(check)
		_wall_buttons[kind] = button
		_wall_checks[kind] = check
	_wall_done_button = _button(wall_controls, "Done", func() -> void:
		doc.finish_wall()
		_hover = {}
		_refresh())
	_wall_done_button.custom_minimum_size.y = maxf(56.0, _dp_scale(48.0))
	_wall_done_button.hide()
	_pickup_bar = HBoxContainer.new()
	_pickup_bar.add_theme_constant_override("separation", 10)
	_pickup_bar.hide()
	_ui_layer.add_child(_pickup_bar)
	_pickup_bar.add_child(_kind_option(LevelFormat.PICKUP_KINDS, PICKUP_LABELS, pickup_kind, func(kind: String) -> void: pickup_kind = kind))
	_palette = HBoxContainer.new()
	_palette.add_theme_constant_override("separation", 6)
	_ui_layer.add_child(_palette)
	var group := ButtonGroup.new()
	for name: String in TOOLS:
		var button := _button(_palette, TOOL_LABELS[name], select_tool.bind(name))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 64)
		_tool_buttons[name] = button
	_tool_buttons.select.button_pressed = true
	_palette.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_palette.offset_left = 8
	_palette.offset_right = -8
	_palette.offset_top = -72
	_palette.offset_bottom = -8
	_wall_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_wall_bar.offset_top = 84
	_pickup_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 84)
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 10
	add_child(_modal_layer)
	_layout_hint_backing()


func _layout_hint_backing() -> void:
	if not is_instance_valid(_hint_backing) or not is_instance_valid(_palette):
		return
	var viewport: Vector2 = get_viewport_rect().size
	var max_width: float = maxf(0.0, viewport.x - 24.0)
	var font: Font = _hint_label.get_theme_font("font")
	var font_size: int = _hint_label.get_theme_font_size("font_size")
	var natural_size: Vector2 = font.get_string_size(_hint_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var width: float = minf(max_width, natural_size.x + 16.0)
	_hint_label.custom_minimum_size.x = maxf(0.0, width - 16.0)
	_hint_backing.custom_minimum_size.x = width
	var height: float = maxf(36.0, _hint_label.get_combined_minimum_size().y + 8.0)
	_hint_backing.position = Vector2(12.0, _palette.get_global_rect().position.y - height - 8.0)
	_hint_backing.size = Vector2(width, height)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 56)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(Sfx.play.bind("tap"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _wall_chip(kind: String) -> ImageTexture:
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.fill(WALL_COLORS[kind])
	return ImageTexture.create_from_image(image)


func _wall_button_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111B2E")
	style.border_color = Style.ACCENT if selected else Style.BORDER
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style

## A dropdown of `kinds`, labelled by `labels`; picking one hands its kind to `on_pick`.
func _kind_option(kinds: Array, labels: Dictionary, current: String, on_pick: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(240, 56)
	option.add_theme_font_size_override("font_size", 22)
	for kind: String in kinds:
		option.add_item(labels[kind])
	option.select(kinds.find(current))
	option.item_selected.connect(func(index: int) -> void: on_pick.call(kinds[index]))
	return option


func _test() -> void:
	if not doc.errors().is_empty():
		_error_label.modulate = Color(2, 2, 2)
		create_tween().tween_property(_error_label, "modulate", Color.WHITE, 0.5)
		return
	if not save():
		return
	_kept = {"id": level_id, "doc": doc, "view": [_camera.position, _camera.zoom]}
	Progress.open(level_id, true)


func _open_settings() -> void:
	_close_context_menu()
	_close_property_panel()
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
	label.custom_minimum_size.x = 160
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = LevelFormat.TANK_RANGE.x
	slider.max_value = LevelFormat.TANK_RANGE.y
	slider.step = 1
	slider.value = 100 if unlimited else value
	slider.editable = not unlimited
	slider.custom_minimum_size = Vector2(400, 48)
	row.add_child(slider)
	var box := _number_box(slider)
	box.editable = slider.editable
	row.add_child(box)
	var forever := CheckButton.new()
	forever.text = "Unlimited"
	forever.button_pressed = unlimited
	row.add_child(forever)
	var show := func() -> void:
		label.text = tank.capitalize() + (": ∞" if forever.button_pressed else "")
	slider.value_changed.connect(func(v: float) -> void:
		doc.set_setting(tank, int(v))
		show.call())
	forever.toggled.connect(func(on: bool) -> void:
		slider.editable = not on
		box.editable = not on
		doc.set_setting(tank, LevelFormat.UNLIMITED if on else int(slider.value))
		show.call())
	show.call()


func _menu_target(ref: Dictionary) -> Dictionary:
	match ref.get("type", ""):
		"goal":
			return {}
		"body_handle":
			return {"type": "body", "index": ref.index}
		"wall_handle":
			return {"type": "wall", "index": ref.index}
	return ref.duplicate()


func _show_context_menu(ref: Dictionary, screen: Vector2, touch := false, reclose := false, choice_group := "", options: Array = [], labels: Dictionary = {}, property := "") -> void:
	if ref.is_empty() or not find_children("*", "Overlay", true, false).is_empty():
		return
	_close_property_panel()
	_close_context_menu()
	_menu_ref = ref.duplicate()
	_menu_anchor = screen
	_menu_touch = touch
	_menu_content_height = 0.0
	var menu := PanelContainer.new()
	menu.name = "EditorContextMenu"
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.add_theme_stylebox_override("panel", _opaque_panel())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	_menu_panel = menu
	if reclose:
		_menu_add_button(rows, "Keep closed", _finish_reclose.bind(true))
		_menu_add_button(rows, "Open here", _finish_reclose.bind(false))
	elif not choice_group.is_empty():
		_menu_add_heading(rows, choice_group)
		_menu_add_button(rows, "Back", _show_context_menu.bind(ref, screen, touch))
		for option: String in options:
			_menu_add_button(rows, str(labels[option]), _set_menu_property.bind(_wall_ref(ref), property, option))
	else:
		_build_context_rows(rows, _menu_ref)
	var free: Rect2 = _free_canvas_rect()
	var width: float = minf(320.0, free.size.x)
	var height: float = minf(_menu_content_height + 32.0, free.size.y)
	menu.custom_minimum_size = Vector2(width, height)
	scroll.custom_minimum_size = Vector2(maxf(0.0, width - 32.0), maxf(0.0, height - 32.0))
	_modal_layer.add_child(menu)
	_layout_context_menu()


func _build_context_rows(rows: VBoxContainer, ref: Dictionary) -> void:
	match ref.type:
		"wall":
			_menu_add_button(rows, "Colour", _open_menu_choices.bind("Colour", LevelFormat.WALL_KINDS, WALL_LABELS, ref, "kind"))
			_menu_add_button(rows, "Delete wall", _delete_menu_thing.bind(ref))
		"wall_point":
			_menu_add_button(rows, "Remove point", _remove_menu_point.bind(ref))
			_menu_add_button(rows, "Colour", _open_menu_choices.bind("Colour", LevelFormat.WALL_KINDS, WALL_LABELS, _wall_ref(ref), "kind"))
			_menu_add_button(rows, "Delete wall", _delete_menu_thing.bind(ref))
		"body":
			var body: Dictionary = doc.data.bodies[ref.index]
			_menu_property(rows, ref, "Radius", "radius")
			_menu_property(rows, ref, "Mass", "mass")
			_menu_property(rows, ref, "Reach", "reach")
			if body.kind == "planet":
				var destructible := CheckButton.new()
				destructible.text = "Destructible"
				destructible.button_pressed = body.get("destructible", false)
				destructible.flat = true
				destructible.alignment = HORIZONTAL_ALIGNMENT_LEFT
				destructible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				destructible.custom_minimum_size = Vector2(0, _menu_row_height())
				destructible.add_theme_font_size_override("font_size", _menu_font_size())
				destructible.toggled.connect(_set_destructible.bind(ref))
				rows.add_child(destructible)
				_menu_content_height += _menu_row_height()
				_menu_property(rows, ref, "Health", "health")
			_menu_add_button(rows, "Delete", _delete_menu_thing.bind(ref))
		"asteroid":
			if doc.data.asteroids[ref.index].has("orbit"):
				_menu_property(rows, ref, "Orbit speed", "orbit_speed")
			_menu_add_button(rows, "Delete", _delete_menu_thing.bind(ref))
		"pickup":
			_menu_add_button(rows, "Kind", _open_menu_choices.bind("Kind", LevelFormat.PICKUP_KINDS, PICKUP_LABELS, ref, "kind"))
			_menu_add_button(rows, "Delete", _delete_menu_thing.bind(ref))
		"ship":
			_menu_add_button(rows, "Start motion", _open_property_panel.bind(ref, "start_motion"))


func _open_menu_choices(group: String, options: Array, labels: Dictionary, ref: Dictionary, property: String) -> void:
	_show_context_menu(ref, _menu_anchor, _menu_touch, false, group, options, labels, property)

func _menu_property(rows: VBoxContainer, ref: Dictionary, label: String, property: String) -> void:
	_menu_add_button(rows, label, _open_property_panel.bind(ref, property))


func _menu_add_heading(rows: VBoxContainer, text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", Style.INK_DIM)
	heading.add_theme_font_size_override("font_size", _menu_font_size())
	heading.custom_minimum_size.y = _dp_scale(20.0)
	rows.add_child(heading)
	_menu_content_height += heading.custom_minimum_size.y


func _menu_add_button(rows: VBoxContainer, text: String, action: Callable) -> Button:
	if text in ["Delete", "Delete wall"]:
		var separator := ColorRect.new()
		separator.color = Style.BORDER
		separator.custom_minimum_size.y = 1
		separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(separator)
		_menu_content_height += 1.0
	var button := _button(rows, text, action)
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, _menu_row_height())
	button.add_theme_font_size_override("font_size", _menu_font_size())
	if text in ["Delete", "Delete wall"]:
		button.add_theme_color_override("font_color", Color("#ff8a6a"))
	_menu_content_height += _menu_row_height()
	return button




func _menu_row_height() -> float:
	return maxf(56.0, _dp_scale(48.0))


func _menu_font_size() -> int:
	return roundi(maxf(20.0, _dp_scale(16.0)))


func _dp_scale(points: float) -> float:
	return points * _ui_scale


func _opaque_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#080E1D")
	style.border_color = Style.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	return style


func _layout_context_menu() -> void:
	if not is_instance_valid(_menu_panel):
		return
	var free: Rect2 = _free_canvas_rect()
	var size: Vector2 = _menu_panel.custom_minimum_size
	var gap: float = 24.0 if _menu_touch else 8.0
	var position: Vector2
	if _menu_touch:
		position = Vector2(_menu_anchor.x - size.x / 2.0, _menu_anchor.y - gap - size.y)
		if position.y < free.position.y:
			position = Vector2(_menu_anchor.x + gap, _menu_anchor.y - size.y / 2.0)
			if position.x + size.x > free.end.x:
				position.x = _menu_anchor.x - gap - size.x
	else:
		position = _menu_anchor + Vector2(gap, gap)
	position.x = clampf(position.x, free.position.x, maxf(free.position.x, free.end.x - size.x))
	position.y = clampf(position.y, free.position.y, maxf(free.position.y, free.end.y - size.y))
	_menu_panel.position = position
	_menu_panel.size = size


func _close_context_menu() -> void:
	if is_instance_valid(_menu_panel):
		_menu_panel.hide()
		_menu_panel.queue_free()
	_menu_panel = null
	_menu_ref = {}


func _wall_ref(ref: Dictionary) -> Dictionary:
	return {"type": "wall", "index": ref.index} if ref.type == "wall_point" else ref


func _set_menu_property(ref: Dictionary, property: String, value: Variant) -> void:
	_close_context_menu()
	doc.set_property(ref, property, value)
	_refresh()


func _set_destructible(enabled: bool, ref: Dictionary) -> void:
	_close_context_menu()
	doc.begin_edit()
	doc.set_property(ref, "destructible", enabled)
	if enabled and not doc.data.bodies[ref.index].has("health"):
		doc.set_property(ref, "health", 100)
	doc.end_edit()
	_refresh()


func _delete_menu_thing(ref: Dictionary) -> void:
	_close_context_menu()
	doc.erase(_wall_ref(ref) if ref.type == "wall_point" else ref)
	selection = {}
	_hover = {}
	_refresh()


func _remove_menu_point(ref: Dictionary) -> void:
	var screen: Vector2 = _menu_anchor
	var touch: bool = _menu_touch
	var wall: Dictionary = doc.data.walls[ref.index]
	_close_context_menu()
	if wall.get("closed", false) and wall.points.size() >= 4:
		_show_context_menu(ref, screen, touch, true)
		return
	doc.erase(ref)
	selection = {}
	_hover = {}
	_refresh()


func _finish_reclose(keep_closed: bool) -> void:
	var ref: Dictionary = _menu_ref.duplicate()
	_close_context_menu()
	doc.erase(ref, keep_closed)
	selection = {}
	_hover = {}
	_refresh()


func _panel_thing_name(ref: Dictionary) -> String:
	match ref.type:
		"body":
			return str(doc.data.bodies[ref.index].kind).replace("_", " ").capitalize()
		"asteroid":
			return "Asteroid"
		"ship":
			return "Start"
	return "Thing"


func _open_property_panel(ref: Dictionary, property: String) -> void:
	_close_context_menu()
	_close_property_panel()
	_panel_ref = ref.duplicate()
	_panel_property = property
	var title := ""
	var help := ""
	var field := ""
	var bounds := Vector2.ZERO
	var step := 1.0
	var value := 0.0
	match property:
		"radius", "mass", "reach", "health":
			var body: Dictionary = doc.data.bodies[ref.index]
			var limits: Dictionary = LevelFormat.KIND_LIMITS[body.kind]
			_panel_radius = clampf(LevelFormat.body_value(body, "radius"), limits.radius.x, limits.radius.y)
			_panel_mass = clampf(LevelFormat.total_pull(body), limits.total_pull.x, limits.total_pull.y)
			match property:
				"radius":
					title = "Radius"
					help = "px"
					field = "radius"
					bounds = limits.radius
					value = _panel_radius
				"mass":
					title = "Mass"
					help = "Pull at 100 m (px/s²)"
					field = "mass"
					bounds = limits.total_pull
					step = 0.1
					value = _panel_mass
				"reach":
					title = "Reach"
					help = "px"
					field = "reach"
					bounds = limits.reach
					value = LevelFormat.body_value(body, property)
				"health":
					title = "Health"
					help = "hit points"
					field = "health"
					bounds = Vector2(1, 1000)
					value = float(body.get("health", 100))
		"orbit_speed":
			title = "Orbit speed"
			help = "rad/s · negative = clockwise"
			field = "orbit_speed"
			bounds = Vector2(-3, 3)
			step = 0.1
			value = float(doc.data.asteroids[ref.index].orbit.get("speed", LevelDoc.ORBIT_SPEED))
		"start_motion":
			title = "Start motion"
			help = "Direction and speed"
			var velocity: Vector2 = LevelDoc._v(doc.data.ship.get("velocity", [0, 0]))
			_panel_direction = roundf(rad_to_deg(velocity.angle()))
			_panel_speed = clampf(roundf(velocity.length()), 0.0, Tuning.max_speed)
		_:
			return
	var free: Rect2 = _free_canvas_rect()
	var window_height: int = DisplayServer.window_get_size().y
	var compact: bool = DisplayServer.is_touchscreen_available() or (window_height > 0 and window_height <= 600)
	if property == "start_motion":
		title = "Start motion"
	else:
		title = "%s %s" % [_panel_thing_name(ref), title.to_lower()]
		if not help.is_empty() and not compact:
			title += " (%s)" % help
			help = ""
	var width: float = minf(400.0, free.size.x)
	var row_height: float = _menu_row_height()
	var font_size: int = _menu_font_size()
	var small_font_size: int = roundi(maxf(14.0, _dp_scale(14.0)))
	var panel := EditorPropertyPanel.new()
	var number_box_factory: Callable = _number_box.bind(row_height, font_size, maxf(100.0, row_height * 1.5))
	panel.name = "EditorPropertyPanel"
	panel.build(title, help, width, row_height, font_size, small_font_size)
	panel.value_changed.connect(_apply_panel_value)
	panel.close_requested.connect(_close_property_panel)
	if property == "start_motion":
		panel.add_numeric("direction", "Direction (degrees)", Vector2(-180, 180), 1, _panel_direction, row_height, font_size, number_box_factory)
		panel.add_numeric("speed", "Speed (px/s)", Vector2(0, Tuning.max_speed), 1, _panel_speed, row_height, font_size, number_box_factory)
	else:
		panel.add_numeric(field, "", bounds, step, value, row_height, font_size, number_box_factory)
	_property_panel = panel
	doc.begin_edit()
	_modal_layer.add_child(panel)
	_position_property_panel(ref, free)
	Style.focus_first(panel)


func _panel_extent(ref: Dictionary, center: Vector2) -> float:
	var extent: float
	match ref.type:
		"body":
			var body: Dictionary = doc.data.bodies[ref.index]
			extent = LevelDoc.drawn_radius(body) * _camera.zoom.x
			for role: String in ["radius", "reach"]:
				var knob: Vector2 = _to_screen(_body_handle_position(ref.index, role, LevelDoc.HIT_SLOP / _camera.zoom.x))
				extent = maxf(extent, center.distance_to(knob) + 12.0)
		"asteroid":
			extent = Asteroid.RADIUS * 1.2 * _camera.zoom.x
		"ship":
			extent = Ship.RADIUS * 1.4 * _camera.zoom.x
		_:
			extent = 0.0
	return extent


func _position_property_panel(ref: Dictionary, free: Rect2) -> void:
	var size: Vector2 = _property_panel.get_combined_minimum_size()
	size.x = minf(400.0, free.size.x)
	size.y = minf(_property_panel.preferred_height(), free.size.y)
	_property_panel.size = size
	var target: Vector2 = _to_screen(doc.position_of(ref))
	var position: Vector2
	if free.has_point(target):
		var extent: float = _panel_extent(ref, target)
		var gap := 16.0
		var right: Vector2 = Vector2(target.x + extent + gap, target.y - size.y / 2.0)
		var left: Vector2 = Vector2(target.x - extent - gap - size.x, target.y - size.y / 2.0)
		if right.x + size.x <= free.end.x:
			position = right
		elif left.x >= free.position.x:
			position = left
		else:
			var right_room: float = free.end.x - right.x
			var left_room: float = target.x - extent - gap - free.position.x
			position = right if right_room >= left_room else left
	else:
		var corners: Array[Vector2] = [
			free.position,
			Vector2(free.end.x - size.x, free.position.y),
			Vector2(free.position.x, free.end.y - size.y),
			free.end - size,
		]
		position = corners[0]
		var nearest: float = INF
		for corner: Vector2 in corners:
			var distance: float = target.distance_to(corner + size / 2.0)
			if distance < nearest:
				nearest = distance
				position = corner
	position.x = clampf(position.x, free.position.x, maxf(free.position.x, free.end.x - size.x))
	position.y = clampf(position.y, free.position.y, maxf(free.position.y, free.end.y - size.y))
	_property_panel.position = position




func _apply_panel_value(field: String, value: float) -> void:
	if _panel_ref.is_empty() or not is_finite(value):
		return
	var ref: Dictionary = _panel_ref
	match _panel_property:
		"radius", "mass":
			var body: Dictionary = doc.data.bodies[ref.index]
			var limits: Dictionary = LevelFormat.KIND_LIMITS[body.kind]
			if field == "radius":
				if value < limits.radius.x or value > limits.radius.y:
					return
				_panel_radius = value
			elif field == "mass":
				if value < limits.total_pull.x or value > limits.total_pull.y:
					return
				_panel_mass = value
			doc.set_property(ref, "radius", _panel_radius)
			doc.set_property(ref, "strength", _panel_mass / pow(_panel_radius / 1000.0, 2))
		"reach":
			var body: Dictionary = doc.data.bodies[ref.index]
			var bounds: Vector2 = LevelFormat.KIND_LIMITS[body.kind].reach
			if value < bounds.x or value > bounds.y:
				return
			doc.set_property(ref, "reach", value)
		"health":
			if value < 1.0 or value > 1000.0:
				return
			doc.set_property(ref, "health", value)
		"orbit_speed":
			if value < -3.0 or value > 3.0:
				return
			var orbit: Dictionary = doc.data.asteroids[ref.index].orbit.duplicate(true)
			orbit.speed = value
			doc.set_property(ref, "orbit", orbit)
		"start_motion":
			if field == "direction":
				if value < -180.0 or value > 180.0:
					return
				_panel_direction = value
			elif field == "speed":
				if value < 0.0 or value > Tuning.max_speed:
					return
				_panel_speed = value
			doc.set_setting("velocity", LevelDoc._p(Vector2.from_angle(deg_to_rad(_panel_direction)) * _panel_speed))
	_refresh()


func _close_property_panel() -> void:
	var was_open: bool = is_instance_valid(_property_panel)
	if was_open:
		_property_panel.hide()
		_property_panel.queue_free()
	_property_panel = null
	_panel_ref = {}
	_panel_property = ""
	if doc.editing():
		doc.end_edit()
	if was_open:
		_refresh()


## A box for typing `slider`'s value exactly; it shares the slider's value, bounds and step.
func _number_box(slider: Range, height: float = 48.0, font_size: int = 24, width: float = 200.0) -> SpinBox:
	var box := SpinBox.new()
	box.custom_minimum_size = Vector2(width, height)
	box.allow_greater = true
	box.allow_lesser = true
	box.add_theme_font_size_override("font_size", font_size)
	slider.allow_greater = true
	slider.allow_lesser = true
	slider.share(box)
	return box


## Android Back lets the OS dismiss its keyboard, then closes a menu or panel before leaving.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.virtual_keyboard_get_height() > 0:
		return
	var overlays: Array[Node] = find_children("*", "Overlay", true, false)
	if not overlays.is_empty():
		(overlays[0] as Overlay).close()
		return
	if _menu_panel != null:
		_close_context_menu()
		return
	if _property_panel != null:
		_close_property_panel()
		return
	if save():
		get_tree().change_scene_to_node(MyLevelsScreen.new())
