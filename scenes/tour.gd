class_name Tour
extends Node
## A guided flyover before a level's first flight: a zoomed-out view of the whole course, the
## goal, each stop under the level's `Tour` node (Marker2D children with a "text" metadata),
## then the ship. The game is paused; the player reads each caption and taps Next.

signal finished

const OVERVIEW_TEXT := "This is the whole course. Find your ship and the green ring."
const GOAL_TEXT := "Reach the green ring to finish the course."
const SHIP_TEXT := "This is your ship. Ready?"
const FLY_SECONDS := 0.9
const SAME_PLACE := 50.0  # px
const ZOOM := Vector2(0.8, 0.8)  # a little wider than play, to show each element in context
const OVERVIEW_PADDING := 300.0  # px of space around the course in the overview
const OVERVIEW_MIN_ZOOM := 0.08

var _stops: Array = []  # [world position, caption, zoom]
var _index := -1
var _camera: Camera2D
var _label: Label
var _next: Button


## `level` must have a goal, a ship and a `Tour` node.
func _init(level: Level) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bounds := _course_bounds(level)
	_stops.append([bounds.get_center(), OVERVIEW_TEXT, _fit(bounds)])
	_stops.append([level.goal.global_position, GOAL_TEXT, ZOOM])
	for stop: Node2D in level.get_node("Tour").get_children():
		_stops.append([stop.global_position, stop.get_meta("text", ""), ZOOM])
	# A level stop already at the ship (its controls advice) is the last word; no generic one.
	if _stops.back()[0].distance_to(level.ship.global_position) > SAME_PLACE:
		_stops.append([level.ship.global_position, SHIP_TEXT, ZOOM])


## Everything the player should see in the overview: walls, bodies, the ship and the goal.
static func _course_bounds(level: Level) -> Rect2:
	var bounds := Rect2(level.ship.global_position, Vector2.ZERO).expand(level.goal.global_position)
	for wall in level.find_children("*", "Barrier", true, false):
		for point: Vector2 in wall.get_node("Shape").points:
			bounds = bounds.expand(wall.to_global(point))
	for body in level.find_children("*", "GravityBody", true, false):
		bounds = bounds.expand(body.global_position)
	return bounds.grow(OVERVIEW_PADDING)


## The camera zoom that fits `bounds` on screen.
static func _fit(bounds: Rect2) -> Vector2:
	var screen := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var zoom := minf(screen.x / bounds.size.x, screen.y / bounds.size.y)
	return Vector2.ONE * clampf(zoom, OVERVIEW_MIN_ZOOM, ZOOM.x)


func _ready() -> void:
	_camera = Camera2D.new()
	_camera.zoom = _stops[0][2]
	_camera.global_position = _stops[0][0]
	add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # touches on the card never reach the ship
	layer.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 640
	_label.add_theme_font_size_override("font_size", 28)
	column.add_child(_label)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(220, 60)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_next.add_theme_font_size_override("font_size", 26)
	_next.pressed.connect(Sfx.play.bind("tap"))
	_next.pressed.connect(next)
	column.add_child(_next)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	get_tree().paused = true
	next()


## Fly to the next stop, or end the tour after the last one.
func next() -> void:
	_index += 1
	if _index >= _stops.size():
		get_tree().paused = false
		finished.emit()
		queue_free()
		return
	_label.text = _stops[_index][1]
	_next.text = "Go!" if _index == _stops.size() - 1 else "Next"
	var seconds := 0.0 if _index == 0 else FLY_SECONDS
	var fly := create_tween().set_parallel()
	fly.tween_property(_camera, "global_position", _stops[_index][0], seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fly.tween_property(_camera, "zoom", _stops[_index][2], seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The caption on screen, for tests.
func caption() -> String:
	return _label.text


func _exit_tree() -> void:
	get_tree().paused = false  # a scene change mid-tour must not leave the next scene paused
