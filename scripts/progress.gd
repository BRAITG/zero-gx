extends Node
## Saved best results per level, the points formula, and level unlocking.
## Autoloaded as `Progress`. A level id is its file stem, e.g. "level_01".

signal changed

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


## Sorted ids of every level in res://levels/.
func levels() -> PackedStringArray:
	var ids := PackedStringArray()
	for file in ResourceLoader.list_directory(LEVELS_DIR):
		if file.ends_with(".tscn"):
			ids.append(file.get_basename())
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
	var index := levels().find(id)
	return unlock_all or index <= 0 or best_points(levels()[index - 1]) >= 0


## The level after `id`, or "" for the last one.
func next_level(id: String) -> String:
	var ids := levels()
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
