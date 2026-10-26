extends SceneTree
## Renders a whole level, the picture a submission PR shows: its walls, bodies, pickups, asteroids, ship and goal over the
## starfield, framed by the level's sketch bounds. The PNG is 1600 px wide; its height follows the level's aspect, 400 to 1600.
## Needs a real renderer: godot --path . -s res://tools/render_level.gd -- <level.json> <out.png>
## Exits 1 with an error when the arguments are wrong, the level cannot be read or is not valid, or the image cannot be written.

const WIDTH := 1600
const MIN_HEIGHT := 400
const MAX_HEIGHT := 1600
const MARGIN := 1.05  # the level fills 1/1.05 of the picture: 5 % of air around it


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Level rendering needs a window, not --headless.")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	# Loaded here, not preloaded: a -s script compiles before the autoloads the level code uses exist.
	var level_format: GDScript = load("res://scripts/level_format.gd")
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: render_level.gd -- <level.json> <out.png>")
		quit(1)
		return
	var data: Dictionary = level_format.read(args[0])
	var errors: PackedStringArray = level_format.validate(data)
	if not errors.is_empty():
		push_error("%s is not a valid level: %s" % [args[0], "; ".join(errors)])
		quit(1)
		return
	var bounds: Array = level_format.sketch(data).bounds
	var box := Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	var viewport := SubViewport.new()
	viewport.size = Vector2i(WIDTH, clampi(roundi(WIDTH * box.size.y / box.size.x), MIN_HEIGHT, MAX_HEIGHT))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(load("res://scenes/starfield.gd").new())
	viewport.add_child(level_format.build(data, load("res://scenes/level_preview.gd")))
	var camera := Camera2D.new()
	camera.position = box.get_center()
	camera.zoom = Vector2.ONE * minf(viewport.size.x / box.size.x, viewport.size.y / box.size.y) / MARGIN
	viewport.add_child(camera)
	camera.make_current()  # the built ship carries a follow camera of its own
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(args[1]) != OK:
		push_error("Cannot write %s" % args[1])
		quit(1)
		return
	quit(0)
