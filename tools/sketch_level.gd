extends SceneTree
## Writes the thumbnail sketch of a level file (LevelFormat.sketch_json) to another file.
## With a proof's demo as the third argument, the sketch also carries the demo's score as `par`.
## Usage: godot --headless --path . -s res://tools/sketch_level.gd -- <level.json> <out.json> [<proof.demo.gz>]
## Exits 1 with an error when the arguments are wrong, the level cannot be read or is not valid, the demo was not recorded on the level or is not a valid run of it, or the output cannot be written.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Loaded here, not preloaded: a -s script compiles before the autoloads the level code uses exist.
	var level_format: GDScript = load("res://scripts/level_format.gd")
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 and args.size() != 3:
		push_error("Usage: sketch_level.gd -- <level.json> <out.json> [<proof.demo.gz>]")
		quit(1)
		return
	var data: Dictionary = level_format.read(args[0])
	var errors: PackedStringArray = level_format.validate(data)
	if not errors.is_empty():
		push_error("%s is not a valid level: %s" % [args[0], "; ".join(errors)])
		quit(1)
		return
	# The proof's demo, when given, sets the sketch's par; it must be a valid run recorded on this level.
	var demo = null
	if args.size() == 3:
		var demo_script: GDScript = load("res://scripts/demo.gd")
		demo = demo_script.load_file(args[2])
		if demo == null or demo.level_sha256 != level_format.sha256(data):
			push_error("The demo was not recorded on this level.")
			quit(1)
			return
		var demo_check: GDScript = load("res://scripts/demo_check.gd")
		var problems: PackedStringArray = demo_check.check(data, demo)
		if not problems.is_empty():
			push_error("The demo is not a valid run of this level: %s" % problems[0])
			quit(1)
			return
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s" % args[1])
		quit(1)
		return
	file.store_string(level_format.sketch_json(level_format.sketch(data, demo)))
	file.close()
	quit(0)
