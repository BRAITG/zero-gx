extends SceneTree
## Writes the thumbnail sketch of a level file (LevelFormat.sketch_json) to another file.
## Usage: godot --headless --path . -s res://tools/sketch_level.gd -- <level.json> <out.json>
## Exits 1 with an error when the arguments are wrong, the level cannot be read or is not valid, or the output cannot be written.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Loaded here, not preloaded: a -s script compiles before the autoloads the level code uses exist.
	var level_format: GDScript = load("res://scripts/level_format.gd")
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: sketch_level.gd -- <level.json> <out.json>")
		quit(1)
		return
	var data: Dictionary = level_format.read(args[0])
	var errors: PackedStringArray = level_format.validate(data)
	if not errors.is_empty():
		push_error("%s is not a valid level: %s" % [args[0], "; ".join(errors)])
		quit(1)
		return
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % args[1])
		quit(1)
		return
	file.store_string(level_format.sketch_json(level_format.sketch(data)))
	file.close()
	quit(0)
