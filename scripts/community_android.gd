class_name CommunityAndroid
extends CommunityPlatform
## This device's Play Games sign-in (the `godot-play-game-services` plugin) and Play Integrity (our plugin, `android/plugins/integrity/`). Available only in the Play build with both plugins and the setup values.
## The Play Games SDK itself starts at every launch (its init provider cannot be removed) and may then sign the player in to Play Games, under Google's privacy policy. Only the sign-in to our server below waits for the player to open Community.

const PLAY_GAMES := "GodotPlayGameServices"
const INTEGRITY := "ZeroGxIntegrity"
## The custom export feature only the "Android Play" preset sets. A sideloaded APK is not `PLAY_RECOGNIZED` by Play Integrity, so the server refuses its sign-in.
const FEATURE := "community"
const SIGN_IN_CANCELLED := "Play Games sign-in was cancelled"
const SIGN_IN_SILENT := "Play Games did not answer."
const NO_CODE := "Play Games gave no sign-in code."
const INTEGRITY_FAILED := "Play Integrity could not check this device."
const INTEGRITY_SILENT := "Play Integrity did not answer."
## The Play Games plugin answers a failed `request_server_side_access` with nothing, so the race needs its own timer.
const WAIT_SECONDS := 30.0  # we never wait longer than a request's own timeout

var _host: Node
var _client: PlayGamesSignInClient
var _integrity_turn: Race  # the newest Integrity caller's turn: each caller waits for the one before it
var _integrity_requests := 0  # the id of the last native Integrity request


## `host` is a node in the tree: it carries the sign-in client and runs the timeouts.
func _init(host: Node) -> void:
	_host = host


func available() -> bool:
	return OS.has_feature(FEATURE) and Engine.has_singleton(PLAY_GAMES) and Engine.has_singleton(INTEGRITY) and configured()


## Whether the project carries the setup values: the Play Games web client id and the Cloud project number.
static func configured() -> bool:
	return ProjectSettings.get_setting("community/google_web_client_id", "") != "" and int(ProjectSettings.get_setting("community/cloud_project_number", 0)) != 0


func sign_in() -> Dictionary:
	if not available():
		return {"error": UNAVAILABLE}
	var web_client: String = ProjectSettings.get_setting("community/google_web_client_id", "")
	if _client == null:
		if GodotPlayGameServices.initialize() != GodotPlayGameServices.PlayGamesPluginError.OK:
			return {"error": UNAVAILABLE}
		_client = PlayGamesSignInClient.new()  # after initialize: it connects to the plugin's signals when it enters the tree
		_host.add_child(_client)
	var signed_in := _race([_client.user_authenticated], WAIT_SECONDS)  # listening before the call: an answer given during it must not be lost
	_client.sign_in()
	var auth: Array = await signed_in.result()
	if auth[0] == -1:
		return {"error": SIGN_IN_SILENT}
	if not auth[1]:
		return {"error": SIGN_IN_CANCELLED}
	var race := _race([_client.server_side_access_requested], WAIT_SECONDS)
	_client.request_server_side_access(web_client, false)
	var answer: Array = await race.result()
	return {"auth_code": answer[1]} if answer[0] == 0 and answer[1] != "" else {"error": NO_CODE}


func integrity(nonce: String) -> Dictionary:
	if not Engine.has_singleton(INTEGRITY):  # not `available()`: callers have checked it, and this call never touches Play Games
		return {"error": UNAVAILABLE}
	var deadline := _host.get_tree().create_timer(WAIT_SECONDS)  # one bound for the whole call, queueing included
	var ahead := _integrity_turn  # the caller before this one; its turn ends with its answer or its bound
	var turn := Race.new()
	_integrity_turn = turn
	var answer := {"error": INTEGRITY_SILENT}
	var gate := Race.new()
	if ahead != null and not ahead.is_done():
		ahead.finished.connect(gate.finish.bind(null, 0), CONNECT_ONE_SHOT)
		deadline.timeout.connect(gate.finish.bind(null, -1))
		if (await gate.result())[0] == 0:
			answer = await _integrity_request(nonce, deadline)
	else:
		answer = await _integrity_request(nonce, deadline)
	# A caller that timed out in the queue never started its request: it passes the turn on only once the one ahead has ended.
	# A Callable to a RefCounted holds no reference: the lambda captures `turn`, and its bound argument keeps `ahead` alive until it fires.
	var release := func(_ahead: Race) -> void: turn.finish(null, 0)
	if ahead != null and not ahead.is_done():
		ahead.finished.connect(release.bind(ahead), CONNECT_ONE_SHOT)
	else:
		release.bind(null).call_deferred()  # deferred: a caller whose bound ends in this same frame must time out, not start
	return answer


## One native request under a fresh id, ended by its answer or by `deadline`. Only the answer under that id settles it, and its listener is gone when this returns.
func _integrity_request(nonce: String, deadline: SceneTreeTimer) -> Dictionary:
	var plugin := Engine.get_singleton(INTEGRITY)
	var project: int = ProjectSettings.get_setting("community/cloud_project_number", 0)
	_integrity_requests += 1
	var request_id := _integrity_requests
	var race := Race.new()
	var listener := func(answer_id: int, token: String, error: String) -> void:
		if answer_id == request_id:
			race.finish(token, 0 if token != "" else 1)  # the native error text is never kept: it is the provider's, not ours
	var results := Signal(plugin, "integrity_result")
	results.connect(listener)  # before the call: an answer given during it must not be lost
	deadline.timeout.connect(race.finish.bind(null, -1))
	plugin.request(nonce, project, request_id)
	var answer: Array = await race.result()
	results.disconnect(listener)
	match answer[0]:
		0:
			return {"token": answer[1]}
		1:
			return {"error": INTEGRITY_FAILED}
	return {"error": INTEGRITY_SILENT}


## Listens to `signals` (each with one argument) from now on: the first to fire wins as `[its index, its argument]`; `seconds` of silence is `[-1, null]`.
func _race(signals: Array, seconds: float) -> Race:
	var race := Race.new()
	for i in signals.size():
		signals[i].connect(race.finish.bind(i), CONNECT_ONE_SHOT)
	_host.get_tree().create_timer(seconds).timeout.connect(race.finish.bind(null, -1))
	return race


class Race:
	signal finished
	var _answer := []

	func finish(value: Variant, index: int) -> void:
		if _answer.is_empty():
			_answer = [index, value]
			finished.emit()

	func is_done() -> bool:
		return not _answer.is_empty()

	## Coroutine.
	func result() -> Array:
		if _answer.is_empty():
			await finished
		return _answer
