class_name LevelDoc
extends RefCounted
## A level being edited: level-format data plus undoable editing operations.
## A reference ("ref") to a thing in the level is {"type": ..., "index": i[, "point": k]}, with
## type one of ship, goal, wall, wall_point, body, asteroid, pickup.

const FINE_SNAP := 10.0  # px: 1 m
const COARSE_SNAP := 100.0  # px: 10 m
const CLOSE_DISTANCE := 20.0  # screen px: the editor divides it by the zoom; tapping this near a wall's first point closes it
const HIT_SLOP := 40.0  # screen px of finger tolerance when picking things; the editor scales it by zoom
const ORBIT_SPEED := 0.8  # rad/s for a new orbiting asteroid
const UNDO_LIMIT := 50

var data: Dictionary
## Index of the wall being drawn, or -1.
var drawing := -1
var _history: Array[Dictionary] = []


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
	_remember()
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
func add_wall_point(at: Vector2, kind := "blue", close := CLOSE_DISTANCE) -> void:
	_remember()
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


## The thing under `at`, nearest first in this order: wall points, start, goal, asteroids, pickups,
## bodies, wall segments. Empty when nothing is there. `slop` is the pick tolerance in world
## px; wall points get 1.5 x slop so they win near misses.
func hit(at: Vector2, slop := HIT_SLOP) -> Dictionary:
	var walls: Array = data.get("walls", [])
	for i in walls.size():
		for k in walls[i].points.size():
			if _v(walls[i].points[k]).distance_to(at) <= slop * 1.5:
				return {"type": "wall_point", "index": i, "point": k}
	if _v(data.ship.position).distance_to(at) <= slop:
		return {"type": "ship", "index": 0}
	if _v(data.goal.position).distance_to(at) <= Goal.RADIUS:
		return {"type": "goal", "index": 0}
	for type: String in ["asteroid", "pickup"]:
		var list: Array = data.get(type + "s", [])
		for i in list.size():
			if _v(list[i].position).distance_to(at) <= slop:
				return {"type": type, "index": i}
	var bodies: Array = data.get("bodies", [])
	for i in bodies.size():
		if _v(bodies[i].position).distance_to(at) <= LevelFormat.body_value(bodies[i], "radius") + slop:
			return {"type": "body", "index": i}
	for i in walls.size():
		var points: Array = walls[i].points
		for k in points.size() - 1:
			if Geometry2D.get_closest_point_to_segment(at, _v(points[k]), _v(points[k + 1])).distance_to(at) <= slop:
				return {"type": "wall", "index": i}
	return {}


## Where `ref` is: its position, a wall point, or a wall's first point.
func position_of(ref: Dictionary) -> Vector2:
	match ref.type:
		"ship": return _v(data.ship.position)
		"goal": return _v(data.goal.position)
		"wall_point": return _v(data.walls[ref.index].points[ref.point])
		"wall": return _v(data.walls[ref.index].points[0])
	return _v(_entry(ref).position)


## Move `ref` to `at`; a whole wall moves by its first point. Call `begin_move` once per drag.
func move(ref: Dictionary, at: Vector2) -> void:
	match ref.type:
		"ship": data.ship.position = _p(at)
		"goal": data.goal.position = _p(at)
		"wall_point": data.walls[ref.index].points[ref.point] = _p(at)
		"wall":
			var shift := at - _v(data.walls[ref.index].points[0])
			data.walls[ref.index].points = data.walls[ref.index].points.map(func(p: Array) -> Array: return _p(_v(p) + shift))
		_:
			_entry(ref).position = _p(at)


## Start a drag: remembered once, so one drag is one undo step.
func begin_move() -> void:
	_remember()


## Removes `ref`. A point taken from a closed wall keeps it closed when `reclose` and three or more points remain; otherwise the wall opens at the gap, starting from the removed point's next neighbour.
func erase(ref: Dictionary, reclose := true) -> void:
	if ref.type in ["ship", "goal"]:
		return  # every level needs both
	_remember()
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
	_remember()
	_entry(ref)[key] = value


## Title, hint, show_velocity, or the ship's fuel and hull (a number or LevelFormat.UNLIMITED).
func set_setting(key: String, value: Variant) -> void:
	_remember()
	if key in ["fuel", "hull"]:
		data.ship[key] = value
	elif key == "hint" and value == "":
		data.erase("hint")
	else:
		data[key] = value


func can_undo() -> bool:
	return not _history.is_empty()


func undo() -> void:
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


func _remember() -> void:
	_history.append(data.duplicate(true))
	if _history.size() > UNDO_LIMIT:
		_history.pop_front()


static func _p(at: Vector2) -> Array:
	return [roundi(at.x), roundi(at.y)]


static func _v(p: Array) -> Vector2:
	return Vector2(p[0], p[1])
