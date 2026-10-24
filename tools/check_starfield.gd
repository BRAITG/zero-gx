extends SceneTree
## Run with a real renderer: godot --path . -s res://tools/check_starfield.gd
## Guards the starfield's draw-call budget at rest and with motion streaks.

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Starfield rendering check needs a window, not --headless.")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var stars := load("res://scenes/starfield.gd").new() as Node2D
	root.add_child(stars)
	var ship := load("res://scenes/ship.tscn").instantiate() as RigidBody2D
	ship.freeze = true
	root.add_child(ship)
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	stars.ship = ship
	var failed := false
	for velocity in [Vector2.ZERO, Vector2(300, 120), Vector2(-300, -120)]:
		ship.linear_velocity = velocity
		await create_timer(1.0).timeout
		var start := Time.get_ticks_usec()
		var frames := 0
		var calls := 0.0
		while Time.get_ticks_usec() - start < 2_000_000:
			await process_frame
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			frames += 1
		calls /= frames
		var ms := (Time.get_ticks_usec() - start) / 1000.0 / frames
		print("Starfield velocity %s: %.2f ms, %.0f FPS, %.0f draw calls" % [velocity, ms, 1000.0 / ms, calls])
		if calls > 1000:
			push_error("Starfield exceeds 1000 draw calls; individual stars or streaks are no longer batched.")
			failed = true
	quit(1 if failed else 0)
