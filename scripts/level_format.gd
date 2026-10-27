class_name LevelFormat
extends RefCounted
## The level file format shared by the game, the in-app editor and the community server:
## versioned JSON: plain `.json` for official levels and tutorials, in the stable layout `to_json` writes, and gzip-compressed `.json.gz` for player drafts. See docs/superpowers/specs/2026-10-16-level-format-design.md.

const FORMAT := "zero-gx-level"
const VERSION := 1
const UNLIMITED := "unlimited"
const EXTENSION := ".json"
const COMPRESSED_MAGIC := "GCPF"  # the first bytes of what `FileAccess.open_compressed` writes: Godot's own container, not a standard .gz

const WALL_KINDS := ["blue", "orange", "red"]  # Barrier.Kind order
const BODY_KINDS := ["planet", "black_hole", "star"]  # GravityBody.Preset order
const PICKUP_KINDS := ["thrust_up", "thrust_down", "boost"]  # Pickup.Kind order

const MAX_BYTES := 65536
const MAX_COORD := 50000.0
const MAX_WALLS := 300
const MAX_WALL_POINTS := 64
const MAX_BODIES := 32
const MAX_ASTEROIDS := 150
const MAX_PICKUPS := 50
const MAX_TOUR := 12
const MAX_ROUTE := 64
const MAX_TITLE := 40
const MAX_TEXT := 200
const MAX_PAR := 1_000_000
const TANK_RANGE := Vector2(1, 1000)  # fuel and hull, unless unlimited
const BODY_RANGES := {"radius": Vector2(8, 3000), "strength": Vector2(0, 6000000), "reach": Vector2(0, 10000), "health": Vector2(1, 10000)}  # strength covers the heaviest, smallest black hole
## Per-kind limits, each independent of the others so radius and pull can be set apart. Total
## pull is the pull at 1000 px, which acts like mass: strength (the surface pull) is total pull
## divided by (radius / 1000)². As in reality, black holes and stars overlap in mass, but any
## black hole pulls harder at its surface than any star (at most 13,889 against at least 14,648).
const KIND_LIMITS := {
	"planet": {"radius": Vector2(32, 240), "total_pull": Vector2(0, 100), "reach": Vector2(0, 1500)},
	"star": {"radius": Vector2(600, 3000), "total_pull": Vector2(150, 5000), "reach": Vector2(0, 8000)},
	"black_hole": {"radius": Vector2(32, 64), "total_pull": Vector2(60, 6000), "reach": Vector2(0, 1500)},
}

const LEVEL_SCRIPT := preload("res://scenes/level.gd")
const SHIP := preload("res://scenes/ship.tscn")
const GOAL := preload("res://scenes/goal.tscn")
const BARRIER := preload("res://scenes/barrier.tscn")
const BODY := preload("res://scenes/gravity_body.tscn")
const ASTEROID := preload("res://scenes/asteroid.tscn")
const PICKUP := preload("res://scenes/pickup.tscn")


## Whether a fuel or hull value is the "unlimited" marker (values are otherwise numbers).
static func is_unlimited(value: Variant) -> bool:
	return value is String and value == UNLIMITED


## Reads a level file: compressed when it starts with Godot's compressed-file header (whatever its name), plain text otherwise.
static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null and file.get_length() >= COMPRESSED_MAGIC.length() and file.get_buffer(COMPRESSED_MAGIC.length()).get_string_from_ascii() == COMPRESSED_MAGIC:
		file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if file == null:
		return {}
	var json := JSON.new()  # unlike parse_string, the instance parse does not log every bad file
	return json.data if json.parse(file.get_as_text()) == OK and json.data is Dictionary else {}


## Writes a level file: gzip when the path ends in `.gz`, otherwise in the stable `to_json` layout.
static func write(path: String, data: Dictionary) -> Error:
	var gzip := path.ends_with(".gz")
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP) if gzip else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data) if gzip else to_json(data))
	return OK


## The stable file layout: sorted keys, 2-space indent, whole numbers as integers, trailing newline.
static func to_json(data: Dictionary) -> String:
	return JSON.stringify(_normalized(data), "  ", true) + "\n"


## The hash that identifies a level's content.
static func sha256(data: Dictionary) -> String:
	return to_json(data).sha256_text()


static func _normalized(value: Variant) -> Variant:
	if value is float:  # only whole numbers change form, so the hash identifies the content exactly
		return int(value) if value == roundf(value) else value
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _normalized(value[key])
		return out
	if value is Array:
		return value.map(_normalized)
	return value


## Every way `data` breaks the format's rules; empty when the level is valid. A `draft` (an
## unfinished level, which the editor accepts and shows the problems of) only has to be well
## formed: wrong types and shapes still fail, but sizes, ranges, limits and placement do not.
static func validate(data: Dictionary, draft := false) -> PackedStringArray:
	var errors := PackedStringArray()
	if not draft and JSON.stringify(data).to_utf8_buffer().size() > MAX_BYTES:
		errors.append("level is larger than %d bytes" % MAX_BYTES)
	if not data.get("format") is String or data.format != FORMAT or not (data.get("version") is float or data.get("version") is int) or int(data.version) != VERSION:
		errors.append("not a %s version %d file" % [FORMAT, VERSION])
		return errors
	var title: Variant = data.get("title")
	if not title is String or (not draft and (title.length() < 1 or title.length() > MAX_TITLE)):
		errors.append("title must be 1-%d characters" % MAX_TITLE)
	_text(data.get("hint", ""), "hint", errors, draft)
	if data.has("par") and not (_whole(data.par) and (draft or (data.par >= Progress.MIN_POINTS and data.par <= MAX_PAR))):
		errors.append("par must be a whole number from %d to %d points" % [Progress.MIN_POINTS, MAX_PAR])
	var ship: Variant = data.get("ship")
	if not ship is Dictionary:
		errors.append("missing ship")
		return errors
	_point(ship.get("position"), "ship position", errors, draft)
	_point(ship.get("velocity", [0, 0]), "ship velocity", errors, draft)
	_number(ship.get("rotation", 0), -TAU, TAU, "ship rotation", errors, draft)
	for tank: String in ["fuel", "hull"]:
		var value: Variant = ship.get(tank, 100)
		if not is_unlimited(value):
			_number(value, TANK_RANGE.x, TANK_RANGE.y, "ship %s" % tank, errors, draft)
	var goal: Variant = data.get("goal")
	if not goal is Dictionary:
		errors.append("missing goal")
	else:
		_point(goal.get("position"), "goal position", errors, draft)
	var walls := _list(data, "walls", MAX_WALLS, errors, draft)
	for i in walls.size():
		var wall: Variant = walls[i]
		if not wall is Dictionary or not wall.get("kind") in WALL_KINDS:
			errors.append("wall %d: unknown kind" % i)
			continue
		var points: Variant = wall.get("points")
		if not points is Array or (not draft and (points.size() < 2 or points.size() > MAX_WALL_POINTS)):
			errors.append("wall %d: needs 2-%d points" % [i, MAX_WALL_POINTS])
			continue
		for p in points:
			_point(p, "wall %d point" % i, errors, draft)
	var bodies := _list(data, "bodies", MAX_BODIES, errors, draft)
	for i in bodies.size():
		var body: Variant = bodies[i]
		if not body is Dictionary or not body.get("kind") in BODY_KINDS:
			errors.append("body %d: unknown kind" % i)
			continue
		var before := errors.size()
		_point(body.get("position"), "body %d position" % i, errors, draft)
		for key: String in BODY_RANGES:
			if body.has(key):
				_number(body[key], BODY_RANGES[key].x, BODY_RANGES[key].y, "body %d %s" % [i, key], errors, draft)
		if not draft and errors.size() == before:  # only well-formed numbers can be compared to the kind's limits
			_check_kind_limits(i, body, errors)
	var rocks := _list(data, "asteroids", MAX_ASTEROIDS, errors, draft)
	for i in rocks.size():
		var rock: Variant = rocks[i]
		if not rock is Dictionary:
			errors.append("asteroid %d: not an object" % i)
			continue
		_point(rock.get("position"), "asteroid %d position" % i, errors, draft)
		_point(rock.get("velocity", [0, 0]), "asteroid %d velocity" % i, errors, draft)
		var orbit: Variant = rock.get("orbit")
		if orbit != null:
			var index: Variant = orbit.get("body") if orbit is Dictionary else null
			if not (index is float or index is int) or int(index) < 0 or int(index) >= bodies.size():
				errors.append("asteroid %d: orbit names no body" % i)
	var pickups := _list(data, "pickups", MAX_PICKUPS, errors, draft)
	for i in pickups.size():
		var pickup: Variant = pickups[i]
		if not pickup is Dictionary or not pickup.get("kind") in PICKUP_KINDS:
			errors.append("pickup %d: unknown kind" % i)
			continue
		_point(pickup.get("position"), "pickup %d position" % i, errors, draft)
	var tour := _list(data, "tour", MAX_TOUR, errors, draft)
	for i in tour.size():
		if not tour[i] is Dictionary:
			errors.append("tour stop %d: not an object" % i)
			continue
		_point(tour[i].get("position"), "tour stop %d position" % i, errors, draft)
		_text(tour[i].get("text", ""), "tour stop %d text" % i, errors, draft)
	var route: Variant = data.get("route")
	if route != null:
		var points: Variant = route.get("points") if route is Dictionary else null
		if not points is Array or (not draft and points.size() > MAX_ROUTE):
			errors.append("route needs up to %d points" % MAX_ROUTE)
		else:
			for p in points:
				_point(p, "route point", errors, draft)
	if not draft and errors.is_empty():
		_check_start(data, errors)
	return errors


## A body's radius, strength or reach: its own value, or its kind's preset.
static func body_value(body: Dictionary, key: String) -> float:
	var preset: Array = GravityBody.PRESETS[BODY_KINDS.find(body.kind)]
	return body.get(key, preset[["radius", "strength", "reach"].find(key)])


## A body's pull at 1000 px: what reaches across a course.
static func total_pull(body: Dictionary) -> float:
	return body_value(body, "strength") * pow(body_value(body, "radius") / 1000.0, 2)


static func _check_kind_limits(i: int, body: Dictionary, errors: PackedStringArray) -> void:
	var limits: Dictionary = KIND_LIMITS[body.kind]
	for key: String in limits:
		var value := total_pull(body) if key == "total_pull" else body_value(body, key)
		if value < limits[key].x - 0.001 or value > limits[key].y + 0.001:
			errors.append("body %d: a %s's %s must be %s to %s" % [i, body.kind.replace("_", " "), key.replace("_", " "), limits[key].x, limits[key].y])


## The scene for `data`: a Level (or `script`, a Level subclass such as a tutorial lesson).
static func build(data: Dictionary, script: Script = LEVEL_SCRIPT) -> Level:
	var root := Node2D.new()
	root.set_script(script)
	root.name = "Level"
	root.title = data.get("title", "")
	root.hint = data.get("hint", "")
	root.show_velocity = data.get("show_velocity", false)
	root.par = int(data.get("par", 0))
	var spec: Dictionary = data.ship
	var ship: Ship = SHIP.instantiate()
	ship.name = "Ship"
	ship.position = _vec(spec.position)
	ship.rotation = spec.get("rotation", 0.0)
	ship.linear_velocity = _vec(spec.get("velocity", [0, 0]))
	var fuel: Variant = spec.get("fuel", Ship.MAX_FUEL)
	ship.fuel_unlimited = is_unlimited(fuel)
	if not ship.fuel_unlimited:
		ship.fuel = fuel
	var hull: Variant = spec.get("hull", Ship.MAX_HEALTH)
	ship.hull_unlimited = is_unlimited(hull)
	if not ship.hull_unlimited:
		ship.hull = hull
	root.add_child(ship)
	var goal: Node2D = GOAL.instantiate()
	goal.name = "Goal"
	goal.position = _vec(data.goal.position)
	root.add_child(goal)
	var walls: Array = data.get("walls", [])
	for i in walls.size():
		var wall: Barrier = BARRIER.instantiate()
		wall.name = "Wall%d" % (i + 1)
		wall.kind = WALL_KINDS.find(walls[i].kind)
		wall.closed = walls[i].get("closed", false)
		wall.get_node("Shape").points = PackedVector2Array(walls[i].points.map(_vec))
		root.add_child(wall)
	var bodies: Array = data.get("bodies", [])
	for i in bodies.size():
		var body: GravityBody = BODY.instantiate()
		body.name = "Body%d" % (i + 1)
		body.preset = BODY_KINDS.find(bodies[i].kind)
		body.position = _vec(bodies[i].position)
		for key: String in ["radius", "strength", "reach", "destructible", "health"]:
			if bodies[i].has(key):
				body.set(key, bodies[i][key])
		root.add_child(body)
	var rocks: Array = data.get("asteroids", [])
	for i in rocks.size():
		var rock: Asteroid = ASTEROID.instantiate()
		rock.name = "Rock%d" % (i + 1)
		rock.position = _vec(rocks[i].position)
		rock.linear_velocity = _vec(rocks[i].get("velocity", [0, 0]))
		var orbit: Variant = rocks[i].get("orbit")
		if orbit is Dictionary:
			rock.orbit_parent = NodePath("../Body%d" % (int(orbit.body) + 1))
			rock.orbit_radius = orbit.get("radius", rock.orbit_radius)
			rock.orbit_speed = orbit.get("speed", rock.orbit_speed)
			rock.orbit_angle = orbit.get("angle", rock.orbit_angle)
		root.add_child(rock)
	var pickups: Array = data.get("pickups", [])
	for i in pickups.size():
		var pickup: Pickup = PICKUP.instantiate()
		pickup.name = "Pickup%d" % (i + 1)
		pickup.kind = PICKUP_KINDS.find(pickups[i].kind)
		pickup.position = _vec(pickups[i].position)
		root.add_child(pickup)
	var tour: Array = data.get("tour", [])
	if not tour.is_empty():
		var tour_node := Node2D.new()
		tour_node.name = "Tour"
		for i in tour.size():
			var stop := Marker2D.new()
			stop.name = "Stop%d" % (i + 1)
			stop.position = _vec(tour[i].position)
			stop.set_meta("text", tour[i].get("text", ""))
			tour_node.add_child(stop)
		root.add_child(tour_node)
	var route: Variant = data.get("route")
	if route is Dictionary:
		var line := Line2D.new()
		line.name = "Route"
		line.visible = false
		line.points = PackedVector2Array(route.points.map(_vec))
		if route.has("cruise"):
			line.set_meta("cruise", float(route.cruise))
		if route.has("coast"):
			line.set_meta("coast", PackedInt32Array(route.coast))
		root.add_child(line)
	return root


## The data for a level scene (built or loaded, not yet in the tree): the inverse of `build`.
static func serialize(root: Node) -> Dictionary:
	var data := {"format": FORMAT, "version": VERSION, "title": root.title}
	if root.hint != "":
		data.hint = root.hint
	if root.show_velocity:
		data.show_velocity = true
	if root.par > 0:
		data.par = root.par
	var bodies: Array[Node] = root.get_children().filter(func(n: Node) -> bool: return n is GravityBody)
	for child in root.get_children():
		if child is Ship:
			var ship := {"position": _list_of(child.position)}
			if child.rotation != 0.0:
				ship.rotation = snappedf(child.rotation, 0.0001)
			if child.linear_velocity != Vector2.ZERO:
				ship.velocity = _list_of(child.linear_velocity)
			ship.fuel = UNLIMITED if child.fuel_unlimited else _num(child.fuel)
			ship.hull = UNLIMITED if child.hull_unlimited else _num(child.hull)
			data.ship = ship
		elif child is Goal:
			data.goal = {"position": _list_of(child.position)}
		elif child is Barrier:
			var points: Array = []
			for p: Vector2 in child.get_node("Shape").points:
				points.append(_list_of(child.position + p))
			var wall := {"kind": WALL_KINDS[child.kind], "points": points}
			if child.closed:
				wall.closed = true
			data.get_or_add("walls", []).append(wall)
		elif child is GravityBody:
			var body := {"kind": BODY_KINDS[child.preset], "position": _list_of(child.position)}
			for key: String in ["radius", "strength", "reach"]:
				if child.get(key) >= 0.0:
					body[key] = _num(child.get(key))
			if child.destructible:
				body.destructible = true
				body.health = _num(child.health)
			data.get_or_add("bodies", []).append(body)
		elif child is Asteroid:
			var rock := {"position": _list_of(child.position)}
			if child.linear_velocity != Vector2.ZERO:
				rock.velocity = _list_of(child.linear_velocity)
			if not child.orbit_parent.is_empty():
				var parent := child.get_node(child.orbit_parent)
				rock.orbit = {"body": bodies.find(parent), "radius": _num(child.orbit_radius), "speed": _num(child.orbit_speed), "angle": snappedf(child.orbit_angle, 0.0001)}
			data.get_or_add("asteroids", []).append(rock)
		elif child is Pickup:
			data.get_or_add("pickups", []).append({"kind": PICKUP_KINDS[child.kind], "position": _list_of(child.position)})
		elif child.name == &"Tour":
			for stop: Node2D in child.get_children():
				data.get_or_add("tour", []).append({"position": _list_of(stop.position), "text": stop.get_meta("text", "")})
		elif child.name == &"Route":
			var route := {"points": Array(child.points).map(_list_of)}
			if child.has_meta("cruise"):
				route.cruise = _num(child.get_meta("cruise"))
			if child.has_meta("coast"):
				route.coast = Array(child.get_meta("coast"))
			data.route = route
	return data


## The thumbnail sketch of a level: its shapes at one-pixel detail, under 2 KB, derived from `data`.
## With `demo`, the sketch also carries the demo's score as `par`; the caller checks that the demo was recorded on `data`.
static func sketch(data: Dictionary, demo: Demo = null) -> Dictionary:
	var box := _sketch_box(data)
	var tolerance := maxf(box.size.x, box.size.y) / 320.0  # one thumbnail pixel
	var extra := {} if demo == null else {"par": DemoCheck.score(data, demo).points}
	var out := _shape(data, box, tolerance, extra)
	for _doubling in 8:
		if _fits(out):
			break
		tolerance *= 2.0
		out = _shape(data, box, tolerance, extra)
	# shortcut: a whole kind is cut before the next, so a dense level drops every wall before any pickup, upgrade: a per-item budget
	for key in ["asteroids", "walls", "pickups", "bodies"]:
		while not _fits(out) and not out[key].is_empty():
			out[key].pop_back()
	return out


## The sketch as one line of JSON with sorted keys, so the same level always gives the same bytes.
static func sketch_json(sketch: Dictionary) -> String:
	return JSON.stringify(sketch, "", true)


static func _fits(sketch: Dictionary) -> bool:
	return sketch_json(sketch).length() < 2048


## The box around everything a level places, grown by the ship's radius.
static func _sketch_box(data: Dictionary) -> Rect2:
	var box := Rect2(_vec(data.ship.position), Vector2.ZERO)
	box = box.expand(_vec(data.goal.position))
	for wall: Dictionary in data.get("walls", []):
		for p: Array in wall.points:
			box = box.expand(_vec(p))
	for body: Dictionary in data.get("bodies", []):
		var at := _vec(body.position)
		var radius := Vector2.ONE * body_value(body, "radius")
		box = box.expand(at - radius).expand(at + radius)
	for pickup: Dictionary in data.get("pickups", []):
		box = box.expand(_vec(pickup.position))
	for rock: Dictionary in data.get("asteroids", []):
		box = box.expand(_vec(rock.position))
	return box.grow(Ship.RADIUS)


## The sketch at one simplification tolerance: every wall, body, pickup and asteroid, merged with `extra`.
static func _shape(data: Dictionary, box: Rect2, tolerance: float, extra: Dictionary) -> Dictionary:
	var walls := []
	for wall: Dictionary in data.get("walls", []):
		var points := PackedVector2Array()
		for p: Array in wall.points:
			points.append(_vec(p))
		var sketched := {"kind": wall.kind, "points": Array(_simplify(points, tolerance)).map(_int_point)}
		if wall.get("closed", false):
			sketched.closed = true
		walls.append(sketched)
	var bodies := []
	for body: Dictionary in data.get("bodies", []):
		bodies.append({"kind": body.kind, "position": _int_point(_vec(body.position)), "radius": roundi(body_value(body, "radius"))})
	var pickups := []
	for pickup: Dictionary in data.get("pickups", []):
		pickups.append({"kind": pickup.kind, "position": _int_point(_vec(pickup.position))})
	var rocks := []
	for rock: Dictionary in data.get("asteroids", []):
		rocks.append(_int_point(_vec(rock.position)))
	var lo := _int_point(box.position)
	var hi := _int_point(box.end)
	return {"bounds": [lo[0], lo[1], hi[0] - lo[0], hi[1] - lo[1]], "ship": _int_point(_vec(data.ship.position)), "goal": _int_point(_vec(data.goal.position)), "walls": walls, "bodies": bodies, "pickups": pickups, "asteroids": rocks}.merged(extra)


## Ramer–Douglas–Peucker: the points a polyline keeps within `tolerance`; its first and last always stay.
static func _simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var worst := 0.0
	var at := 0
	for i in range(1, points.size() - 1):
		var gap := Geometry2D.get_closest_point_to_segment(points[i], points[0], points[points.size() - 1]).distance_to(points[i])
		if gap > worst:
			worst = gap
			at = i
	if worst <= tolerance:
		return PackedVector2Array([points[0], points[points.size() - 1]])
	var left := _simplify(points.slice(0, at + 1), tolerance)
	var right := _simplify(points.slice(at, points.size()), tolerance)
	left.remove_at(left.size() - 1)  # the split point ends the left half and starts the right
	return left + right


static func _int_point(v: Vector2) -> Array:
	return [roundi(v.x), roundi(v.y)]


static func _check_start(data: Dictionary, errors: PackedStringArray) -> void:
	var start := _vec(data.ship.position)
	var clearance := Ship.RADIUS + Barrier.THICKNESS / 2.0
	for i in data.get("walls", []).size():
		var points: Array = data.walls[i].points
		for k in points.size() - 1:
			var gap := Geometry2D.get_closest_point_to_segment(start, _vec(points[k]), _vec(points[k + 1])).distance_to(start)
			if gap < clearance:
				errors.append("the ship starts inside wall %d" % i)
	for i in data.get("bodies", []).size():
		var body: Dictionary = data.bodies[i]
		var radius: float = body.get("radius", GravityBody.PRESETS[BODY_KINDS.find(body.kind)][0])
		if _vec(body.position).distance_to(start) < radius + Ship.RADIUS:
			errors.append("the ship starts inside body %d" % i)
	if _vec(data.goal.position).distance_to(start) < Goal.RADIUS + Ship.RADIUS:
		errors.append("the ship starts inside the goal")


static func _list(data: Dictionary, key: String, limit: int, errors: PackedStringArray, draft: bool) -> Array:
	var value: Variant = data.get(key, [])
	if not value is Array:
		errors.append("%s must be a list" % key)
		return []
	if value.size() > limit and not draft:  # a draft's items still get their shapes checked
		errors.append("more than %d %s" % [limit, key])
		return []
	return value


static func _point(value: Variant, what: String, errors: PackedStringArray, draft: bool) -> void:
	if not value is Array or value.size() != 2:
		errors.append("%s must be [x, y]" % what)
		return
	for c in value:
		_number(c, -MAX_COORD, MAX_COORD, what, errors, draft)


static func _whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == roundf(value))


static func _number(value: Variant, low: float, high: float, what: String, errors: PackedStringArray, draft: bool) -> void:
	if not (value is float or value is int) or is_nan(float(value)) or is_inf(float(value)) or (not draft and (value < low or value > high)):
		errors.append("%s must be a number from %s to %s" % [what, low, high])


static func _text(value: Variant, what: String, errors: PackedStringArray, draft: bool) -> void:
	if not value is String or (not draft and value.length() > MAX_TEXT):
		errors.append("%s must be text up to %d characters" % [what, MAX_TEXT])


static func _vec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])


## Whole numbers stay integers in the file; others keep two decimals.
static func _num(value: float) -> Variant:
	return int(value) if is_equal_approx(value, roundf(value)) else snappedf(value, 0.01)


static func _list_of(v: Vector2) -> Array:
	return [_num(v.x), _num(v.y)]
