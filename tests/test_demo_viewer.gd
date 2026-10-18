extends "res://tests/test_case.gd"

const FLIGHT_LIMIT := 4800  # frames: 80 s


## Flies level_01 by autopilot and returns the won level, or null.
func won_level_01() -> Level:
	var lvl := Progress.build("level_01")
	world.add_child(lvl)
	var outcome := {"won": null}
	lvl.finished.connect(func(won: bool): outcome.won = won)
	var route := lvl.get_node("Route") as Line2D
	var waypoints: Array[Vector2] = []
	for point in route.points:
		waypoints.append(route.position + point)
	waypoints.append(lvl.goal.position)
	var pilot := {"next": 0}
	for frame in FLIGHT_LIMIT:
		await frames(1)
		if outcome.won != null:
			break
		fly(lvl.ship, waypoints, pilot)
	return lvl if outcome.won == true else null


## A hand-made demo of `count` frames with one asteroid (id 0) and, when `spawn` >= 0, a shard
## (id 1) that appears at frame `spawn`; it ends with `ending`.
func scripted(count: int, spawn: int, ending: Demo.Event) -> Demo:
	var demo := Demo.new()
	for f in count:
		var rocks := {0: Transform2D(0.0, Vector2(500, 0))}
		if spawn >= 0 and f >= spawn:
			rocks[1] = Transform2D(0.0, Vector2(900, 0))
		if f == spawn:
			demo.add_event(Demo.Event.ASTEROID_SPAWNED, [1])
		demo.add_frame({"position": Vector2(f * 10.0, 0), "rotation": 0.0, "firing": false, "fuel": 100.0, "hull": 100.0}, rocks)
	demo.add_event(ending)
	return demo


func scripted_level() -> Dictionary:
	var data := LevelDoc.blank()
	data.ship.position = [0, 0]
	data.goal.position = [5000, 0]
	data.asteroids = [{"position": [500, 0]}]
	return data


func visible_asteroids(viewer: DemoViewer) -> int:
	return viewer.level.get_children().filter(func(n: Node) -> bool: return n is Asteroid and n.visible).size()


func test_seek_places_every_object() -> void:
	var lvl := await won_level_01()
	check(lvl != null, "autopilot did not win level_01")
	if lvl == null:
		return
	var demo := lvl.demo
	var viewer := DemoViewer.create(lvl.level_data, demo, func() -> void: pass)
	world.add_child(viewer)
	check(viewer.level.get_children().all(func(n: Node) -> bool: return not n is Tour), "a replay must not run the level's tour")
	check(not tree.paused, "a replay must not pause the tree")
	for n in [0, demo.frame_count() / 2, demo.frame_count() - 1]:
		viewer.seek(n)
		var at := viewer.ship.global_position
		check(at.distance_to(demo.ship_at(n).position) <= 0.2, "frame %d: viewer ship %s, demo %s" % [n, at, demo.ship_at(n).position])
		for id in demo.asteroids_at(n):
			var rock := viewer.rock(id)
			check(rock.visible and rock.global_position.distance_to(demo.asteroids_at(n)[id].origin) <= 0.2, "frame %d: asteroid %d misplaced" % [n, id])
	lvl.free()


func test_seeking_back_restores_unspawned_shards() -> void:
	var viewer := DemoViewer.create(scripted_level(), scripted(90, 30, Demo.Event.GOAL_REACHED), func() -> void: pass)
	world.add_child(viewer)
	viewer.seek(60)
	check(visible_asteroids(viewer) == 2, "the shard must show after its spawn: %d visible" % visible_asteroids(viewer))
	viewer.seek(10)
	check(visible_asteroids(viewer) == 1, "the shard must hide before its spawn: %d visible" % visible_asteroids(viewer))
	viewer.seek(60)
	check(visible_asteroids(viewer) == 2, "the shard must come back: %d visible" % visible_asteroids(viewer))


func test_a_lost_run_plays_to_its_end() -> void:
	var demo := scripted(60, 20, Demo.Event.SHIP_LOST)
	var viewer := DemoViewer.create(scripted_level(), demo, func() -> void: pass)
	world.add_child(viewer)
	viewer.speed = 2.0
	for i in 300:
		if viewer.paused:
			break
		await frames(1)
	check(viewer.paused and viewer.cursor == demo.frame_count() - 1, "stopped at %s of %d" % [viewer.cursor, demo.frame_count() - 1])
	check(viewer.ship.global_position.distance_to(demo.ship_at(demo.frame_count() - 1).position) <= 0.2, "the ship must end where the demo ends")


func test_the_back_gesture_goes_to_the_viewers_back() -> void:
	var ran := {"back": 0}
	var viewer := DemoViewer.create(scripted_level(), scripted(5, -1, Demo.Event.GOAL_REACHED), func() -> void: ran.back += 1)
	world.add_child(viewer)
	var scene := tree.current_scene
	tree.root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(ran.back == 1, "Back ran %d times" % ran.back)
	check(tree.current_scene == scene, "the preview level must not change the scene itself")


func test_the_back_gesture_in_the_editor_saves_and_lists_levels() -> void:
	var editor := LevelEditor.create(MyLevels.new_id())
	world.add_child(editor)
	var scene := tree.current_scene
	tree.root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	check(tree.current_scene is MyLevelsScreen, "the editor's Back must end on the level list, not the menu: %s" % [tree.current_scene])
	if tree.current_scene != scene:
		tree.current_scene.free()
		tree.current_scene = null


func test_a_demo_without_frames_is_no_demo() -> void:
	var id := MyLevels.new_id()
	var data := scripted_level()
	MyLevels.save(id, data)
	var empty := Demo.new()
	empty.level_sha256 = LevelFormat.sha256(MyLevels.load_level(id))
	MyLevels.save_demo(id, empty)
	check(MyLevels.demo(id) == null, "a zero-frame draft demo must not be offered")
	Progress.save_best_demo("level_01", empty)
	check(Progress.best_demo("level_01") == null, "a zero-frame best demo must not be offered")
	DirAccess.remove_absolute(Progress.demos_dir + "level_01.demo.gz")
	MyLevels.delete(id)
