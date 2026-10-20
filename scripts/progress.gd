extends Node
## Saved best results per stage, the points formula, and stage unlocking.
## Autoloaded as `Progress`. A stage id is its file stem, e.g. "tutorial_1" or "level_01".

signal changed

const TUTORIALS_DIR := "res://tutorials/"
const LEVELS_DIR := "res://levels/"
const BASE_POINTS := 1000
const MIN_POINTS := 100

var path := "user://progress.cfg"
var demos_dir := "user://demos/"
## Session-only debug switch from the Tune panel; never saved.
var unlock_all := false:
	set(value):
		unlock_all = value
		changed.emit()
## Levels whose tour was shown this session, so a restart after a crash does not repeat it.
var toured := {}

var _file := ConfigFile.new()


func _ready() -> void:
	load_file()


## Sorted ids of every level in res://levels/ (tutorials not included).
func levels() -> PackedStringArray:
	return _stems(LEVELS_DIR)


## Sorted ids of every training stage in res://tutorials/.
func trainings() -> PackedStringArray:
	return _stems(TUTORIALS_DIR)


## Start stage `id`: build it from its level file. Tutorials add their lesson script.
## `testing` is the author's test flight of one of their own levels.
func open(id: String, testing := false) -> void:
	get_tree().change_scene_to_node(build(id, testing))


## The scene of stage `id`, built from its level file: a tutorial, a level, or the player's own.
func build(id: String, testing := false) -> Level:
	var data: Dictionary
	var script: Script = LevelFormat.LEVEL_SCRIPT
	if id.begins_with(MyLevels.PREFIX):
		data = MyLevels.load_level(id)
	elif id.begins_with("tutorial_"):
		data = LevelFormat.read(TUTORIALS_DIR + id + LevelFormat.EXTENSION)
		script = load(TUTORIALS_DIR + id + ".gd")
	else:
		data = LevelFormat.read(LEVELS_DIR + id + LevelFormat.EXTENSION)
	var level := LevelFormat.build(data, script)
	level.level_id = id
	level.testing = testing
	if not id.begins_with("tutorial_"):
		level.level_data = data
		level.level_sha256 = LevelFormat.sha256(data)
	return level


func _track(id: String) -> PackedStringArray:
	return trainings() if id.begins_with("tutorial_") else levels()


func _stems(dir: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(LevelFormat.EXTENSION):
			ids.append(file.trim_suffix(LevelFormat.EXTENSION))
	ids.sort()
	return ids


func points(fuel: float, hull: float, seconds: float) -> int:
	var raw := BASE_POINTS + fuel * Tuning.points_fuel + hull * Tuning.points_hull - seconds * Tuning.points_per_second
	return maxi(MIN_POINTS, roundi(raw))


## −1 when the level has not been won.
func best_points(id: String) -> int:
	return _file.get_value(id, "best_points", -1)


func best_time(id: String) -> float:
	return _file.get_value(id, "best_time", 0.0)


## Saves the run if it beats the best; returns whether it did.
func record_win(id: String, run_points: int, seconds: float) -> bool:
	if run_points <= best_points(id):
		return false
	_file.set_value(id, "best_points", run_points)
	_file.set_value(id, "best_time", seconds)
	_save()
	return true


## The demo of the best score on official level `id`, or null.
func best_demo(id: String) -> Demo:
	var found := Demo.load_file(_demo_path(id))
	return found if found and found.frame_count() > 0 else null


## Called when a run set a new best: the older demo no longer matches the score and goes first,
## so a demo too large to store leaves none rather than a stale one.
func save_best_demo(id: String, run: Demo) -> void:
	DirAccess.remove_absolute(_demo_path(id))
	run.save(_demo_path(id))


func _demo_path(id: String) -> String:
	return demos_dir + id + ".demo.gz"


## Training and levels are separate tracks: each opens in its own order, from its first stage.
func is_unlocked(id: String) -> bool:
	var ids := _track(id)
	var index := ids.find(id)
	return unlock_all or index <= 0 or best_points(ids[index - 1]) >= 0


## Whether every training stage has been finished.
func training_completed() -> bool:
	return Array(trainings()).all(func(id: String) -> bool: return best_points(id) >= 0)


## The stage after `id` on its own track, or "" for the last one.
func next_level(id: String) -> String:
	var ids := _track(id)
	var index := ids.find(id)
	return ids[index + 1] if index >= 0 and index + 1 < ids.size() else ""


## A missing or unreadable file means no progress.
func load_file() -> void:
	_file = ConfigFile.new()
	if _file.load(path) != OK:
		_file = ConfigFile.new()
	changed.emit()


func reset() -> void:
	_file = ConfigFile.new()
	for file in DirAccess.get_files_at(demos_dir) if DirAccess.dir_exists_absolute(demos_dir) else PackedStringArray():
		DirAccess.remove_absolute(demos_dir + file)
	_save()


func _save() -> void:
	_file.save(path)
	changed.emit()
