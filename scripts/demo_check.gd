class_name DemoCheck
extends RefCounted
## Validates a demo against its level's data. The rules are plain on purpose: the server ports them to TypeScript.

const START_TOLERANCE := 2.0  # px
const SPEED_MARGIN := 1.1
const CLAIM_TOLERANCE := 0.5  # fuel and hull
const POINTS_TOLERANCE := 2
const CONTACT_MARGIN := 2.0  # px a ship may overlap a lethal surface before it counts as contact
## Where the ship's circle meets a barrier's collision slab.
const RED_CONTACT := Barrier.THICKNESS / 2.0 + Ship.RADIUS - CONTACT_MARGIN


## Every rule the demo breaks; empty when it passes. `claim` holds `points`, `fuel`, `hull` and
## `seconds`; with no claim the claim rule is skipped.
static func check(level: Dictionary, demo: Demo, claim: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	if demo.truncated:
		errors.append("the demo is truncated")
	if demo.level_sha256 != LevelFormat.sha256(level):
		errors.append("the demo was recorded on a different level")
	var count := demo.frame_count()
	if count == 0:
		errors.append("the demo has no frames")
		return errors
	var goal := _vec(level.goal.position)
	var first: Vector2 = demo.ship_at(0).position
	if first.distance_to(_vec(level.ship.position)) > START_TOLERANCE:
		errors.append("frame 0: the ship does not start at the level's start")
	var last: Dictionary = demo.ship_at(count - 1)
	if last.position.distance_to(goal) > Goal.RADIUS + Ship.RADIUS:
		errors.append("frame %d: the ship is not inside the goal" % (count - 1))
	var events := demo.events()
	if events.is_empty() or events.back()[1] != Demo.Event.GOAL_REACHED or events.back()[0] != count:
		errors.append("the demo does not end with the goal event")

	var max_step := Ship.TUNNEL_LIMIT * SPEED_MARGIN * Demo.STEP
	var walls := _wall_segments(level)
	var hazards: Array = level.get("bodies", []).filter(func(b: Dictionary) -> bool: return b.kind != "planet")
	var fuel_limited: bool = not LevelFormat.is_unlimited(level.ship.get("fuel", Ship.MAX_FUEL))
	for f in count:
		var now: Dictionary = demo.ship_at(f)
		var before: Dictionary = demo.ship_at(maxi(f - 1, 0))
		for wall in walls:
			if wall.kind == "red" and Geometry2D.get_closest_point_to_segment(now.position, wall.a, wall.b).distance_to(now.position) < RED_CONTACT:
				errors.append("frame %d: the ship touched a red wall" % f)
		for body in hazards:
			# The whole step, so a fast frame cannot hop over the body.
			var centre := _vec(body.position)
			if Geometry2D.get_closest_point_to_segment(centre, before.position, now.position).distance_to(centre) < LevelFormat.body_value(body, "radius") + Ship.RADIUS - CONTACT_MARGIN:
				errors.append("frame %d: the ship hit a %s" % [f, body.kind.replace("_", " ")])
		if f == 0:
			continue
		var moved: float = now.position.distance_to(before.position)
		if moved > max_step:
			errors.append("frame %d: the ship moved %d px in one frame" % [f, moved])
		for wall in walls:
			if Geometry2D.segment_intersects_segment(before.position, now.position, wall.a, wall.b) != null:
				errors.append("frame %d: the ship crossed a wall" % f)
		if fuel_limited and now.fuel > before.fuel:
			errors.append("frame %d: fuel rose from %.1f to %.1f" % [f, before.fuel, now.fuel])

	if not claim.is_empty():
		if absf(claim.seconds - demo.seconds()) > Demo.STEP:
			errors.append("claimed %.2f seconds, the demo lasts %.2f" % [claim.seconds, demo.seconds()])
		if absf(claim.fuel - last.fuel) > CLAIM_TOLERANCE:
			errors.append("claimed fuel %.1f, the demo ends with %.1f" % [claim.fuel, last.fuel])
		if absf(claim.hull - last.hull) > CLAIM_TOLERANCE:
			errors.append("claimed hull %.1f, the demo ends with %.1f" % [claim.hull, last.hull])
		var points: int = Progress.points(claim.fuel, claim.hull, claim.seconds)
		if absi(claim.points - points) > POINTS_TOLERANCE:
			errors.append("claimed %d points, the claim is worth %d" % [claim.points, points])
	return errors


## Every wall as separate segments {kind, a, b}; a closed wall includes last point back to first.
static func _wall_segments(level: Dictionary) -> Array:
	var out := []
	for wall: Dictionary in level.get("walls", []):
		var points: Array = wall.points
		var n: int = points.size() if wall.get("closed", false) else points.size() - 1
		for i in n:
			out.append({"kind": wall.kind, "a": _vec(points[i]), "b": _vec(points[(i + 1) % points.size()])})
	return out


static func _vec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
