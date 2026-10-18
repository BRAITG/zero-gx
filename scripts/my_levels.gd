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


static func delete(id: String) -> void:
	DirAccess.remove_absolute(dir + id + EXTENSION)
	DirAccess.remove_absolute(_demo_path(id))
	var index := _index()
	if index.has_section(id):
		index.erase_section(id)
		index.save(dir + "index.cfg")


## The draft's last winning test flight, kept only while the draft is unchanged.
static func demo(id: String) -> Demo:
	var found := Demo.load_file(_demo_path(id))
	return found if found and found.level_sha256 == LevelFormat.sha256(load_level(id)) else null


static func save_demo(id: String, run: Demo) -> void:
	run.save(_demo_path(id))


static func _demo_path(id: String) -> String:
	return dir + id + ".demo.gz"


static func is_completed(id: String) -> bool:
	return _index().get_value(id, "completed_hash", "") == _hash(load_level(id))


## Record that the author finished `id` as it is saved now.
static func mark_completed(id: String) -> void:
	var index := _index()
	index.set_value(id, "completed_hash", _hash(load_level(id)))
	index.save(dir + "index.cfg")


static func _index() -> ConfigFile:
	var index := ConfigFile.new()
	index.load(dir + "index.cfg")  # missing means nothing completed yet
	return index


static func _hash(data: Dictionary) -> String:
	return JSON.stringify(data, "", true).sha256_text() if not data.is_empty() else "-"
