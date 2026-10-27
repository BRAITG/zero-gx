extends SceneTree
## Sets each official level's `par` to the points the autopilot scores on it, and prints `level_NN <points>`.
## A level the autopilot does not finish keeps its file as it is, and the run exits 1. Run from the
## project root, as tools/make_fixtures.gd is:
##   godot --headless --path . -s res://tools/par_levels.gd

# Untyped and loaded after the first frame: a -s script compiles before the autoloads exist and
# cannot use the global class names.
var _format


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_format = load("res://scripts/level_format.gd")
	root.get_node("Tuning").tours = false
	var progress = root.get_node("Progress")
	progress.path = "user://par_progress.cfg"  # the flights must not touch the player's progress or demos
	progress.demos_dir = "user://par_demos/"
	progress.reset()
	var pilot = load("res://tests/test_demo_check.gd").new()  # flies a level along its hidden route
	pilot.tree = self
	var unfinished := false
	for id in progress.levels():
		pilot.world = Node2D.new()
		root.add_child(pilot.world)
		seed(1)  # random effects replay the same way, as in the test run
		var lvl = await pilot.fly_level(progress.build(id))
		if lvl == null:
			print("%s unfinished" % id)
			unfinished = true
		else:
			var points: int = pilot.claim_from(lvl).points
			print("%s %d" % [id, points])
			var path: String = progress.LEVELS_DIR + id + _format.EXTENSION
			var data: Dictionary = _format.read(path)
			data.par = points
			if _format.write(path, data) != OK:
				push_error("par_levels: could not write %s" % path)
				quit(1)
				return
		pilot.world.free()
	quit(1 if unfinished else 0)
