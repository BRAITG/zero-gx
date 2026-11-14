class_name CommunityScores
extends RefCounted
## Account-owned outbox of best runs waiting to be posted, saved as one JSON file at `path` beside one replay snapshot
## file per queued run. It does no network and touches no timer or UI: `Community` owns those and adopts an answer only
## for the owner, generation and revision that sent it.
##
## File: {format, version, owners: {owner: {entries: {sha: {level, revision, bytes_sha}}, revisions: {sha: highest
## revision ever queued}}}}. One entry per owner and level version: a newer best replaces it under a higher revision,
## and revisions never repeat until erasure, so a late answer for revision 1 can never settle revision 2.
##
## Snapshots are `replay_dir(path)/<owner tag>_<sha>_<revision>.demo.gz`: copies of the encoded run made at enqueue
## time, never rewritten, so a later change of the player's saved best demo cannot alter what is sent. A snapshot is
## written before the metadata that names it and anything the metadata does not name is swept, so a failed save leaves
## the previous queue whole.

const FORMAT := "zero-gx-community-scores"
const VERSION := 1
const EMPTY := {"format": FORMAT, "version": VERSION, "owners": {}}

var path := "user://community_scores.json"
## False until a load succeeds. A file that did not load is never written, so its bytes survive.
var _ready := false
var _state: Dictionary = EMPTY.duplicate(true)
var _hex := RegEx.create_from_string("\\A[0-9a-f]+\\z")


## Where the snapshots of the metadata file `metadata_path` live.
static func replay_dir(metadata_path: String) -> String:
	return metadata_path.get_basename() + "_replays/"


## Loads `path`. A missing file is an empty outbox; any other file that is not this format and version is refused and
## left as it is, and until one loads every change is refused.
func load_file() -> Error:
	_ready = false
	_state = EMPTY.duplicate(true)
	if not FileAccess.file_exists(path):
		_ready = true
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not _valid_file(json.data):
		return ERR_INVALID_DATA
	_state = json.data
	_ready = true
	return OK


## Queues `bytes` (an encoded winning run of version `sha`, of stage `level`) for `owner`, replacing that version's
## queued run under the next revision. Saved before it returns OK; on any failure the previous queue is untouched.
func enqueue(owner: String, level: String, sha: String, bytes: PackedByteArray) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if owner.is_empty() or level.is_empty() or not _is_hex(sha, 64) or bytes.is_empty() or bytes.size() > Demo.MAX_BYTES:
		return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	var section := _section(next, owner)
	var revision: int = int(section["revisions"].get(sha, 0)) + 1
	section["revisions"][sha] = revision
	section["entries"][sha] = {"level": level, "revision": revision, "bytes_sha": CommunityWire.sha256_hex(bytes)}
	var file := _replay_path(owner, sha, revision)
	var err := _write(file, bytes)
	if err != OK:
		return err
	err = _commit(next)
	if err != OK:
		DirAccess.remove_absolute(file)
		return err
	_sweep()
	return OK


## The queued run of `owner` for version `sha`: `{sha256, level, revision}`, `{}` when there is none.
func entry(owner: String, sha: String) -> Dictionary:
	var found: Variant = _entries(owner).get(sha)
	if found == null:
		return {}
	return {"sha256": sha, "level": found["level"], "revision": int(found["revision"])}


## Every queued run of `owner`, each as `entry` describes it.
func entries(owner: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sha: String in _entries(owner):
		out.append(entry(owner, sha))
	return out


## The highest revision ever queued for `owner` and version `sha`, 0 when none.
func revision(owner: String, sha: String) -> int:
	return int(_state["owners"].get(owner, {}).get("revisions", {}).get(sha, 0))


## The snapshot bytes of exactly this revision, empty when it is not the queued one or its file is missing or damaged.
func snapshot(owner: String, sha: String, at_revision: int) -> PackedByteArray:
	var found := entry(owner, sha)
	if found.is_empty() or found["revision"] != at_revision:
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(_replay_path(owner, sha, at_revision))
	return bytes if CommunityWire.sha256_hex(bytes) == _entries(owner)[sha]["bytes_sha"] else PackedByteArray()


## The server answered for `at_revision` (posted, or refused for good): leaves the queue only that revision, with its
## snapshot. An answer for an older revision changes nothing; an erased owner or an absent entry has nothing to settle.
func settle(owner: String, sha: String, at_revision: int) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if at_revision < 1:
		return ERR_INVALID_PARAMETER
	var found := entry(owner, sha)
	if found.is_empty() or at_revision < found["revision"]:
		return OK
	if at_revision > found["revision"]:
		return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	next["owners"][owner]["entries"].erase(sha)
	var err := _commit(next)
	if err == OK:
		_sweep()
	return err


## Forgets everything held for `owner`: its queue and snapshots. Late settlement finds no entry to recreate; Community
## guards replies from a pre-erasure generation. OK only once metadata and every unreferenced snapshot are gone;
## calling it again after a failure finishes the job.
func erase_owner(owner: String) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if owner.is_empty():
		return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	next["owners"].erase(owner)
	var err := _commit(next)
	return err if err != OK else _sweep()


func _entries(owner: String) -> Dictionary:
	return _state["owners"].get(owner, {}).get("entries", {})


func _section(state: Dictionary, owner: String) -> Dictionary:
	if not state["owners"].has(owner):
		state["owners"][owner] = {"entries": {}, "revisions": {}}
	return state["owners"][owner]


func _replay_path(owner: String, sha: String, at_revision: int) -> String:
	var tag := CommunityWire.sha256_hex(owner.to_utf8_buffer()).substr(0, 16)
	return "%s%s_%s_%d.demo.gz" % [replay_dir(path), tag, sha, at_revision]


## Deletes every file of the snapshot folder that the metadata does not name (replaced or settled runs, erased owners,
## temporary files of an interrupted save). A folder that does not exist has nothing to delete; one that cannot be
## listed or emptied is an error.
func _sweep() -> Error:
	var folder := replay_dir(path)
	if not DirAccess.dir_exists_absolute(folder):
		return OK
	var named := {}
	for owner: String in _state["owners"]:
		for sha: String in _entries(owner):
			named[_replay_path(owner, sha, int(_entries(owner)[sha]["revision"]))] = true
	var names := PackedStringArray()
	var listing := DirAccess.open(folder)
	if listing == null or listing.list_dir_begin() != OK:
		return ERR_FILE_CANT_OPEN
	var file := listing.get_next()
	while file != "":
		if not listing.current_is_dir():
			names.append(file)
		file = listing.get_next()
	listing.list_dir_end()
	var result := OK
	for name in names:
		if not named.has(folder + name) and DirAccess.remove_absolute(folder + name) != OK:
			result = FAILED
	return result


## Saves `next`, then makes it the memory state. Memory is untouched when the save fails.
func _commit(next: Dictionary) -> Error:
	if next == _state:
		return OK
	var err := _write(path, JSON.stringify(next, "", false).to_utf8_buffer())
	if err == OK:
		_state = next
	return err


## Writes `bytes` to a temporary file, checks it, then renames it over `file`. Any failure leaves the old file in place.
func _write(file: String, bytes: PackedByteArray) -> Error:
	var folder := file.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		var made := DirAccess.make_dir_recursive_absolute(folder)
		if made != OK:
			return made
	var temp := file + ".tmp"
	var out := FileAccess.open(temp, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	out.store_buffer(bytes)
	out.flush()
	var err := out.get_error()
	out.close()
	if err == OK:
		err = DirAccess.rename_absolute(temp, file)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err


## The whole file, checked once at load so every later read can trust the types.
func _valid_file(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("format") != FORMAT or data.get("version") != VERSION:
		return false
	if typeof(data.get("owners")) != TYPE_DICTIONARY:
		return false
	for owner in data["owners"]:
		if not _is_text(owner) or not _is_section(data["owners"][owner]):
			return false
	return true


func _is_section(section: Variant) -> bool:
	if typeof(section) != TYPE_DICTIONARY or typeof(section.get("entries")) != TYPE_DICTIONARY or typeof(section.get("revisions")) != TYPE_DICTIONARY:
		return false
	for sha in section["revisions"]:
		if not _is_hex(sha, 64) or not _is_count(section["revisions"][sha]) or section["revisions"][sha] < 1:
			return false
	for sha in section["entries"]:
		var found: Variant = section["entries"][sha]
		if not _is_hex(sha, 64) or typeof(found) != TYPE_DICTIONARY or not _is_text(found.get("level")) or not _is_hex(found.get("bytes_sha"), 64):
			return false
		if not _is_count(found.get("revision")) or found["revision"] < 1 or found["revision"] > section["revisions"].get(sha, 0):
			return false
	return true


## A whole, non-negative number. JSON parses every number as a float, so 2.0 passes the same as 2.
func _is_count(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value >= 0 and int(value) == value


func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _is_hex(value: Variant, length: int) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == length and _hex.search(value) != null
