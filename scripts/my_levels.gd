class_name MyLevels
extends RefCounted
## The player's own levels on the device: `user://levels/<id>.json.gz`, ids starting "user_".
## A level is completed when its author finished it in Test, and stays so only while it is
## unchanged: the index stores a hash of the level as it was when finished.

const EXTENSION := ".json.gz"
const PREFIX := "user_"

static var dir := "user://levels/"


static func ids() -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if file.begins_with(PREFIX) and file.ends_with(EXTENSION):
			found.append(file.trim_suffix(EXTENSION))
	found.sort()
	return found


static func new_id() -> String:
	return PREFIX + "%x%04x" % [int(Time.get_unix_time_from_system()), randi() % 0x10000]


static func load_level(id: String) -> Dictionary:
	return LevelFormat.read(dir + id + EXTENSION)


static func save(id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	LevelFormat.write(dir + id + EXTENSION, data)


## Imports a level file as a new level. Drafts import too: only a malformed file (wrong format,
## version, types or shapes) is refused; `LevelFormat.validate` gates Play.
static func import_file(path: String) -> PackedStringArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["file cannot be read"]
	# shortcut: the 64 KB limit applies to the compressed size of a gzip file, so a small gzip bomb still inflates in memory; cap the inflated read when levels come from the community server
	if file.get_length() > LevelFormat.MAX_BYTES:
		return ["file is larger than %d bytes" % LevelFormat.MAX_BYTES]
	var data := LevelFormat.read(path)
	var errors := LevelFormat.validate(data, true)
	if not errors.is_empty():
		return errors
	var id := new_id()
	while FileAccess.file_exists(dir + id + EXTENSION):  # same-second ids can collide; never overwrite
		id = new_id()
	save(id, data)
	return PackedStringArray()


## `path` is a file name or an Android `content://` URI, which already names the file and takes no extension.
static func export_file(id: String, path: String) -> Error:
	return LevelFormat.write(path if path.ends_with(".json") or path.begins_with("content://") else path + ".json", load_level(id))


static func delete(id: String) -> void:
	DirAccess.remove_absolute(dir + id + EXTENSION)
	DirAccess.remove_absolute(demo_path(id))
	var index := _index()
	if index.has_section(id):
		index.erase_section(id)
		index.save(dir + "index.cfg")


## The draft's last winning test flight, kept only while the draft is unchanged.
static func demo(id: String) -> Demo:
	var found := Demo.load_file(demo_path(id))
	return found if found and found.frame_count() > 0 and found.level_sha256 == LevelFormat.sha256(load_level(id)) else null


## Whether `demo(id)` has something to show, without decoding the frames.
static func has_demo(id: String) -> bool:
	return Demo.peek_level_sha256(FileAccess.get_file_as_bytes(demo_path(id))) == LevelFormat.sha256(load_level(id))


static func save_demo(id: String, run: Demo) -> void:
	run.save(demo_path(id))


static func demo_path(id: String) -> String:
	return dir + id + ".demo.gz"


static func is_completed(id: String) -> bool:
	return _index().get_value(id, "completed_hash", "") == _hash(load_level(id))


## Record that the author finished `id` as it is saved now.
static func mark_completed(id: String) -> void:
	var index := _index()
	index.set_value(id, "completed_hash", _hash(load_level(id)))
	index.save(dir + "index.cfg")


## The community id of a draft that was submitted, "" before its first submission; later versions of the draft are sent under it.
static func level_id(id: String) -> String:
	return _index().get_value(id, "level_id", "")


## Remember the community id of `id`; "" forgets it.
static func set_level_id(id: String, community_id: String) -> void:
	var index := _index()
	index.set_value(id, "level_id", community_id if community_id != "" else null)
	index.save(dir + "index.cfg")


## Whether draft `id` was submitted and is still as it was then; editing it makes it a new version.
static func is_submitted(id: String) -> bool:
	return _index().get_value(id, "submitted_hash", "") == LevelFormat.sha256(load_level(id))


## Record that `id` went to the server as the level with content hash `hash` (`LevelFormat.sha256`); "" forgets it.
static func set_submitted(id: String, hash: String) -> void:
	var index := _index()
	index.set_value(id, "submitted_hash", hash if hash != "" else null)
	index.save(dir + "index.cfg")


static func _index() -> ConfigFile:
	var index := ConfigFile.new()
	index.load(dir + "index.cfg")  # missing means nothing completed yet
	return index


static func _hash(data: Dictionary) -> String:
	return JSON.stringify(data, "", true).sha256_text() if not data.is_empty() else "-"
