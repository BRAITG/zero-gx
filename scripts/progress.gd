extends Node
## Saved best results per stage, the points formula, and stage unlocking.
## Autoloaded as `Progress`. A stage id is its file stem, e.g. "tutorial_1" or "level_01".

signal changed

const TUTORIALS_DIR := "res://tutorials/"
const LEVELS_DIR := "res://levels/"
const BASE_POINTS := 1000
const MIN_POINTS := 100

var path := "user://progress.cfg"
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


## Every stage in play order: the tutorials, then the levels. Unlocking follows this order.
func stages() -> PackedStringArray:
	return _stems(TUTORIALS_DIR) + _stems(LEVELS_DIR)


## Start stage `id`: build it from its level file. Tutorials add their lesson script.
func open(id: String) -> void:
	get_tree().change_scene_to_node(build(id))


## The scene of stage `id`, built from its level file.
func build(id: String) -> Level:
	var tutorial := id.begins_with("tutorial_")
	var dir := TUTORIALS_DIR if tutorial else LEVELS_DIR
	var script: Script = load(dir + id + ".gd") if tutorial else LevelFormat.LEVEL_SCRIPT
	var level := LevelFormat.build(LevelFormat.read(dir + id + LevelFormat.EXTENSION), script)
	level.level_id = id
	return level


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


func is_unlocked(id: String) -> bool:
	var ids := stages()
	var index := ids.find(id)
	return unlock_all or index <= 0 or best_points(ids[index - 1]) >= 0


## The stage after `id`, or "" for the last one.
func next_level(id: String) -> String:
	var ids := stages()
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
	_save()


func _save() -> void:
	_file.save(path)
	changed.emit()
