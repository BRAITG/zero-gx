class_name CommunityAndroid
extends CommunityPlatform
## This device's Play Games sign-in (the `godot-play-game-services` plugin) and Play Integrity (our plugin, `android/plugins/integrity/`). Available only in the Play build with both plugins and the setup values.
## The Play Games SDK itself starts at every launch (its init provider cannot be removed) and may then sign the player in to Play Games, under Google's privacy policy. Only the sign-in to our server below waits for the player to open Community.

const PLAY_GAMES := "GodotPlayGameServices"
const INTEGRITY := "ZeroGxIntegrity"
## The custom export feature only the "Android Play" preset sets. A sideloaded APK is not `PLAY_RECOGNIZED` by Play Integrity, so the server refuses its sign-in.
const FEATURE := "community"
const SIGN_IN_CANCELLED := "Play Games sign-in was cancelled"
const NO_CODE := "Play Games gave no sign-in code."
const INTEGRITY_FAILED := "Play Integrity could not check this device."
const INTEGRITY_SILENT := "Play Integrity did not answer."
## The Play Games plugin answers a failed `request_server_side_access` with nothing, and the player may take a while over its prompt.
const CODE_SECONDS := 120.0
const INTEGRITY_SECONDS := 60.0

var _host: Node
var _client: PlayGamesSignInClient


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
	_client.sign_in()
	if not await _client.user_authenticated:
		return {"error": SIGN_IN_CANCELLED}
	var race := _race([_client.server_side_access_requested], CODE_SECONDS)
	_client.request_server_side_access(web_client, false)
	var answer: Array = await race.result()
	return {"auth_code": answer[1]} if answer[0] == 0 and answer[1] != "" else {"error": NO_CODE}


func integrity(nonce: String) -> Dictionary:
	if not Engine.has_singleton(INTEGRITY):  # not `available()`: callers have checked it, and this call never touches Play Games
		return {"error": UNAVAILABLE}
	var project: int = ProjectSettings.get_setting("community/cloud_project_number", 0)
	var plugin := Engine.get_singleton(INTEGRITY)
	var race := _race([Signal(plugin, "integrity_token"), Signal(plugin, "integrity_failed")], INTEGRITY_SECONDS)
	plugin.request(nonce, project)
	var answer: Array = await race.result()
	match answer[0]:
		0:
			return {"token": answer[1]}
		1:
			push_warning("Play Integrity failed: %s" % answer[1])  # the raw text is for the log, not for the player
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

	## Coroutine.
	func result() -> Array:
		if _answer.is_empty():
			await finished
		return _answer
