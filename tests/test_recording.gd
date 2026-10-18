extends "res://tests/test_case.gd"

const FLIGHT_LIMIT := 4800  # frames: 80 s


## A draft saved under a fresh id, built the way the game builds it, and in the tree.
func draft(data: Dictionary, testing := false) -> Level:
	var id := MyLevels.new_id()
	MyLevels.save(id, data)
	var lvl := Progress.build(id, testing)
	world.add_child(lvl)
	return lvl


func blank_with(extra: Dictionary) -> Dictionary:
	var data := LevelDoc.blank()
	data.ship.position = [0, 1500]
	data.goal.position = [3000, 1500]
	data.merge(extra)
	return data


func test_autopilot_run_is_recorded_frame_by_frame() -> void:
	var lvl := Progress.build("level_01")
	world.add_child(lvl)
	var route := lvl.get_node("Route") as Line2D
	var waypoints: Array[Vector2] = []
	for point in route.points:
		waypoints.append(route.position + point)
	waypoints.append(lvl.goal.position)
	var outcome := {"won": null}
	lvl.finished.connect(func(won: bool): outcome.won = won)
	var pilot := {"next": 0}
	var seen := 0
	var before := lvl.ship.global_position  # where the ship was when the last tick recorded
	var checked := 0
	for frame in FLIGHT_LIMIT:
		await frames(1)
		if outcome.won != null:
			break
		fly(lvl.ship, waypoints, pilot)
		var count := lvl.demo.frame_count()
		if count > seen and count % 30 == 0:
			var recorded: Vector2 = lvl.demo.ship_at(count - 1).position
			check(recorded.distance_to(before) <= 1.0, "frame %d: recorded %s, ship %s" % [count - 1, recorded, before])
			checked += 1
		seen = count
		before = lvl.ship.global_position
	check(outcome.won == true, "autopilot must win level_01")
	check(checked > 0, "no frame was compared")
	var events := lvl.demo.events()
	check(not events.is_empty() and events.back()[1] == Demo.Event.GOAL_REACHED, "the last event must be GOAL_REACHED: %s" % [events.back() if events else null])
	check(lvl.demo.level_sha256 == LevelFormat.sha256(LevelFormat.read("res://levels/level_01.json")), "wrong level hash")
	check(lvl.level_data == LevelFormat.read("res://levels/level_01.json"), "level_data must be the file's data")
	check(Progress.best_demo("level_01") != null, "a new best must store its demo")


func test_a_lost_run_is_still_a_whole_demo() -> void:
	var lvl := draft(blank_with({}))
	lvl.ship.start_boost()
	await frames(60)
	lvl.ship.take_damage(10000.0)
	await frames(5)
	var decoded := Demo.decode(lvl.demo.encode())
	check(decoded != null and decoded.frame_count() == lvl.demo.frame_count(), "the demo must decode from its own encoding")
	check(lvl.demo.frame_count() >= 25, "a second of flight is %d frames" % lvl.demo.frame_count())
	var events := lvl.demo.events()
	check(not events.is_empty() and events.back()[1] == Demo.Event.SHIP_LOST, "the last event must be SHIP_LOST: %s" % [events])


func test_a_run_lost_before_any_thrust_has_a_frame() -> void:
	var lvl := draft(blank_with({}))
	await frames(2)
	lvl.finish(false)
	check(lvl.demo.frame_count() == 1, "expected the final frame, got %d" % lvl.demo.frame_count())


func test_shards_are_recorded_from_their_spawn() -> void:
	var lvl := draft(blank_with({
		"bodies": [{"kind": "planet", "position": [400, 0], "destructible": true, "health": 1}],
		"asteroids": [{"position": [0, 0], "velocity": [400, 0]}],
	}))
	lvl.ship.start_boost()
	await frames(120)
	var spawned := lvl.demo.events().filter(func(e: Array) -> bool: return e[1] == Demo.Event.ASTEROID_SPAWNED)
	check(spawned.size() >= GravityBody.SHARDS_MIN, "%d shards spawned" % spawned.size())
	check(lvl.demo.events().any(func(e: Array) -> bool: return e[1] == Demo.Event.PLANET_SHATTERED), "no PLANET_SHATTERED event")
	if not spawned.is_empty():
		var shard: int = spawned[0][2][0]
		var frame: int = spawned[0][0]
		check(lvl.demo.asteroids_at(frame).has(shard), "shard %d missing on its spawn frame %d" % [shard, frame])
		check(not lvl.demo.asteroids_at(maxi(frame - 1, 0)).has(shard) or frame == 0, "shard %d exists before it spawned" % shard)


func test_tutorials_are_not_recorded() -> void:
	var lvl := Progress.build("tutorial_1")
	world.add_child(lvl)
	check(lvl.demo == null and lvl.level_sha256 == "", "a tutorial must not record")


func test_draft_demo_is_kept_only_while_the_draft_is_unchanged() -> void:
	var data := LevelDoc.blank()
	var id := MyLevels.new_id()
	MyLevels.save(id, data)
	var lvl := Progress.build(id, true)
	world.add_child(lvl)
	await frames(2)
	lvl.finish(true)
	check(MyLevels.demo(id) != null, "a won test flight must keep its demo")
	data.title = "Changed"
	MyLevels.save(id, data)
	check(MyLevels.demo(id) == null, "an edited draft must drop the demo")


func test_the_demo_is_frozen_when_the_run_ends() -> void:
	var lvl := draft(blank_with({
		"bodies": [{"kind": "planet", "position": [400, 0], "destructible": true, "health": 1}],
		"asteroids": [{"position": [0, 0], "velocity": [400, 0]}],
	}))
	lvl.ship.start_boost()
	await frames(10)
	lvl.finish(true)
	var demo := lvl.demo
	var events := demo.events().duplicate(true)
	var count := demo.frame_count()
	await frames(300)  # the world runs on: the planet shatters and shards spawn
	check(lvl.get_children().filter(func(n: Node) -> bool: return n is Asteroid).size() > 1, "the planet did not shatter, so the test proves nothing")
	lvl.free()
	check(demo.frame_count() == count, "frames changed after the run ended")
	check(demo.events() == events, "events changed after the run ended: %s" % [demo.events().slice(events.size())])
	check(events.back()[1] == Demo.Event.GOAL_REACHED, "the last event must stay GOAL_REACHED")
