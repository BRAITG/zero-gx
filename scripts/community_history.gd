class_name CommunityHistory
extends RefCounted
## Account-owned play history and feedback outbox, saved as one JSON file at `path`.
##
## Every record belongs to the account that made it: one account never sees another's data, and an erased
## account keeps nothing. Nothing here touches the network, timers or the UI.
##
## File: {format, version, owners: {owner: {attempts: {id: {level, sha256, started_ms, revision, outcome,
## ended_ms, acked}}, clears: {sha256: true}, votes: {key: {kind, level, sha, value, revision, acked}},
## feedback: {level: {sha256: you}}}}, erased: [owner]}. `acked` is the highest revision the server has
## acknowledged or discarded; a higher revision is still pending.
##
## Progress contract (Task 6):
## - progress(owner, level, sha) is the server's last `you` block for that account and version. It is
##   confirmed data only: empty until a reply arrives, then replaced as a whole by confirm_progress.
## - batch(owner) returns only pending attempts. Acknowledged attempts stay in history but are not returned,
##   so an unconfirmed local attempt count needs a read accessor that this module does not have yet.

const FORMAT := "zero-gx-community-history"
const VERSION := 1
const MAX_BATCH := 32
const OUTCOMES := ["failed", "abandoned", "cleared"]
const DIFFICULTIES := ["easy", "normal", "hard", "expert"]
const EMPTY := {"format": FORMAT, "version": VERSION, "owners": {}, "erased": []}

var path := "user://community_history.json"
## False until a load succeeds. A file that did not load is never written, so its bytes survive.
var _ready := false
var _state: Dictionary = EMPTY.duplicate(true)
var _crypto := Crypto.new()
var _hex := RegEx.create_from_string("\\A[0-9a-f]+\\z")


## Loads `path`. A missing file is an empty history. Any other file that is not this format and version is
## refused and left as it is; until one loads, every change is refused.
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


## Records a new attempt and returns its id, saved before it is returned. "" when refused, not saved, or this
## account has already cleared `sha`.
func begin(owner: String, level: String, sha: String, started_ms: int) -> String:
	if not _ready or owner.is_empty() or level.is_empty() or not _is_hex(sha, 64) or started_ms < 0:
		return ""
	var next := _state.duplicate(true)
	var section := _activate(next, owner)
	if section["clears"].has(sha):
		return ""
	var id := _new_id()
	while section["attempts"].has(id):
		id = _new_id()
	section["attempts"][id] = {"level": level, "sha256": sha, "started_ms": started_ms, "revision": 1, "outcome": null, "ended_ms": null, "acked": 0}
	return id if _commit(next) == OK else ""


## Ends an attempt `owner` started. Repeating the same end changes nothing; a different outcome or end for a
## finished attempt is refused, so the first one stands.
func finish(owner: String, id: String, outcome: String, ended_ms: int) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if not (outcome in OUTCOMES):
		return ERR_INVALID_PARAMETER
	var attempts := _part(owner, "attempts")
	if not attempts.has(id):
		return ERR_DOES_NOT_EXIST
	var current: Dictionary = attempts[id]
	if current["revision"] == 2:
		return OK if current["outcome"] == outcome and current["ended_ms"] == ended_ms else ERR_ALREADY_EXISTS
	if ended_ms < current["started_ms"]:
		return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	var record: Dictionary = next["owners"][owner]["attempts"][id]
	record["revision"] = 2
	record["outcome"] = outcome
	record["ended_ms"] = ended_ms
	if outcome == "cleared":
		next["owners"][owner]["clears"][record["sha256"]] = true
	return _commit(next)


## The account that started `id`, or "" when it is unknown or its account was erased.
func owner_for_attempt(id: String) -> String:
	for owner in _state["owners"]:
		if _state["owners"][owner]["attempts"].has(id):
			return owner
	return ""


## Up to MAX_BATCH pending snapshots for `owner`, oldest first. Each is a fresh copy, so a batch already in
## flight does not change when its attempt is finished later.
func batch(owner: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var attempts := _part(owner, "attempts")
	for id in attempts:
		var record: Dictionary = attempts[id]
		if record["revision"] > record["acked"]:
			out.append({"id": id, "sha256": record["sha256"], "started_ms": record["started_ms"], "revision": record["revision"], "outcome": record["outcome"], "ended_ms": record["ended_ms"]})
		if out.size() == MAX_BATCH:
			break
	return out


## Applies the server's reply for `owner`. Acknowledged and discarded revisions leave the outbox but stay in
## history, and a newer pending revision stays pending. Reported clears are kept. A reply for an erased
## account changes nothing.
func acknowledge(owner: String, reply: Dictionary) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if owner.is_empty() or not _is_reply(reply):
		return ERR_INVALID_PARAMETER
	if _state["erased"].has(owner):
		return OK
	var next := _state.duplicate(true)
	var attempts: Dictionary = next["owners"].get(owner, {}).get("attempts", {})
	for entry in reply["acknowledged"] + reply["discarded"]:
		var record = attempts.get(entry["id"])
		if record != null and entry["revision"] <= record["revision"]:
			record["acked"] = max(record["acked"], entry["revision"])
	for sha in reply["cleared"]:
		_section(next, owner)["clears"][sha] = true
	return _commit(next)


## Replaces the cached feedback for one account and version with the server's latest `you` block. A clear
## it reports is kept: no later reply can undo it.
func confirm_progress(owner: String, level: String, sha: String, you: Dictionary) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if owner.is_empty() or level.is_empty() or not _is_hex(sha, 64) or not _is_you(you):
		return ERR_INVALID_PARAMETER
	if _state["erased"].has(owner):
		return OK
	var next := _state.duplicate(true)
	var section := _section(next, owner)
	if not section["feedback"].has(level):
		section["feedback"][level] = {}
	section["feedback"][level][sha] = you.duplicate(true)
	if you["cleared"]:
		section["clears"][sha] = true
	return _commit(next)


## The last confirmed `you` block for this account and version, or {} when none is cached.
func progress(owner: String, level: String, sha: String) -> Dictionary:
	var levels := _part(owner, "feedback")
	return levels.get(level, {}).get(sha, {}).duplicate(true)


## Queues this account's like for a stage. Only the latest desired value is kept, under one key.
func queue_like(owner: String, level: String, value: bool) -> Error:
	if owner.is_empty() or level.is_empty():
		return ERR_INVALID_PARAMETER
	return _desire(owner, "like:" + level, "like", level, "", value)


## Queues this account's difficulty for one version; "" queues its removal. One vote per version.
func queue_difficulty(owner: String, level: String, sha: String, value: String) -> Error:
	if owner.is_empty() or level.is_empty() or not _is_hex(sha, 64) or not (value.is_empty() or value in DIFFICULTIES):
		return ERR_INVALID_PARAMETER
	return _desire(owner, "difficulty:" + sha, "difficulty", level, sha, value)


## The votes still to send, one per key, each with its latest desired value.
func pending_votes(owner: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var votes := _part(owner, "votes")
	for key in votes:
		var vote: Dictionary = votes[key]
		if vote["revision"] > vote["acked"]:
			out.append({"key": key, "kind": vote["kind"], "level": vote["level"], "sha": vote["sha"], "value": vote["value"], "revision": vote["revision"]})
	return out


## The server applied `revision` of the vote under `key`. An older revision cannot clear a newer desired value.
## An erased account has no votes, so a late acknowledgment finds nothing.
func ack_vote(owner: String, key: String, revision: int) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if revision < 1:
		return ERR_INVALID_PARAMETER
	var votes := _part(owner, "votes")
	if not votes.has(key):
		return OK
	var vote: Dictionary = votes[key]
	if revision > vote["revision"]:
		return ERR_INVALID_PARAMETER
	if revision <= vote["acked"]:
		return OK
	var next := _state.duplicate(true)
	next["owners"][owner]["votes"][key]["acked"] = revision
	return _commit(next)


## Forgets everything held for `owner`: history, outbox and cached feedback. The account is remembered as erased,
## so late replies cannot recreate it. A later local action (a start or a vote) makes it active again.
func erase_owner(owner: String) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	if owner.is_empty():
		return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	next["owners"].erase(owner)
	if not next["erased"].has(owner):
		next["erased"].append(owner)
	return _commit(next)


## One part of an account's section, read without copying: {} when the account has none.
func _part(owner: String, part: String) -> Dictionary:
	return _state["owners"].get(owner, {}).get(part, {})


## The account's section, created when missing.
func _section(state: Dictionary, owner: String) -> Dictionary:
	if not state["owners"].has(owner):
		state["owners"][owner] = {"attempts": {}, "clears": {}, "votes": {}, "feedback": {}}
	return state["owners"][owner]


## A local action (a start or a vote) brings an erased account back. Server replies never do.
func _activate(state: Dictionary, owner: String) -> Dictionary:
	state["erased"].erase(owner)
	return _section(state, owner)


## Keeps one vote per key. A new vote starts with no value, so its first call is always a change (revision 1).
func _desire(owner: String, key: String, kind: String, level: String, sha: String, value: Variant) -> Error:
	if not _ready:
		return ERR_UNAVAILABLE
	var next := _state.duplicate(true)
	var votes: Dictionary = _activate(next, owner)["votes"]
	var vote: Dictionary = votes.get(key, {"kind": kind, "level": level, "sha": sha, "value": null, "revision": 0, "acked": 0})
	if vote["value"] != value:
		vote["value"] = value
		vote["revision"] += 1
	votes[key] = vote
	return _commit(next)


## Saves `next`, then makes it the memory state. Memory is untouched when the save fails, and unchanged state is not saved.
func _commit(next: Dictionary) -> Error:
	if next == _state:
		return OK
	var err := _save(next)
	if err == OK:
		_state = next
	return err


# shortcut: each change rewrites the whole file, so saves slow as history grows; move to one file per version once measured save stalls appear.
## Writes a temporary file, checks it, then renames it over `path`. Any failure leaves the old file in place.
func _save(data: Dictionary) -> Error:
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		var made := DirAccess.make_dir_recursive_absolute(folder)
		if made != OK:
			return made
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "", false))
	file.flush()
	var err := file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err


func _new_id() -> String:
	return _crypto.generate_random_bytes(16).hex_encode()


## The whole file, checked once at load so every later read can trust the types.
func _valid_file(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("format") != FORMAT or data.get("version") != VERSION:
		return false
	if typeof(data.get("owners")) != TYPE_DICTIONARY or typeof(data.get("erased")) != TYPE_ARRAY:
		return false
	for owner in data["erased"]:
		if not _is_text(owner):
			return false
	for owner in data["owners"]:
		if not _is_text(owner) or not _is_section(data["owners"][owner]):
			return false
	return true


func _is_section(section: Variant) -> bool:
	if typeof(section) != TYPE_DICTIONARY:
		return false
	for part in ["attempts", "clears", "votes", "feedback"]:
		if typeof(section.get(part)) != TYPE_DICTIONARY:
			return false
	for id in section["attempts"]:
		if not _is_hex(id, 32) or not _is_attempt(section["attempts"][id]):
			return false
	for sha in section["clears"]:
		if not _is_hex(sha, 64) or typeof(section["clears"][sha]) != TYPE_BOOL or not section["clears"][sha]:
			return false
	for key in section["votes"]:
		if not _is_vote(section["votes"][key]):
			return false
	for level in section["feedback"]:
		if not _is_text(level) or typeof(section["feedback"][level]) != TYPE_DICTIONARY:
			return false
		for sha in section["feedback"][level]:
			if not _is_hex(sha, 64) or not _is_you(section["feedback"][level][sha]):
				return false
	return true


func _is_attempt(attempt: Variant) -> bool:
	# batch() reads both keys directly, and get() cannot tell a missing key from null: both must be present, even when null.
	if typeof(attempt) != TYPE_DICTIONARY or not attempt.has("outcome") or not attempt.has("ended_ms") or not _is_text(attempt.get("level")) or not _is_hex(attempt.get("sha256"), 64):
		return false
	if not _is_count(attempt.get("started_ms")) or not _is_revision(attempt.get("revision")):
		return false
	if not _is_count(attempt.get("acked")) or attempt.get("acked") > attempt.get("revision"):
		return false
	if attempt.get("revision") == 1:
		return attempt.get("outcome") == null and attempt.get("ended_ms") == null
	return attempt.get("outcome") in OUTCOMES and _is_count(attempt.get("ended_ms")) and attempt.get("ended_ms") >= attempt.get("started_ms")


func _is_vote(vote: Variant) -> bool:
	if typeof(vote) != TYPE_DICTIONARY or not _is_text(vote.get("level")):
		return false
	if not _is_count(vote.get("revision")) or vote.get("revision") < 1:
		return false
	if not _is_count(vote.get("acked")) or vote.get("acked") > vote.get("revision"):
		return false
	if vote.get("kind") == "like":
		return typeof(vote.get("value")) == TYPE_BOOL and vote.get("sha") == ""
	return vote.get("kind") == "difficulty" and _is_hex(vote.get("sha"), 64) and (vote.get("value") == "" or vote.get("value") in DIFFICULTIES)


func _is_you(you: Variant) -> bool:
	return typeof(you) == TYPE_DICTIONARY and typeof(you.get("liked")) == TYPE_BOOL and typeof(you.get("like_eligible")) == TYPE_BOOL and (you.get("difficulty") == null or you.get("difficulty") in DIFFICULTIES) and typeof(you.get("difficulty_eligible")) == TYPE_BOOL and _is_count(you.get("attempts")) and typeof(you.get("cleared")) == TYPE_BOOL


## A server reply with its three lists, each entry well formed. Checked before any change, so a bad reply changes nothing.
func _is_reply(reply: Dictionary) -> bool:
	for part in ["acknowledged", "discarded"]:
		if typeof(reply.get(part)) != TYPE_ARRAY:
			return false
		for entry in reply[part]:
			if typeof(entry) != TYPE_DICTIONARY or not _is_hex(entry.get("id"), 32) or not _is_revision(entry.get("revision")):
				return false
	if typeof(reply.get("cleared")) != TYPE_ARRAY:
		return false
	for sha in reply["cleared"]:
		if not _is_hex(sha, 64):
			return false
	return true


func _is_revision(value: Variant) -> bool:
	return _is_count(value) and (value == 1 or value == 2)


## A whole, non-negative number. JSON parses every number as a float, so 2.0 passes the same as 2.
func _is_count(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value >= 0 and int(value) == value


func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _is_hex(value: Variant, length: int) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == length and _hex.search(value) != null
