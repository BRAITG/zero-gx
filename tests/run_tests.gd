extends SceneTree
## Runs every `test_*` method in `res://tests/test_*.gd`, each with a fresh world. Exit code 1 on failure.

const TIMEOUT_FRAMES := 70000  # The level-design check idles 12000 frames in each of 5 levels.

## Runtime script errors abort the test method without failing it; this catches them.
class ScriptErrors extends Logger:
	var seen: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			seen.append("script error: %s (%s:%d)" % [rationale if rationale else code, file, line])

var _errors := ScriptErrors.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	_run()


func _run() -> void:
	await process_frame  # autoloads and root are not fully in the tree during _initialize
	var failed := 0
	var passed := 0
	var only := OS.get_environment("TEST_FILTER")
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if not script or not script.can_instantiate():
			failed += 1
			print("FAIL %s: does not compile" % file)
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_") or (only != "" and not (file + "::" + name).contains(only)):
				continue
			var test = script.new()
			test.tree = self
			root.get_node("Tuning").reset()  # a test that changes a value must not leak it
			root.get_node("Tuning").tours = false  # a tour pauses the game; tests that want one turn it on
			var progress := root.get_node("Progress")
			progress.path = "user://test_progress.cfg"  # never touch the player's real progress
			progress.unlock_all = false
			progress.toured.clear()
			progress.reset()
			test.world = Node2D.new()
			root.add_child(test.world)
			var state := {"done": false}
			_errors.seen.clear()
			_invoke(test, name, state)
			var waited := 0
			while not state.done and waited < TIMEOUT_FRAMES:
				await physics_frame
				waited += 1
			if not state.done:
				test.failures.append("timed out after %d frames" % TIMEOUT_FRAMES)
			test.world.queue_free()
			test.failures.append_array(_errors.seen)
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
