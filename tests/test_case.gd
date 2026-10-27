extends RefCounted
## Base class for test files. The runner sets `tree` and a fresh `world` before each test method.

var tree: SceneTree
var world: Node2D
var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


## Coroutine: wait `n` physics frames.
func frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## The tiers of the medal icons visible under `node`.
func medal_tiers(node: Node) -> Array:
	var icons := node.find_children("*", "ScoreIcon", true, false).filter(func(i: ScoreIcon) -> bool: return i.kind == ScoreIcon.Kind.MEDAL and i.is_visible_in_tree())
	return icons.map(func(i: ScoreIcon) -> int: return i.tier)


## Instantiate `path`, set `props` before entering the tree, add it to `world` at `pos`.
func spawn(path: String, pos: Vector2, props: Dictionary = {}) -> Node:
	var node: Node = load(path).instantiate()
	for key in props:
		node.set(key, props[key])
	node.position = pos
	world.add_child(node)
	return node


## Autopilot for winnability checks: a velocity controller toward the next waypoint that slows
## only as much as the turn there needs. `state.next` tracks the waypoint. Waypoints listed in
## `coast` are flown to without thrust, as a player rides a slingshot.
const CRUISE := 450.0  # px/s
const ARRIVE_GAIN := 1.2  # 1/s: desired speed per px left to the waypoint
const ARRIVE_FLOOR := 80.0  # px/s at a right-angle turn
const WAYPOINT_REACH := 110.0  # px
const COAST_REACH := 300.0  # px: a coast waypoint only needs to be passed near
const DEAD_BAND := 40.0  # px/s of velocity error tolerated before thrusting


func fly(ship: Ship, waypoints: Array[Vector2], state: Dictionary, cruise := CRUISE, coast := PackedInt32Array()) -> void:
	var at := ship.global_position
	while state.next < waypoints.size() - 1 and at.distance_to(waypoints[state.next]) < (COAST_REACH if state.next in coast else WAYPOINT_REACH):
		state.next += 1
	if state.next in coast:
		ship.thrusting = false
		return
	var to: Vector2 = waypoints[state.next] - at
	var turn := 0.0
	if state.next < waypoints.size() - 1 and not (state.next + 1 in coast):  # arrive at a release point at speed
		turn = absf(to.angle_to(waypoints[state.next + 1] - waypoints[state.next]))
	var arrive := lerpf(cruise, ARRIVE_FLOOR, clampf(turn / (PI / 2.0), 0.0, 1.0))
	var error := to.normalized() * minf(cruise, ARRIVE_GAIN * to.length() + arrive) - ship.linear_velocity
	ship.thrusting = error.length() > DEAD_BAND
	ship.aim_point = at + error.normalized() * 1000.0
