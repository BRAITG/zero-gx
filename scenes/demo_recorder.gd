class_name DemoRecorder
extends Node
## Records a level run into a Demo: one frame every second physics tick from the first tick (the
## ship drifts under gravity before the first thrust), plus the level's events. A CLOCK_STARTED
## event marks the tick the score clock starts.

var demo := Demo.new()
var _level: Level
var _started := false
var _clock_started := false
var _tick := 0
var _rocks := {}  # id -> Asteroid alive
var _next_id := 0
var _finished := false


func _init(level: Level) -> void:
	_level = level
	demo.level_sha256 = level.level_sha256


func _ready() -> void:
	var pickups := _level.get_children().filter(func(n: Node) -> bool: return n is Pickup)
	for i in pickups.size():
		pickups[i].body_entered.connect(func(body: Node) -> void:
			if body is Ship and not _finished:
				demo.add_event(Demo.Event.PICKUP_TAKEN, [i]))
	var planets := _level.get_children().filter(func(n: Node) -> bool: return n is GravityBody)
	for i in planets.size():
		planets[i].shattered.connect(func() -> void:
			if not _finished:
				demo.add_event(Demo.Event.PLANET_SHATTERED, [i]))


func _physics_process(_delta: float) -> void:
	_start()
	if not _clock_started and _level.ship.flight_time > 0.0:
		_clock_started = true
		demo.add_event(Demo.Event.CLOCK_STARTED)
	if _tick % 2 == 0:
		_record_frame()
	_tick += 1


## The run is over: the last state and the result, whether or not a tick has run yet.
func finish(won: bool) -> void:
	set_physics_process(false)
	_start()
	_record_frame()
	demo.add_event(Demo.Event.GOAL_REACHED if won else Demo.Event.SHIP_LOST)
	_finished = true  # the world runs on behind the result card; the demo must not change


func _start() -> void:
	if _started:
		return
	_started = true
	for child in _level.get_children():
		if child is Asteroid:
			_track(child)
	_level.child_entered_tree.connect(func(node: Node) -> void:
		if node is Asteroid and not _finished:
			demo.add_event(Demo.Event.ASTEROID_SPAWNED, [_track(node)]))


func _track(rock: Asteroid) -> int:
	var id := _next_id
	_next_id += 1
	_rocks[id] = rock
	rock.tree_exiting.connect(func() -> void:
		_rocks.erase(id)
		if not _finished:
			demo.add_event(Demo.Event.ASTEROID_REMOVED, [id]))
	return id


func _record_frame() -> void:
	var ship := _level.ship
	var rocks := {}
	for id in _rocks:
		rocks[id] = _rocks[id].global_transform
	demo.add_frame({
		"position": ship.global_position,
		"rotation": ship.global_rotation,
		"firing": ship.firing,
		"fuel": 0.0 if ship.fuel_unlimited else ship.fuel,
		"hull": 0.0 if ship.hull_unlimited else ship.health,
	}, rocks)
