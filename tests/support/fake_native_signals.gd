class_name FakeNativeSignals
extends RefCounted
## The two native Android plugins community uses, as GDScript sees them. Each holds its answers until the test releases them, unless the test asks for an answer during the call.


## The `ZeroGxIntegrity` singleton: records each request, and answers it only when the test says so.
class Integrity extends Object:
	signal integrity_result(request_id: int, token: String, error: String)
	## Every request so far, in order: {nonce, cloud_project_number, request_id}.
	var requests: Array[Dictionary] = []
	## Not empty: each request is answered during the request call, with `{token}` or `{error}`.
	var instant := {}


	func request(nonce: String, cloud_project_number: int, request_id: int) -> void:
		requests.append({"nonce": nonce, "cloud_project_number": cloud_project_number, "request_id": request_id})
		if not instant.is_empty():
			integrity_result.emit(request_id, instant.get("token", ""), instant.get("error", ""))


	## The `index`-th request (0 is the first), or `{}` when there is none.
	func request_at(index: int) -> Dictionary:
		return requests[index] if index < requests.size() else {}


	## Answers the `index`-th request under the id that request carried. An index with no request answers under id -1, which no request carries, so the test fails on its own expectation.
	func answer(index: int, token := "", error := "") -> void:
		reply(request_at(index).get("request_id", -1), token, error)


	## Emits a result under any id: how a test sends an answer that belongs to another request.
	func reply(request_id: int, token := "", error := "") -> void:
		integrity_result.emit(request_id, token, error)


## The `GodotPlayGameServices` singleton's sign-in surface: the autoload calls `initialize`, the sign-in client calls `signIn` and `requestServerSideAccess` and listens to the signals.
class PlayGames extends Object:
	signal imageStored(file_path: String)
	signal userAuthenticated(is_authenticated: bool)
	signal serverSideAccessRequested(token: String)
	## True: `signIn` answers during the call, as a signed-in player.
	var authenticates_at_once := false
	## Not empty: `requestServerSideAccess` answers during the call with this code.
	var code_at_once := ""


	func initialize() -> void:
		pass


	func signIn() -> void:
		if authenticates_at_once:
			authenticate(true)


	func requestServerSideAccess(_server_client_id: String, _force_refresh_token: bool) -> void:
		if code_at_once != "":
			grant_code(code_at_once)


	## Answers a sign-in that is under way.
	func authenticate(is_authenticated: bool) -> void:
		userAuthenticated.emit(is_authenticated)


	## Answers a code request that is under way.
	func grant_code(token: String) -> void:
		serverSideAccessRequested.emit(token)
