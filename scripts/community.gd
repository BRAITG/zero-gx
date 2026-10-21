extends Node
## The community client: every call to the community server, the session token and the download cache. Autoloaded as `Community`. Screens call it and show what it returns; it never touches UI. Failures come back as one sentence.

const NO_CONNECTION := "No connection"
const BAD_ANSWER := "The server's answer could not be read."
const NOT_SUBMITTABLE := "This level cannot be submitted."
const SESSION_SECONDS := 6 * 24 * 60 * 60  # the server's sessions last 7 days; sign in again a day early
const LEVEL_URL := "https://cdn.jsdelivr.net/gh/BRAITG/zero-gx-levels@%s/levels/%s/v%d.json"
## A downloaded level is played as stage `community_<sha256>`, built from its cached file.
const STAGE_PREFIX := "community_"
## A submission makes the server do about nine GitHub calls, so it gets longer than the usual 30 s.
const SUBMISSION_SECONDS := 120.0

var transport: CommunityTransport
var platform: CommunityPlatform
## Downloaded levels (`<sha256>.json`) and the last fetched list pages.
var dir := "user://community/"
## The session token with its expiry, and the last known submission statuses.
var session_path := "user://community.cfg"
var api_url: String = ProjectSettings.get_setting("community/api_url", "https://zerogx.braitg.dev")

var _http: CommunityTransport
var _signing_in := false  # one sign-in at a time; `_sign_in_done` hands its result to the callers that came meanwhile

signal _sign_in_done(error: String)


func _ready() -> void:
	_http = CommunityTransport.new()
	add_child(_http)
	use_defaults()


## The real transport and this device's platform; what tests restore after swapping in fakes.
func use_defaults() -> void:
	transport = _http
	platform = CommunityAndroid.new(self) if OS.has_feature("android") else CommunityPlatform.new()


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
	var nonce := await _nonce()  # before Play Games: offline must fail at once, not after a prompt
	if nonce.has("error"):
		return nonce.error
	var auth: Dictionary = await platform.sign_in()
	if auth.has("error"):
		return auth.error
	var proof: Dictionary = await platform.integrity(nonce.nonce)
	if proof.has("error"):
		return proof.error
	var body := JSON.stringify({"authCode": auth.auth_code, "integrityToken": proof.token, "nonce": nonce.nonce}).to_utf8_buffer()
	var reply := await _call("POST", api_url + "/session", PackedStringArray(["Content-Type: application/json"]), body)
	if reply.has("error"):
		return reply.error
	if not reply.data.get("token") is String:
		return BAD_ANSWER
	var file := _session()  # keeps the last known statuses
	file.set_value("session", "token", reply.data.token)
	file.set_value("session", "expires", int(Time.get_unix_time_from_system()) + SESSION_SECONDS)
	file.save(session_path)
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


## Coroutine: makes sure the level of a `list` row is cached; `""` when it is there and verified, else why not. A file whose hash differs from the row's is rejected and kept nowhere.
func download(row: Dictionary) -> String:
	var path := level_path(row.sha256)
	if FileAccess.file_exists(path) and CommunityWire.sha256_hex(FileAccess.get_file_as_bytes(path)) == row.sha256:
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
	return "" if _store(path, file.data) else "The level could not be saved."


## Whether the draft `id` can go to the server: a platform with Play Games, and a finishing demo that still matches the draft.
func can_submit(id: String) -> bool:
	return available() and MyLevels.demo(id) != null


## Coroutine: sends draft `id` with its demo; `""` once the server took it, else its sentence. The returned level id is kept for the draft, so a later submission becomes the next version of the same level; the sent content's hash too, which marks the draft as submitted until it changes.
func submit(id: String) -> String:
	if not can_submit(id):
		return NOT_SUBMITTABLE
	var level := LevelFormat.to_json(MyLevels.load_level(id)).to_utf8_buffer()
	var demo := FileAccess.get_file_as_bytes(MyLevels.demo_path(id))
	var reply := await _authed("POST", "/submissions", TYPE_DICTIONARY, _submission.bind(level, demo, level_id_of(id)))
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
	file.save(session_path)
	return fresh


## Coroutine: deletes the player's community account on the server; `""` once it is gone and the session, statuses, draft level ids and submitted marks are cleared here too, else the sentence.
func delete_account() -> String:
	var reply := await _authed("DELETE", "/me", TYPE_NIL)
	if reply.has("error"):
		return reply.error
	DirAccess.remove_absolute(session_path)  # holds the session and the statuses
	for id in MyLevels.ids():
		MyLevels.set_level_id(id, "")
		MyLevels.set_submitted(id, "")
	return ""


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
func _call(method: String, url: String, headers := PackedStringArray(), body := PackedByteArray(), expect := TYPE_DICTIONARY, timeout := CommunityTransport.TIMEOUT_SECONDS) -> Dictionary:
	var reply: Dictionary = await transport.send(method, url, headers, body, timeout)
	var status: int = reply.status
	if status == 0:
		return {"status": 0, "error": NO_CONNECTION}
	if status < 200 or status > 299:
		var failure: Variant = _parse(reply.body)
		var sentence: Variant = failure.get("error") if failure is Dictionary else null
		return {"status": status, "error": sentence if sentence is String and sentence != "" else "The server answered %d." % status}
	var data: Variant = reply.body if expect == TYPE_PACKED_BYTE_ARRAY else _parse(reply.body)
	return {"status": status, "data": data} if typeof(data) == expect else {"status": status, "error": BAD_ANSWER}


## `_call` to the community server with the session. A 401 clears the token that was sent; with `resign` it then signs in again once and retries once. `build` is an optional coroutine that makes `{"headers", "body"}` and optionally `"timeout"` (or `{"error"}`) afresh for each attempt.
func _authed(method: String, path: String, expect := TYPE_DICTIONARY, build := Callable(), resign := true) -> Dictionary:
	var reply := await _send(method, path, expect, build)
	if reply.status == 401:
		_forget(reply.token)
		if resign:
			reply = await _send(method, path, expect, build)
	return reply


## Drops the stored session when it still holds `token`, which the server no longer accepts. A token that a sign-in saved meanwhile stays.
func _forget(token: String) -> void:
	var file := _session()
	if file.get_value("session", "token", "") == token:
		file.erase_section("session")
		file.save(session_path)


## One authorized request; the answer carries the `token` it was sent with.
func _send(method: String, path: String, expect: int, build: Callable) -> Dictionary:
	if _token() == "":
		var error := await sign_in()
		if error != "":
			return {"status": 0, "error": error}
	var headers := PackedStringArray()
	var body := PackedByteArray()
	var timeout := CommunityTransport.TIMEOUT_SECONDS
	if build.is_valid():
		var made: Dictionary = await build.call()
		if made.has("error"):
			return {"status": 0, "error": made.error}
		headers = made.headers
		body = made.body
		timeout = made.get("timeout", timeout)
	var token := _token()
	headers.append("Authorization: Bearer " + token)
	var reply := await _call(method, api_url + path, headers, body, expect, timeout)
	reply["token"] = token
	return reply


## The headers and multipart body of one submission attempt: a fresh nonce, and an integrity token bound to this nonce and these exact bytes.
func _submission(level: PackedByteArray, demo: PackedByteArray, level_id: String) -> Dictionary:
	var nonce := await _nonce()
	if nonce.has("error"):
		return nonce
	var parts: Array[PackedByteArray] = [level, demo]
	var proof: Dictionary = await platform.integrity(CommunityWire.bound_nonce(nonce.nonce, parts))
	if proof.has("error"):
		return proof
	var boundary := Crypto.new().generate_random_bytes(16).hex_encode()  # random, so it cannot occur in the payload
	return {
		"headers": PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary, "X-Nonce: " + nonce.nonce, "X-Integrity: " + proof.token]),
		"body": CommunityWire.multipart({"level_id": level_id} if level_id != "" else {}, {"level": ["level.json", level], "demo": ["demo.gz", demo]}, boundary),
		"timeout": SUBMISSION_SECONDS,
	}
