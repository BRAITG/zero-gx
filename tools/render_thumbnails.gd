extends SceneTree
## Renders every stage thumbnail (scenes/thumbnail.gd) to build/thumbnails/<id>.png (640x360) and
## build/thumbnails/phone/<id>.png (130x73, the size a phone shows), and every official level's sketch
## (the picture a community row shows) to build/thumbnails/sketch/<id>.png, for review.
## Needs a real renderer: godot --path . -s res://tools/render_thumbnails.gd

const SIZES := {"build/thumbnails/": Vector2i(640, 360), "build/thumbnails/phone/": Vector2i(130, 73)}
const SKETCH_DIR := "build/thumbnails/sketch/"


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Thumbnail rendering needs a window, not --headless.")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	# Loaded here, not preloaded: a -s script compiles before the autoloads Thumbnail's dependencies use exist.
	var thumbnail_script: GDScript = load("res://scenes/thumbnail.gd")
	var level_format: GDScript = load("res://scripts/level_format.gd")
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for dir: String in SIZES:
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			push_error("Cannot create %s" % dir)
			quit(1)
			return
		viewport.size = SIZES[dir]
		for id: String in _stems("res://levels/") + _stems("res://tutorials/"):
			if not await _save(viewport, thumbnail_script.new(id), dir + id + ".png"):
				quit(1)
				return
	if DirAccess.make_dir_recursive_absolute(SKETCH_DIR) != OK:
		push_error("Cannot create %s" % SKETCH_DIR)
		quit(1)
		return
	viewport.size = Vector2i(640, 360)
	for dir: String in ["res://levels/", "res://tutorials/"]:
		for id: String in _stems(dir):
			var sketch: Dictionary = level_format.sketch(level_format.read(dir + id + ".json"))
			if not await _save(viewport, thumbnail_script.of_sketch(sketch), SKETCH_DIR + id + ".png"):
				quit(1)
				return
	print("Rendered to build/thumbnails/")
	quit(0)


## Shows `thumbnail` at the viewport's size for one frame and saves it to `path`; false when the file cannot be written.
func _save(viewport: SubViewport, thumbnail: Control, path: String) -> bool:
	thumbnail.size = viewport.size
	viewport.add_child(thumbnail)
	await process_frame
	await RenderingServer.frame_post_draw  # the texture holds this thumbnail, not the previous one
	var saved := viewport.get_texture().get_image().save_png(path) == OK
	if not saved:
		push_error("Cannot write %s" % path)
	thumbnail.free()
	return saved


func _stems(dir: String) -> Array:
	return Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".json")).map(func(f: String) -> String: return f.trim_suffix(".json"))
