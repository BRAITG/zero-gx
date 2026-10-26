extends SceneTree
## Renders every stage thumbnail (scenes/thumbnail.gd) to build/thumbnails/<id>.png (640x360) and
## build/thumbnails/phone/<id>.png (130x73, the size a phone shows) for review.
## Needs a real renderer: godot --path . -s res://tools/render_thumbnails.gd

const SIZES := {"build/thumbnails/": Vector2i(640, 360), "build/thumbnails/phone/": Vector2i(130, 73)}


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Thumbnail rendering needs a window, not --headless.")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	# Loaded here, not preloaded: a -s script compiles before the autoloads Thumbnail's dependencies use exist.
	var thumbnail_script: GDScript = load("res://scenes/thumbnail.gd")
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
			var thumbnail: Control = thumbnail_script.new(id)
			thumbnail.size = viewport.size
			viewport.add_child(thumbnail)
			await process_frame
			await RenderingServer.frame_post_draw  # the texture holds this thumbnail, not the previous one
			var path := dir + id + ".png"
			if viewport.get_texture().get_image().save_png(path) != OK:
				push_error("Cannot write %s" % path)
				quit(1)
				return
			thumbnail.free()
	print("Rendered to build/thumbnails/")
	quit(0)


func _stems(dir: String) -> Array:
	return Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".json")).map(func(f: String) -> String: return f.trim_suffix(".json"))
