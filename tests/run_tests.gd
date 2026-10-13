extends SceneTree
## Runs every `test_*` method in `res://tests/test_*.gd`, each with a fresh world. Exit code 1 on failure.

const TIMEOUT_FRAMES := 20000  # Longest test (level-design check) runs 3600 frames per level.


func _initialize() -> void:
	_run()


func _run() -> void:
	var failed := 0
	var passed := 0
	var only := OS.get_environment("TEST_FILTER")
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_") or (only != "" and not (file + "::" + name).contains(only)):
				continue
			var test = script.new()
			test.tree = self
			test.world = Node2D.new()
			root.add_child(test.world)
			var state := {"done": false}
			_invoke(test, name, state)
			var waited := 0
			while not state.done and waited < TIMEOUT_FRAMES:
				await physics_frame
				waited += 1
			if not state.done:
				test.failures.append("timed out after %d frames" % TIMEOUT_FRAMES)
			test.world.queue_free()
			await process_frame
			if test.failures.is_empty():
				passed += 1
				print("PASS %s::%s" % [file, name])
			else:
				failed += 1
				print("FAIL %s::%s: %s" % [file, name, "; ".join(test.failures)])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _invoke(test: Object, name: String, state: Dictionary) -> void:
	await Callable(test, name).call()
	state.done = true
