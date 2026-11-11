class_name LevelDoc
extends RefCounted
## A level being edited: level-format data plus undoable editing operations.
## A reference ("ref") to a thing in the level is {"type": ..., "index": i[, "point": k]}, with
## type one of ship, goal, wall, wall_point, body, asteroid, pickup.

const FINE_SNAP := 10.0  # px: 1 m
const COARSE_SNAP := 100.0  # px: 10 m
const CLOSE_DISTANCE := 20.0  # screen px: the editor divides it by the zoom; tapping this near a wall's first point closes it
const HIT_SLOP := 40.0  # viewport units of finger tolerance when picking things; the editor scales it by zoom

const HIT_SLOP_MOUSE := 14.0  # viewport units, mouse
const ORBIT_SPEED := 0.8  # rad/s for a new orbiting asteroid
const UNDO_LIMIT := 50

var data: Dictionary
## Index of the wall being drawn, or -1.
var drawing: int = -1
var _history: Array[Dictionary] = []
var _editing: bool = false
var _edit_recorded: bool = false
var _edit_snapshot: Dictionary = {}
var _edit_pruned_snapshot: Dictionary = {}
var _edit_pruned: bool = false


func _init(level: Dictionary = {}) -> void:
	data = level.duplicate(true) if not level.is_empty() else blank()


static func blank() -> Dictionary:
	return {"format": LevelFormat.FORMAT, "version": LevelFormat.VERSION, "title": "My level",
		"ship": {"position": [0, 0], "fuel": 100, "hull": 100}, "goal": {"position": [2000, 0]}}


static func snap(at: Vector2, fine := false) -> Vector2:
	return at.snapped(Vector2.ONE * (FINE_SNAP if fine else COARSE_SNAP))


## Place a body ("planet", "black_hole", "star"), an asteroid, or a pickup ("thrust_up", ...).
## An asteroid dropped on a planet's orbit ring orbits it.
func place(kind: String, at: Vector2) -> Dictionary:
	_record()
	if kind in LevelFormat.BODY_KINDS:
		data.get_or_add("bodies", []).append({"kind": kind, "position": _p(at)})
		return {"type": "body", "index": data.bodies.size() - 1}
	if kind in LevelFormat.PICKUP_KINDS:
		data.get_or_add("pickups", []).append({"kind": kind, "position": _p(at)})
		return {"type": "pickup", "index": data.pickups.size() - 1}
	assert(kind == "asteroid", "unknown thing to place: %s" % kind)
	var rock := {"position": _p(at)}
	var bodies: Array = data.get("bodies", [])
	for i in bodies.size():
		var body: Dictionary = bodies[i]
		var distance := _v(body.position).distance_to(at)
		if body.kind == "planet" and distance > LevelFormat.body_value(body, "radius") + Asteroid.RADIUS * 2.0 and distance <= LevelFormat.body_value(body, "reach"):
			rock.orbit = {"body": i, "radius": roundi(distance), "speed": ORBIT_SPEED, "angle": snappedf((at - _v(body.position)).angle(), 0.0001)}
			break
	data.get_or_add("asteroids", []).append(rock)
	return {"type": "asteroid", "index": data.asteroids.size() - 1}


## Add a point to the wall being drawn, starting a new wall of `kind` if none is. Tapping near
## the first point of a wall with three or more points closes it and ends the wall.
func add_wall_point(at: Vector2, kind: String = "blue", close: float = CLOSE_DISTANCE) -> void:
	_record()
	if drawing < 0:
		data.get_or_add("walls", []).append({"kind": kind, "points": [_p(at)]})
		drawing = data.walls.size() - 1
		return
	var wall: Dictionary = data.walls[drawing]
	if wall.points.size() >= 3 and _v(wall.points[0]).distance_to(at) <= close:
		wall.closed = true
		drawing = -1
		return
	wall.points.append(_p(at))


## End the wall being drawn; a wall with a single point is dropped.
func finish_wall() -> void:
	if drawing >= 0 and data.walls[drawing].points.size() < 2:
		data.walls.remove_at(drawing)
	drawing = -1


## Geometry pick in four groups: points, bodies, wall segments, then goal. First group with a
## candidate in reach wins; nearest within a group wins and ties keep list order. `slop` is world px.
func hit(at: Vector2, slop: float = HIT_SLOP) -> Dictionary:
	var walls: Array = data.get("walls", [])
	var picked: Dictionary = {}
	var nearest: float = INF
	var distance: float = INF
	for point_wall_index: int in walls.size():
		var wall_points: Array = walls[point_wall_index].points
		for point_index: int in wall_points.size():
			distance = _v(wall_points[point_index]).distance_to(at)
			if distance <= slop and distance < nearest:
				nearest = distance
				picked = {"type": "wall_point", "index": point_wall_index, "point": point_index}
	distance = _v(data.ship.position).distance_to(at)
	if distance <= slop and distance < nearest:
		nearest = distance
		picked = {"type": "ship", "index": 0}
	var asteroids: Array = data.get("asteroids", [])
	for asteroid_index: int in asteroids.size():
		distance = _v(asteroids[asteroid_index].position).distance_to(at)
		if distance <= slop and distance < nearest:
			nearest = distance
			picked = {"type": "asteroid", "index": asteroid_index}
	var pickups: Array = data.get("pickups", [])
	for pickup_index: int in pickups.size():
		distance = _v(pickups[pickup_index].position).distance_to(at)
		if distance <= slop and distance < nearest:
			nearest = distance
			picked = {"type": "pickup", "index": pickup_index}
	if not picked.is_empty():
		return picked
	var bodies: Array = data.get("bodies", [])
	nearest = INF
	for body_index: int in bodies.size():
		var body: Dictionary = bodies[body_index]
		distance = _v(body.position).distance_to(at)
		if distance <= drawn_radius(body) + slop and distance < nearest:
			nearest = distance
			picked = {"type": "body", "index": body_index}
	if not picked.is_empty():
		return picked
	nearest = INF
	for segment_wall_index: int in walls.size():
		var wall: Dictionary = walls[segment_wall_index]
		var segment_points: Array = wall.points
		for segment_index: int in range(maxi(segment_points.size() - 1, 0)):
			distance = Geometry2D.get_closest_point_to_segment(at, _v(segment_points[segment_index]), _v(segment_points[segment_index + 1])).distance_to(at)
			if distance <= slop and distance < nearest:
				nearest = distance
				picked = {"type": "wall", "index": segment_wall_index}
		if wall.get("closed", false) and segment_points.size() > 1:
			distance = Geometry2D.get_closest_point_to_segment(at, _v(segment_points[-1]), _v(segment_points[0])).distance_to(at)
			if distance <= slop and distance < nearest:
				nearest = distance
				picked = {"type": "wall", "index": segment_wall_index}
	if not picked.is_empty():
		return picked
	if _v(data.goal.position).distance_to(at) <= Goal.RADIUS:
		return {"type": "goal", "index": 0}
	return {}



## How far a body's drawing reaches from its centre: a star's corona and prominences, a black
## hole's accretion disk, a planet's atmosphere (see GravityBody._draw).
static func drawn_radius(body: Dictionary) -> float:
	var r := LevelFormat.body_value(body, "radius")
	match body.kind:
		"star": return maxf(r * 1.36, r + GravityBody.PROMINENCE_SIZE.y)
		"black_hole": return r * 1.79
	return r + 7.0


## Where `ref` is: its position, a wall point, or a wall's first point.
func position_of(ref: Dictionary) -> Vector2:
	match ref.type:
		"ship": return _v(data.ship.position)
		"goal": return _v(data.goal.position)
		"wall_point": return _v(data.walls[ref.index].points[ref.point])
		"wall": return _v(data.walls[ref.index].points[0])
	return _v(_entry(ref).position)


## Move `ref` to `at`; actual changes record through `_record()`.
func move(ref: Dictionary, at: Vector2) -> void:
	if ref.type == "wall_point":
		var point_wall_points: Array = data.walls[ref.index].points
		var point_position: Array = _p(at)
		if point_wall_points[ref.point] == point_position:
			return
		_record()
		point_wall_points[ref.point] = point_position
	elif ref.type == "wall":
		var whole_wall_points: Array = data.walls[ref.index].points
		var shift: Vector2 = at - _v(whole_wall_points[0])
		var changed: bool = false
		for check_index: int in whole_wall_points.size():
			if _p(_v(whole_wall_points[check_index]) + shift) != whole_wall_points[check_index]:
				changed = true
				break
		if not changed:
			return
		_record()
		for move_index: int in whole_wall_points.size():
			whole_wall_points[move_index] = _p(_v(whole_wall_points[move_index]) + shift)
	else:
		var entry: Dictionary = _entry(ref)
		var entry_position: Array = _p(at)
		if entry.position == entry_position:
			return
		_record()
		entry.position = entry_position


func begin_edit() -> void:
	if _editing:
		return
	_editing = true
	_edit_recorded = false
	_edit_snapshot = {}
	_edit_pruned_snapshot = {}
	_edit_pruned = false


func end_edit() -> void:
	_editing = false
	_edit_recorded = false
	_edit_snapshot = {}
	_edit_pruned_snapshot = {}
	_edit_pruned = false


func cancel_edit() -> void:
	if _edit_recorded:
		data = _edit_snapshot
		_history.pop_back()
		if _edit_pruned:
			_history.push_front(_edit_pruned_snapshot)
	end_edit()


func editing() -> bool:
	return _editing




## Removes `ref`. A point taken from a closed wall keeps it closed when `reclose` and three or more points remain; otherwise the wall opens at the gap, starting from the removed point's next neighbour.
func erase(ref: Dictionary, reclose := true) -> void:
	if ref.type in ["ship", "goal"]:
		return  # every level needs both
	_record()
	match ref.type:
		"wall_point":
			var wall: Dictionary = data.walls[ref.index]
			var points: Array = wall.points
			points.remove_at(ref.point)
			if points.size() < 2:
				data.walls.remove_at(ref.index)
			elif wall.get("closed", false) and not (reclose and points.size() >= 3):
				var at: int = ref.point % points.size()  # the next neighbour; wraps past the last point
				wall.points = points.slice(at) + points.slice(0, at)
				wall.erase("closed")
		"wall":
			data.walls.remove_at(ref.index)
		"body":
			data.bodies.remove_at(ref.index)
			for rock in data.get("asteroids", []):  # orbits follow the bodies' new indices
				if rock.has("orbit"):
					if rock.orbit.body == ref.index:
						rock.erase("orbit")
					elif rock.orbit.body > ref.index:
						rock.orbit.body -= 1
		_:
			data[ref.type + "s"].remove_at(ref.index)


func set_property(ref: Dictionary, key: String, value: Variant) -> void:
	var entry: Dictionary = _entry(ref)
	if entry.has(key) and typeof(entry[key]) == typeof(value) and entry[key] == value:
		return
	_record()
	entry[key] = value


## Title, hint, show_velocity, or the ship's fuel and hull (a number or LevelFormat.UNLIMITED) and
## velocity ([x, y] px/s; [0, 0] removes it).
func set_setting(key: String, value: Variant) -> void:
	if key == "velocity" and typeof(value) == TYPE_ARRAY and value == [0, 0]:
		if not data.ship.has("velocity"):
			return
	elif key in ["fuel", "hull", "velocity"]:
		if data.ship.has(key) and typeof(data.ship[key]) == typeof(value) and data.ship[key] == value:
			return
	elif key == "hint" and typeof(value) == TYPE_STRING and value == "":
		if not data.has("hint"):
			return
	elif data.has(key) and typeof(data[key]) == typeof(value) and data[key] == value:
		return
	_record()
	if key == "velocity" and typeof(value) == TYPE_ARRAY and value == [0, 0]:
		data.ship.erase("velocity")
	elif key in ["fuel", "hull", "velocity"]:
		data.ship[key] = value
	elif key == "hint" and typeof(value) == TYPE_STRING and value == "":
		data.erase("hint")
	else:
		data[key] = value


func can_undo() -> bool:
	return not _history.is_empty()


func undo() -> void:
	end_edit()
	if _history.is_empty():
		return
	data = _history.pop_back()
	drawing = -1


func errors() -> PackedStringArray:
	return LevelFormat.validate(data)


func _entry(ref: Dictionary) -> Dictionary:
	match ref.type:
		"wall", "wall_point": return data.walls[ref.index]
		"body": return data.bodies[ref.index]
		"asteroid": return data.asteroids[ref.index]
		"pickup": return data.pickups[ref.index]
		"ship": return data.ship
	return data.goal


func _record() -> void:
	if _editing:
		if _edit_recorded:
			return
		_edit_snapshot = data.duplicate(true)
		_history.append(_edit_snapshot)
		_edit_recorded = true
	else:
		_history.append(data.duplicate(true))
	if _history.size() > UNDO_LIMIT:
		if _editing and _edit_recorded:
			_edit_pruned_snapshot = _history.pop_front()
			_edit_pruned = true
		else:
			_history.pop_front()

static func _p(at: Vector2) -> Array:
	return [roundi(at.x), roundi(at.y)]


static func _v(p: Array) -> Vector2:
	return Vector2(p[0], p[1])
