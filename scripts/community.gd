extends Node
## The community client: every call to the community server, the session token and the download cache. Autoloaded as `Community`. Screens call it and show what it returns; it never touches UI. Failures come back as one sentence.

const NO_CONNECTION := "No connection"
const BAD_ANSWER := "The server's answer could not be read."
const NOT_SUBMITTABLE := "This level cannot be submitted."
const SESSION_SECONDS := 6 * 24 * 60 * 60  # the server's sessions last 7 days; sign in again a day early
const LEVEL_URL := "https://cdn.jsdelivr.net/gh/BRAITG/zero-gx-levels@%s/levels/%s/v%d.json"
## A downloaded level is played as stage `community_<sha256>`, built from its cached file.
const STAGE_PREFIX := "community_"
const SIGNED_OUT := "You are signed out."
const ACCOUNT_CHANGED := "Another account is signed in now."
const NO_HISTORY := "Your play history could not be read."
const HISTORY_UNSAVED := "Your play history could not be saved on this device. It will be tried again."
const BAD_LEVEL := "This level cannot be rated."
## Play-report uploads (and a retry after a failed vote) are at least this far apart. Only future scheduling waits: no request is ever held back for it.
const FLUSH_GAP_SECONDS := 30.0
const MAX_REPORT_BYTES := 16384  # the server refuses a larger report
const FEEDBACK_TRIES := 5  # counted tries that open the rating of a version without a clear
const ERASURE_PENDING := "This device could not finish erasing your community data yet. It will be tried again."
const ERASURE_UNSAVED := "Your account was not deleted: this device could not record the deletion."

var transport: CommunityTransport
var platform: CommunityPlatform
## Downloaded levels (`<sha256>.json`) and the last fetched list pages.
var dir := "user://community/"
## The session token with its expiry, and the last known submission statuses.
var session_path := "user://community.cfg"
var api_url: String = ProjectSettings.get_setting("community/api_url", "https://zerogx.braitg.dev")
## The account-owned play history and feedback outbox; independent of the session file.
var history_path := "user://community_history.json"

var _level_id := RegEx.create_from_string("\\Alvl_[a-z0-9]{10}\\z")  # the server's level ids
var _http: CommunityTransport
var _signing_in := false  # one sign-in at a time; `_sign_in_done` hands its result to the callers that came meanwhile
var _history: CommunityHistory  # loaded on first use from `history_path`; null until then
var _activated := false  # the community was entered this launch: only then may reports go out by themselves
var _flushing := false  # one flush at a time
var _gaps := {"plays": false, "votes": false, "retry": false}  # true while that kind of request waits out its gap; see `_start_gap`
var _generation := 0  # bumped by a reset and by an account deletion: work begun before it writes and retries nothing after it
var _deleting := false  # a deletion is with the server: its local erasure is owed but must not start before the answer
var _choices := {}  # target of a vote → serial of the latest call for it
var _choice_serial := 0
var _settlements := {}  # "account|vote key" → {revision, status, error}: an answer the server gave for a queued choice whose acknowledgment could not be saved. Memory only: a reset or a relaunch forgets it and the choice is simply sent again, as after a lost answer.

signal _sign_in_done(error: String)
## One attempt at a queued choice, after its owner and generation were checked: applied (`error` empty), refused for good (the choice is dropped) or kept for a later flush. `kind` is "like" or "difficulty"; `sha256` is "" for a like; `value` is the choice (bool, or the difficulty with "" for a removal).
signal vote_result(account: String, kind: String, level: String, sha256: String, value: Variant, error: String)
## The server acknowledged durably saved play reports of `account` on version `sha256`, once per version and upload: its eligibility may have changed.
signal play_history_synced(account: String, sha256: String)
## The persisted player of this device changed (a sign-in as someone else) or was erased: `account` is the one now, "" when none. Open sheets drop what they show of the previous one.
signal identity_changed(account: String)


func _ready() -> void:
	_http = CommunityTransport.new()
	add_child(_http)
	use_defaults()


## The real transport and this device's platform; what tests restore after swapping in fakes. It also ends everything that was under way: timers, an upload in flight, the explicit activation and the loaded history.
func use_defaults() -> void:
	transport = _http
	platform = CommunityAndroid.new(self) if OS.has_feature("android") else CommunityPlatform.new()
	_reset_work()
	_activated = false
	_history = null
	_deleting = false
	_choices.clear()


## Whether this device can use community at all (Android with Play Games).
func available() -> bool:
	return platform.available()


func signed_in() -> bool:
	return _token() != ""


## Coroutine: `""` once signed in, else why not. A call that comes while a sign-in is under way waits for that one and gets its result.
func sign_in() -> String:
	if _signing_in:
		return await _sign_in_done
	_signing_in = true
	var error := await _sign_in()
	_signing_in = false
	_sign_in_done.emit(error)
	return error


func _sign_in() -> String:
	if not platform.available():
		return CommunityPlatform.UNAVAILABLE  # a device without Play Games makes no request at all
	var generation := _generation
	var nonce := await _nonce()  # before Play Games: offline must fail at once, not after a prompt
	if nonce.has("error"):
		return nonce.error
	var auth: Dictionary = await platform.sign_in()
	if auth.has("error"):
		return auth.error
	var proof: Dictionary = await platform.integrity(nonce.nonce)
	if proof.has("error"):
		return proof.error
	if generation != _generation:
		return SIGNED_OUT  # the account was deleted while Play Games was asking: no session for it, on the server or here
	var body := JSON.stringify({"authCode": auth.auth_code, "integrityToken": proof.token, "nonce": nonce.nonce}).to_utf8_buffer()
	var reply := await _call("POST", api_url + "/session", PackedStringArray(["Content-Type: application/json"]), body)
	if reply.has("error"):
		return reply.error
	if not reply.data.get("token") is String:
		return BAD_ANSWER
	if generation != _generation:
		return SIGNED_OUT
	var before := player_id()
	var file := _session()  # keeps the last known statuses
	file.set_value("session", "token", reply.data.token)
	file.set_value("session", "expires", int(Time.get_unix_time_from_system()) + SESSION_SECONDS)
	var player: Variant = reply.data.get("player")
	var id: Variant = player.get("id") if player is Dictionary else null
	if id is String and id != "":
		file.set_value("player", "id", id)  # who this device's play history belongs to; kept when a 401 drops the token
	elif file.has_section("player"):
		file.erase_section("player")  # a token whose player is not known must not keep the previous one's name
	_save_session(file)
	_announce_identity(before)
	return ""


## Coroutine: one page of `sort` ("top" or "new"): `{"rows": Array}`, or on failure `{"error", "rows": the cached page or [], "offline": bool}`.
func list(sort: String, page: int) -> Dictionary:
	var cache := dir + "list_%s_%d.json" % [sort, page]
	var reply := await _authed("GET", "/levels?sort=%s&page=%d" % [sort, page], TYPE_ARRAY)
	if reply.has("error"):
		var cached: Variant = _parse(FileAccess.get_file_as_bytes(cache))
		return {"error": reply.error, "rows": cached if cached is Array else [], "offline": reply.error == NO_CONNECTION}
	_store(cache, JSON.stringify(reply.data).to_utf8_buffer())
	return {"rows": reply.data}


## Where the level with this hash is (or will be) cached.
func level_path(sha256: String) -> String:
	return dir + sha256 + ".json"


## Coroutine: makes sure the level of a `list` row is cached; `""` when it is there and verified, else why not. A file whose hash differs from the row's is rejected and kept nowhere. The row's stable level id and version are saved beside it as public metadata, on a cache hit too. The levels CDN is called without the session.
func download(row: Dictionary) -> String:
	var path := level_path(row.sha256)
	if FileAccess.file_exists(path) and CommunityWire.sha256_hex(FileAccess.get_file_as_bytes(path)) == row.sha256:
		_save_meta(row)
		return ""
	var index := await _authed("GET", "/index")
	if index.has("error"):
		return index.error
	if not index.data.get("commit") is String:
		return BAD_ANSWER
	var file := await _call("GET", LEVEL_URL % [index.data.commit, row.level_id, row.latest], PackedStringArray(), PackedByteArray(), TYPE_PACKED_BYTE_ARRAY)
	if file.has("error"):
		return file.error
	if CommunityWire.sha256_hex(file.data) != row.sha256:
		return "The downloaded file did not match the level list."
	if not _store(path, file.data):
		return "The level could not be saved."
	_save_meta(row)
	return ""


## Whether the draft `id` can go to the server: a platform with Play Games, and a finishing demo that still matches the draft.
func can_submit(id: String) -> bool:
	return available() and MyLevels.demo(id) != null


## Coroutine: sends draft `id` with its demo; `""` once the server took it, else its sentence. The returned level id is kept for the draft, so a later submission becomes the next version of the same level; the sent content's hash too, which marks the draft as submitted until it changes.
func submit(id: String, suggested_difficulty := "") -> String:
	if not can_submit(id) or not (suggested_difficulty == "" or suggested_difficulty in CommunityHistory.DIFFICULTIES):
		return NOT_SUBMITTABLE
	var level := LevelFormat.to_json(MyLevels.load_level(id)).to_utf8_buffer()
	var demo := FileAccess.get_file_as_bytes(MyLevels.demo_path(id))
	var reply := await _authed("POST", "/submissions", TYPE_DICTIONARY, _submission.bind(level, demo, level_id_of(id), suggested_difficulty))
	if reply.has("error"):
		return reply.error
	if reply.data.get("level_id") is String:
		MyLevels.set_level_id(id, reply.data.level_id)
	MyLevels.set_submitted(id, CommunityWire.sha256_hex(level))  # the bytes that were sent, not what the draft is by now
	return ""


## The community level id of draft `id`, "" when it was never submitted.
func level_id_of(id: String) -> String:
	return MyLevels.level_id(id)


## Coroutine: level id → `{status, version, comment}` of the player's newest submission of it. Refreshed while signed in; otherwise, or when the refresh fails, the last known ones. It never signs in: a 401 only clears the local session.
func statuses() -> Dictionary:
	var known: Variant = _session().get_value("statuses", "last", {})
	if not signed_in():
		return known if known is Dictionary else {}
	var reply := await _authed("GET", "/me/submissions", TYPE_ARRAY, Callable(), false)
	if reply.has("error"):
		return known if known is Dictionary else {}
	var fresh := {}
	for row: Variant in reply.data:  # newest first: a level's first row is where it stands
		if row is Dictionary and row.get("level_id") is String and not fresh.has(row.level_id):
			fresh[row.level_id] = {"status": row.get("status"), "version": int(row.get("version", 0)), "comment": row.get("comment") if row.get("comment") is String else ""}
	var file := _session()  # read afresh: a sign-in may have rewritten it meanwhile
	file.set_value("statuses", "last", fresh)
	_save_session(file)
	return fresh


## The player this device's session belongs to: the id the server's last `/session` answer named. "" for a session saved before that was stored, a signed-out one and an erased one.
func player_id() -> String:
	var id: Variant = _session().get_value("player", "id", "")
	return id if id is String else ""


## The community (or Submit) was entered this launch: from now on reports may go out by themselves, spaced by `FLUSH_GAP_SECONDS`. It makes no request and records no play.
func activate_feedback() -> void:
	_finish_erasure()
	_activated = true
	_schedule()


## Records the start of a counted attempt of the downloaded version `sha256` for the signed-in player; returns its id, "" when nothing was recorded (no Play Games, no known player, a level without saved metadata, a version already cleared, or a history that cannot be written). Makes no request unless the community was entered.
func record_play_start(sha256: String) -> String:
	var account := _account()
	var level: String = level_info(sha256).get("level_id", "")
	var history := _hist()
	if account == "" or level == "" or history == null or not available():
		return ""
	var id := history.begin(account, level, sha256, _now_ms())
	_schedule()
	return id


## Ends attempt `id` for the account that started it, whoever is signed in now. An unknown or erased attempt changes nothing.
func record_play_finish(id: String, outcome: String) -> void:
	var history := _hist()
	var account := history.owner_for_attempt(id) if history != null and id != "" else ""
	if account == "" or _blocked(account):
		return
	history.finish(account, id, outcome, maxi(_now_ms(), history.started_ms(account, id)))  # a clock set back since the start must not lose the result
	_schedule()


## UI-only progress: local/confirmed starts, clear and pending state. Rate discovery estimates confirmed starts plus local starts made after the last read began; overlapping reads/uploads can offer early, and ambiguous earlier starts can offer late. The sheet and server still enforce confirmed voting eligibility.
func play_progress(sha256: String) -> Dictionary:
	var account := _account()
	var level: String = level_info(sha256).get("level_id", "")
	var history := _hist()
	var local := {"attempts": 0, "uncovered": 0, "cleared": false, "pending_starts": 0, "pending": false}
	var confirmed := {}
	if account != "" and level != "" and history != null:
		local = history.local_progress(account, level, sha256)
		confirmed = history.progress(account, level, sha256)
	var cleared: bool = local.cleared or confirmed.get("cleared", false)
	var tries := maxi(int(local.attempts), int(confirmed.get("attempts", 0)) + int(local.uncovered))
	return {"local_attempts": local.attempts, "confirmed_attempts": int(confirmed.get("attempts", 0)), "cleared": cleared, "pending": local.pending, "can_offer_rating": cleared or tries >= FEEDBACK_TRIES}


## Coroutine: the feedback payload of version `sha256` of stage `level`, as the server sent it, plus `offline: false`. Without an answer it is this player's cached payload with `error` and `offline` (true for no connection), or just `{error, offline}` when there is none. The client never recomputes an aggregate.
func feedback(level: String, sha256: String) -> Dictionary:
	if not available():
		return {"error": CommunityPlatform.UNAVAILABLE, "offline": false}
	if _level_id.search(level) == null or not _is_sha(sha256):
		return {"error": BAD_LEVEL, "offline": false}
	_finish_erasure()
	if _blocked(player_id()):
		return {"error": ERASURE_PENDING, "offline": false}
	var generation := _generation
	var started := player_id()
	var history := _hist()
	var seen: Array = history.start_ids(started, level, sha256) if history != null and started != "" else []  # discovery cutoff, not a server snapshot: concurrent uploads may already be in the answer
	var reply := await _authed("GET", "/levels/%s/feedback?sha256=%s" % [level, sha256])
	if generation != _generation:
		return {"error": SIGNED_OUT, "offline": false}
	var account: String = reply.get("account", "")
	var changed := account != "" and player_id() != account  # the session changed while the read was out: the answer is of a player who is not signed in now
	if account != "" and _blocked(account):
		reply = {"error": ERASURE_PENDING}  # nothing of an account whose erasure is owed is cached or confirmed
	if not reply.has("error") and not _feedback_valid(reply.data, level, sha256):
		reply = {"error": BAD_ANSWER}
	elif not reply.has("error") and account != "" and history != null and history.confirm_progress(account, level, sha256, reply.data.you, seen if account == started else []) == ERR_INVALID_PARAMETER:
		reply = {"error": BAD_ANSWER}
	if reply.has("error"):
		if changed:
			return {"error": ACCOUNT_CHANGED, "offline": false}  # nor is the cached copy of the account that is signed in now
		var stale := _cached_feedback(_account(), level, sha256)
		stale["error"] = reply.error
		stale["offline"] = reply.error == NO_CONNECTION
		return stale
	if account != "":
		_store(_feedback_path(account, sha256), JSON.stringify(reply.data).to_utf8_buffer())  # the account that was sent, not whoever is signed in now
	if changed:
		return {"error": ACCOUNT_CHANGED, "offline": false}  # another player is signed in now: nothing of this answer is theirs
	var fresh: Dictionary = reply.data.duplicate()
	fresh["offline"] = false
	return fresh


## The choices of this player that are queued, not yet applied: `like` (bool) and `difficulty` (String, "" a removal), each present only while queued.
func pending_feedback(level: String, sha256: String) -> Dictionary:
	var out := {}
	var history := _hist()
	var account := _account()
	if history == null or account == "":
		return out
	for vote: Dictionary in history.pending_votes(account):
		if vote.level != level:
			continue
		if vote.kind == "like":
			out["like"] = vote.value
		elif vote.sha == sha256:
			out["difficulty"] = vote.value
	return out


## Coroutine: sends what is queued, plays first. `{error: String, pending: bool}`: `pending` is true while anything is still queued (offline, a server or rate-limit failure, a flush already under way, or the gap between uploads), `error` the sentence of a failure or of a refusal; a refused choice is dropped and the confirmed state stays. Within the gap it answers at once.
func sync_feedback() -> Dictionary:
	_finish_erasure()
	return await _sync()


## Coroutine: likes (`value`) or unlikes stage `level`; same result as `sync_feedback`, with `error` the sentence of this choice's own attempt.
func set_like(level: String, value: bool) -> Dictionary:
	return await _vote(level, "like:" + level, "like", "", value, func(history: CommunityHistory, account: String) -> Error: return history.queue_like(account, level, value))


## Coroutine: sets (or, with "", removes) the vote on the difficulty of version `sha256` of stage `level`; same result as `sync_feedback`, with `error` the sentence of this vote's own attempt.
func set_difficulty(level: String, sha256: String, value: String) -> Dictionary:
	return await _vote(level, "difficulty:" + sha256, "difficulty", sha256, value, func(history: CommunityHistory, account: String) -> Error: return history.queue_difficulty(account, level, sha256, value))


## The public metadata saved beside a downloaded version: `{level_id, version}`, `{}` when unknown or not valid.
func level_info(sha256: String) -> Dictionary:
	if not _is_sha(sha256) or not FileAccess.file_exists(_meta_path(sha256)):
		return {}
	var meta: Variant = _parse(FileAccess.get_file_as_bytes(_meta_path(sha256)))
	if not meta is Dictionary or not _meta_valid(meta.get("level_id"), meta.get("version")):
		return {}
	return {"level_id": meta.level_id, "version": int(meta.version)}


## Coroutine: deletes the player's community account on the server; `""` once it is gone and the session, statuses, draft level ids, submitted marks, play history, queued votes and private feedback are cleared here too (downloaded public levels stay), else a sentence. Work that was under way (an upload, a sign-in, a feedback read) can no longer write anything or retry. The local erasure is owed from before the request: it is recorded in the session file first (no record, no request). When it cannot be finished here, the answer is a sentence about this device's cleanup only (the server's answer may be unknown, for example after an interrupted request), nothing of that account is recorded, shown, cached or sent, and the next explicit community action tries again. A deletion the server refused keeps everything, unless taking back the record also failed.
func delete_account() -> String:
	if not _finish_erasure():
		return ERASURE_PENDING
	var account := player_id()
	if account == "":  # a session saved before the player was stored: learn who it is, so what is owed here has a name
		var error := await sign_in()
		if error != "":
			return error
		account = player_id()
		if account == "":
			return BAD_ANSWER
	if _mark_erasure(account) != OK:
		return ERASURE_UNSAVED
	_deleting = true
	_reset_work()
	var reply := await _authed("DELETE", "/me", TYPE_NIL, Callable(), true, account)
	_deleting = false
	if reply.has("error"):
		_unmark_erasure()
		return reply.error
	_reset_work()
	for id in MyLevels.ids():
		MyLevels.set_level_id(id, "")
		MyLevels.set_submitted(id, "")
	if _complete_erasure(account):
		DirAccess.remove_absolute(session_path)  # holds the session, the player id, the statuses and the mark
		_announce_identity(account)
		return ""
	var owed := ConfigFile.new()  # no token, no player, no statuses: only what is still owed
	owed.set_value("erasure", "owner", account)
	_save_session(owed)
	_announce_identity(account)
	return ERASURE_PENDING


## The stored session token, "" when there is none or it has expired.
func _token() -> String:
	var file := _session()
	var token: Variant = file.get_value("session", "token", "")
	var expires: Variant = file.get_value("session", "expires", 0)
	return token if token is String and (expires is int or expires is float) and expires > Time.get_unix_time_from_system() else ""


func _session() -> ConfigFile:
	var file := ConfigFile.new()
	file.load(session_path)  # missing means signed out
	return file


func _store(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	return true


func _parse(bytes: PackedByteArray) -> Variant:
	var json := JSON.new()  # unlike parse_string, the instance parse does not log bad input
	return json.data if json.parse(bytes.get_string_from_utf8()) == OK else null


## A fresh one-time nonce, `{"nonce": String}` or `{"error": String}`. The server uses a nonce up when it checks it, even when the request fails, so every call that needs one fetches its own.
func _nonce() -> Dictionary:
	var reply := await _call("GET", api_url + "/nonce")
	if reply.has("error"):
		return reply
	return reply.data if reply.data.get("nonce") is String else {"error": BAD_ANSWER}


## One request. A 2xx answer is `{"status", "data"}` with `data` parsed as JSON of type `expect` (TYPE_NIL: no body; TYPE_PACKED_BYTE_ARRAY: the raw bytes); anything else is `{"status", "error"}` with the server's sentence.
func _call(method: String, url: String, headers := PackedStringArray(), body := PackedByteArray(), expect := TYPE_DICTIONARY) -> Dictionary:
	var reply: Dictionary = await transport.send(method, url, headers, body)
	var status: int = reply.status
	if status == 0:
		return {"status": 0, "error": NO_CONNECTION}
	if status < 200 or status > 299:
		var failure: Variant = _parse(reply.body)
		var sentence: Variant = failure.get("error") if failure is Dictionary else null
		return {"status": status, "error": sentence if sentence is String and sentence != "" else "The server answered %d." % status}
	var data: Variant = reply.body if expect == TYPE_PACKED_BYTE_ARRAY else _parse(reply.body)
	return {"status": status, "data": data} if typeof(data) == expect else {"status": status, "error": BAD_ANSWER}


## `_call` to the community server with the session. A 401 clears the token that was sent; with `resign` it then signs in again once and retries once, unless the account was deleted meanwhile. `build` is an optional coroutine that makes `{"headers", "body"}` afresh for each attempt (or `{"error"}`). A non-empty `account` is the only player the request may go out as: the retry, which may have signed in as someone else, stops before it builds or sends anything.
func _authed(method: String, path: String, expect := TYPE_DICTIONARY, build := Callable(), resign := true, account := "") -> Dictionary:
	var generation := _generation
	var reply := await _send(method, path, expect, build, account)
	if reply.status == 401:
		_forget(reply.token)
		if resign and generation == _generation:
			reply = await _send(method, path, expect, build, account)
	return reply


## Drops the stored session when it still holds `token`, which the server no longer accepts. A token that a sign-in saved meanwhile stays.
func _forget(token: String) -> void:
	var file := _session()
	if file.has_section_key("session", "token") and file.get_value("session", "token") == token:
		file.erase_section("session")
		_save_session(file)


## One authorized request; the answer carries the `token` it was sent with and the `account` that token belongs to.
func _send(method: String, path: String, expect: int, build: Callable, account := "") -> Dictionary:
	var generation := _generation
	if _token() == "":
		var error := await sign_in()
		if error != "":
			return {"status": 0, "error": error}
	var stale := _stale(account, generation)
	if stale != "":
		return {"status": 0, "error": stale}
	var headers := PackedStringArray()
	var body := PackedByteArray()
	if build.is_valid():
		var made: Dictionary = await build.call()
		if made.has("error"):
			return {"status": 0, "error": made.error}
		headers = made.headers
		body = made.body
		stale = _stale(account, generation)  # the build awaited: the session may have changed under it
		if stale != "":
			return {"status": 0, "error": stale}
	var token := _token()
	var sender := player_id()
	headers.append("Authorization: Bearer " + token)
	var reply := await _call(method, api_url + path, headers, body, expect)
	reply["token"] = token
	reply["account"] = sender
	return reply


## Why a request made for `account` after `generation` must not go out now, "" when it may.
func _stale(account: String, generation: int) -> String:
	if generation != _generation:
		return SIGNED_OUT
	return ACCOUNT_CHANGED if account != "" and player_id() != account else ""


## The headers and multipart body of one submission attempt: a fresh nonce, and an integrity token bound to this nonce and these exact bytes. A suggested difficulty is the optional third bound part; without one the binding is the two-part protocol.
func _submission(level: PackedByteArray, demo: PackedByteArray, level_id: String, suggested_difficulty: String) -> Dictionary:
	var nonce := await _nonce()
	if nonce.has("error"):
		return nonce
	var parts: Array[PackedByteArray] = [level, demo]
	var fields := {}
	if level_id != "":
		fields["level_id"] = level_id
	if suggested_difficulty != "":
		parts.append(suggested_difficulty.to_utf8_buffer())
		fields["suggested_difficulty"] = suggested_difficulty
	var proof: Dictionary = await platform.integrity(CommunityWire.bound_nonce(nonce.nonce, parts))
	if proof.has("error"):
		return proof
	var boundary := Crypto.new().generate_random_bytes(16).hex_encode()  # random, so it cannot occur in the payload
	return {
		"headers": PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary, "X-Nonce: " + nonce.nonce, "X-Integrity: " + proof.token]),
		"body": CommunityWire.multipart(fields, {"level": ["level.json", level], "demo": ["demo.gz", demo]}, boundary),
	}


# --- play history, feedback and votes ---------------------------------------------------------------------------------


func _hist() -> CommunityHistory:
	if _history == null:
		var loaded := CommunityHistory.new()
		loaded.path = history_path
		if loaded.load_file() != OK:
			return null  # a history that did not load is never written: its bytes survive
		_history = loaded
	return _history


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _is_sha(text: String) -> bool:
	return text.length() == 64 and text == text.to_lower() and text.is_valid_hex_number()


## Ends everything under way: timers and awaiting work see another generation and do nothing more.
func _reset_work() -> void:
	_generation += 1
	_flushing = false
	_settlements.clear()
	for kind in _gaps:
		_gaps[kind] = false


## Whether this account has anything queued for the server.
func _queued() -> bool:
	var history := _hist()
	var account := _account()
	return history != null and account != "" and not (history.batch(account).is_empty() and history.pending_votes(account).is_empty())


## Whether a flush could send something right now: pending plays when their gap is over, else pending votes when theirs is.
func _runnable() -> bool:
	var history := _hist()
	var account := _account()
	if history == null or account == "" or not available():
		return false
	if not history.batch(account).is_empty():
		return not _gaps.plays
	return not history.pending_votes(account).is_empty() and not _gaps.votes


## Starts a flush by itself when the community was entered and there is something to send; the gaps decide when.
func _schedule() -> void:
	if _activated and not _flushing and _runnable():
		_background.call_deferred(_generation)


## The flush `_schedule` asked for, one idle frame later. A Level that leaves its tree schedules one, and no request may begin inside that exit. A reset or deletion since then drops it, and so does a flush already under way.
func _background(generation: int) -> void:
	if generation == _generation and not _flushing and _runnable():
		await _sync()


## `kind` of request ("plays" uploads, "votes" retries, "retry" a flush that left work behind) must not repeat for `FLUSH_GAP_SECONDS`. Only what follows waits: the timer runs on its own, so no request is ever held for it, and a reset makes it inert.
func _start_gap(kind: String) -> void:
	_gaps[kind] = true
	var generation := _generation
	get_tree().create_timer(FLUSH_GAP_SECONDS).timeout.connect(func() -> void:
		if generation == _generation:
			_gaps[kind] = false
			_schedule())


## One flush at a time; a call that comes meanwhile, or that plays must wait for, answers Pending sync at once.
func _sync() -> Dictionary:
	if not available():
		return {"error": CommunityPlatform.UNAVAILABLE, "pending": false}
	if _flushing:
		return {"error": "", "pending": _queued()}
	_flushing = true
	var generation := _generation
	var result := await _flush(generation)
	if generation == _generation:
		_flushing = false
		if _activated and _queued() and not (_gaps.plays or _gaps.votes or _gaps.retry):
			_start_gap("retry")  # work is left and no timer will come for it
	return result


## Who plays: the stored player, else (a session saved before the player was stored, or none) a fresh sign-in. Only explicit community actions ask. `{"account", "error"}`.
func _identify() -> Dictionary:
	var account := player_id()
	var error := ""
	if account == "":
		error = await sign_in()
		account = player_id()
	return {"account": account, "error": "" if account != "" else (error if error != "" else BAD_ANSWER)}


## The body of `_sync`: one batch of plays, then (once no play waits) every queued vote. `{"error", "pending"}`: `error` is the first sentence a retained failure or a refusal gave, `pending` whether anything is still queued.
func _flush(generation: int) -> Dictionary:
	var gone := {"error": SIGNED_OUT, "pending": false}
	var history := _hist()
	if history == null:
		return {"error": NO_HISTORY, "pending": false}
	var who := await _identify()
	if generation != _generation:
		return gone
	var account: String = who.account
	if account == "":
		return {"error": who.error, "pending": false}
	if _blocked(account):
		return {"error": ERASURE_PENDING, "pending": false}
	if not history.batch(account).is_empty():
		if _gaps.plays:
			return {"error": "", "pending": true}
		_start_gap("plays")
		var failure := await _upload(history, account, generation)
		if generation != _generation:
			return gone
		if failure != "" or not history.batch(account).is_empty():
			return {"error": failure, "pending": true}  # votes wait for the plays they need
	if _gaps.votes:
		return {"error": "", "pending": _queued()}
	var refused := ""
	for vote: Dictionary in history.pending_votes(account):
		var key := account + "|" + String(vote.key)
		var reply: Dictionary = _settlements.get(key, {})
		if reply.get("revision", 0) != int(vote.revision):  # no answer is known for this very revision: ask the server
			reply = await _send_vote(vote, account)
			if generation != _generation:
				return gone
		var status: int = reply.get("status", 0)
		var error: String = reply.get("error", "")
		if error == "" or _refused(status):
			if history.ack_vote(account, vote.key, int(vote.revision)) != OK:
				_settlements[key] = {"revision": int(vote.revision), "status": status, "error": error}  # the answer is known: only its local settlement is retried, never the request
				_start_gap("votes")
				vote_result.emit(account, vote.kind, vote.level, vote.sha, vote.value, HISTORY_UNSAVED)
				return {"error": HISTORY_UNSAVED, "pending": true}
			_settlements.erase(key)
			if error != "" and refused == "":
				refused = error
			vote_result.emit(account, vote.kind, vote.level, vote.sha, vote.value, error)  # applied, or never to be: either way this choice is done, and a newer one stays queued
		else:
			_start_gap("votes")  # connection, server and rate-limit failures keep the choice for a later flush
			vote_result.emit(account, vote.kind, vote.level, vote.sha, vote.value, error)
			return {"error": error, "pending": true}
	return {"error": refused, "pending": _queued()}


## A 4xx the server will give again however often it is asked, apart from the ones a later try can change.
func _refused(status: int) -> bool:
	return status >= 400 and status < 500 and not (status in [401, 408, 429])


## Uploads the oldest batch; `""` once the server answered and its acknowledgments were applied, else why not (the batch stays queued).
func _upload(history: CommunityHistory, account: String, generation: int) -> String:
	var sent := {}
	var reply := await _authed("POST", "/plays", TYPE_DICTIONARY, _plays_request.bind(account, sent), true, account)
	if reply.has("error"):
		return reply.error
	if generation != _generation:
		return ""
	var acknowledged := _sent_only(reply.data, sent)
	if history.acknowledge(account, acknowledged) != OK:
		return BAD_ANSWER
	var hashes := {}
	for part in ["acknowledged", "discarded"]:
		for entry: Dictionary in acknowledged[part]:
			hashes[sent[entry.id].sha256] = true
	for sha: String in hashes:
		play_history_synced.emit(account, sha)  # once per version, after the acknowledgments are durable
	return ""


## One report attempt, made afresh each time: a fresh nonce, the oldest pending snapshots of `account` (at most 32 and `MAX_REPORT_BYTES`) and an integrity token bound to exactly those bytes. `sent` receives what went in: id → snapshot.
func _plays_request(account: String, sent: Dictionary) -> Dictionary:
	var nonce := await _nonce()
	if nonce.has("error"):
		return nonce
	var history := _hist()
	var snapshots: Array[Dictionary] = []
	var body := PackedByteArray()
	sent.clear()
	for record in history.batch(account) if history != null else []:
		snapshots.append({"id": record.id, "sha256": record.sha256, "started_ms": int(record.started_ms), "revision": int(record.revision), "outcome": record.outcome, "ended_ms": null if record.ended_ms == null else int(record.ended_ms)})
		var next := JSON.stringify({"player_id": account, "attempts": snapshots}).to_utf8_buffer()
		if next.size() > MAX_REPORT_BYTES:
			snapshots.pop_back()
			break
		body = next
	if snapshots.is_empty():
		return {"error": SIGNED_OUT}  # the account's history is gone
	for snapshot in snapshots:
		sent[snapshot.id] = snapshot
	var parts: Array[PackedByteArray] = [body]
	var proof: Dictionary = await platform.integrity(CommunityWire.bound_nonce(nonce.nonce, parts))
	if proof.has("error"):
		return proof
	return {"headers": PackedStringArray(["Content-Type: application/json", "X-Nonce: " + nonce.nonce, "X-Integrity: " + proof.token]), "body": body}


## The server's reply to a report, cut down to what was sent: only an id with the revision that went out is acknowledged, only a hash that went out is reported cleared. A reply that is not well formed stays as it is: the history refuses it whole.
func _sent_only(reply: Dictionary, sent: Dictionary) -> Dictionary:
	var out := reply.duplicate()
	for part in ["acknowledged", "discarded"]:
		if reply.get(part) is Array:
			out[part] = reply[part].filter(func(entry: Variant) -> bool: return entry is Dictionary and sent.has(entry.get("id")) and sent[entry.get("id")].revision == entry.get("revision"))
	if reply.get("cleared") is Array:
		out["cleared"] = reply["cleared"].filter(func(sha: Variant) -> bool: return sent.values().any(func(snapshot: Dictionary) -> bool: return snapshot.sha256 == sha))
	return out


## One queued choice as a request. Likes and difficulty votes need only the session.
func _send_vote(vote: Dictionary, account: String) -> Dictionary:
	var base := "/levels/%s/" % String(vote.level).uri_encode()
	if vote.kind == "like":
		return await _authed("POST" if vote.value else "DELETE", base + "like", TYPE_DICTIONARY, Callable(), true, account)
	if vote.value == "":
		return await _authed("DELETE", base + "difficulty?sha256=" + String(vote.sha), TYPE_DICTIONARY, Callable(), true, account)
	var body := JSON.stringify({"sha256": vote.sha, "difficulty": vote.value}).to_utf8_buffer()
	var build := func() -> Dictionary: return {"headers": PackedStringArray(["Content-Type: application/json"]), "body": body}
	return await _authed("PUT", base + "difficulty", TYPE_DICTIONARY, build, true, account)


## Queues one choice (`kind` "like" or "difficulty", of version `sha256` for the latter, to `value`) for the signed-in player (signing in first when the player is not known yet), then tries one flush. The answer is `_sync`'s, except that `error` is the sentence of this very choice's attempt when the flush made one. `key` names the target of the choice: of two calls for one target, only the later one may queue, whichever resumes first from a shared sign-in.
func _vote(level: String, key: String, kind: String, sha256: String, value: Variant, queue: Callable) -> Dictionary:
	if not available():
		return {"error": CommunityPlatform.UNAVAILABLE, "pending": false}
	if _level_id.search(level) == null:
		return {"error": BAD_LEVEL, "pending": false}
	_finish_erasure()
	var generation := _generation
	_choice_serial += 1
	var order := _choice_serial
	_choices[key] = order
	var who := await _identify()
	if generation != _generation:
		return {"error": SIGNED_OUT, "pending": false}
	if _choices.get(key) != order:
		return {"error": "", "pending": true}  # a later choice for this target was made meanwhile; it alone is queued
	var history := _hist()
	if who.account == "" or history == null:
		return {"error": who.error if who.account == "" else NO_HISTORY, "pending": false}
	if _blocked(who.account):
		return {"error": ERASURE_PENDING, "pending": false}
	if queue.call(history, who.account) != OK:
		return {"error": NO_HISTORY, "pending": false}
	var seen := {"mine": false, "other": false, "error": ""}
	var listener := func(account: String, other_kind: String, other_level: String, other_sha: String, other_value: Variant, error: String) -> void:
		if account != who.account:
			return
		if other_level == level and other_kind == kind and other_sha == sha256 and typeof(other_value) == typeof(value) and other_value == value:
			seen.mine = true
			seen.error = error
		else:
			seen.other = true  # another stage's, kind's or value's attempt: its failure stopped the flush, it is not this choice's
	vote_result.connect(listener)
	var result := await _sync()
	vote_result.disconnect(listener)
	if seen.mine:
		result["error"] = seen.error  # this choice's own attempt, not another queued choice's refusal
	elif seen.other:
		result["error"] = ""  # the sentence in the batch answer belongs to a choice that is not this one
	return result


func _meta_path(sha256: String) -> String:
	return dir + sha256 + ".meta.json"


func _meta_valid(level_id: Variant, version: Variant) -> bool:
	return level_id is String and _level_id.search(level_id) != null and (version is int or version is float) and version >= 1 and int(version) == version


## Saves the row's stable level id and version beside its cached file, unless the saved ones are already right (a missing or damaged one is replaced).
func _save_meta(row: Dictionary) -> void:
	if not _is_sha(row.sha256) or not _meta_valid(row.get("level_id"), row.get("latest")):
		return
	var meta := {"level_id": row.level_id, "version": int(row.latest)}
	if level_info(row.sha256) != meta:
		_store(_meta_path(row.sha256), JSON.stringify(meta).to_utf8_buffer())


func _owner_tag(account: String) -> String:
	return CommunityWire.sha256_hex(account.to_utf8_buffer()).substr(0, 16)


## The private feedback of one account on one version; its `you` block is this player's alone, so the file name carries the account.
func _feedback_path(account: String, sha256: String) -> String:
	return "%sfeedback_%s_%s.json" % [dir, _owner_tag(account), sha256]


func _feedback_valid(data: Variant, level: String, sha256: String) -> bool:
	return data is Dictionary and data.get("level_id") == level and data.get("sha256") == sha256 and data.get("stats") is Dictionary and data.get("community_difficulty") is Dictionary and data.get("you") is Dictionary


func _cached_feedback(account: String, level: String, sha256: String) -> Dictionary:
	var path := _feedback_path(account, sha256)
	if account == "" or _blocked(account) or not FileAccess.file_exists(path):
		return {}
	var data: Variant = _parse(FileAccess.get_file_as_bytes(path))
	return data if _feedback_valid(data, level, sha256) else {}


## The account whose local erasure is owed: recorded in the session file (and checked) before a deletion goes to the server, cleared only once its history, queued votes and private feedback are durably gone. "" when none.
func _erasure_owner() -> String:
	var who: Variant = _session().get_value("erasure", "owner", "")
	return who if who is String else ""


## Whether `account` is owed an erasure: nothing of it may be recorded, shown, cached or sent until that is done.
func _blocked(account: String) -> bool:
	return account != "" and _erasure_owner() == account


## The stored player id, or "" when that account is owed an erasure.
func _account() -> String:
	var account := player_id()
	return "" if _blocked(account) else account


## Saves the session file through a temporary file and a checked rename, so a failed save leaves the current one whole.
func _save_session(file: ConfigFile) -> Error:
	var temp := session_path + ".tmp"
	var err := file.save(temp)
	if err == OK:
		err = DirAccess.rename_absolute(temp, session_path)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err


func _mark_erasure(account: String) -> Error:
	var file := _session()
	file.set_value("erasure", "owner", account)
	return _save_session(file)


## Takes the mark back after the server refused the deletion.
func _unmark_erasure() -> Error:
	var file := _session()
	if not file.has_section("erasure"):
		return OK
	file.erase_section("erasure")
	return _save_session(file)


## Forgets everything private about `account`: its history, queued votes and cached feedback (downloaded public levels stay). True only when every part is durably gone: a cache folder that is there but cannot be opened or listed is a failure, not an empty folder, and only a folder that does not exist has nothing to erase.
func _complete_erasure(account: String) -> bool:
	for key: String in _settlements.keys():
		if key.begins_with(account + "|"):
			_settlements.erase(key)
	var history := _hist()
	var done := history != null and history.erase_owner(account) == OK
	var names: Variant = _private_names(account)
	if names == null:
		return false
	for file: String in names:
		if DirAccess.remove_absolute(dir + file) != OK:
			done = false
	return done


## Tells open sheets that the persisted player is not `before` any more.
func _announce_identity(before: String) -> void:
	var now := player_id()
	if now != before:
		identity_changed.emit(now)


## The file names of `account`'s private feedback in the downloads folder: empty when the folder does not exist, null when it exists but cannot be opened or listed (nothing is known then).
func _private_names(account: String) -> Variant:
	var names := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return names
	var folder := DirAccess.open(dir)
	if folder == null or folder.list_dir_begin() != OK:
		return null
	var prefix := "feedback_%s_" % _owner_tag(account)
	var file := folder.get_next()
	while file != "":
		if not folder.current_is_dir() and file.begins_with(prefix):
			names.append(file)
		file = folder.get_next()
	folder.list_dir_end()
	return names


## Pays an owed erasure (an explicit community action calls it): true when none is owed any more. Never while the deletion that owes it is still with the server.
func _finish_erasure() -> bool:
	var account := _erasure_owner()
	if account == "":
		return true
	if _deleting or not _complete_erasure(account):
		return false
	var file := _session()
	file.erase_section("erasure")
	return _save_session(file) == OK
