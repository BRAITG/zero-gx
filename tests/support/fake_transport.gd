class_name FakeTransport
extends CommunityTransport
## Answers community requests from a queue instead of the network, and records every request.

## One request held by `hold`: it waits at `opened` once it has arrived.
class Gate extends RefCounted:
	var method := ""
	var prefix := ""
	var arrived := false

	signal opened

## Each entry answers one request: {method, path_prefix, status, body}.
var queue: Array[Dictionary] = []
## Answer every request that nothing in `queue` took: {method, path_prefix, handler}. `handler` gets the recorded request and returns {status, body} (body as for `answer`).
var responders: Array[Dictionary] = []
## Every request made, in order: {method, url, headers, body}.
var requests: Array[Dictionary] = []
## While true, `send` records a request and then waits for `release()` before it answers.
var held := false

var _gates: Array[Gate] = []

signal released


func release() -> void:
	held = false
	released.emit()


## The next `method` request whose path begins with `path_prefix` is recorded and then waits for `release_hold`; others go through.
func hold(method: String, path_prefix: String) -> void:
	var gate := Gate.new()
	gate.method = method
	gate.prefix = path_prefix
	_gates.append(gate)


## Lets the held request (or, when it has not arrived yet, cancels the pending hold) go on to be answered.
func release_hold(method: String, path_prefix: String) -> void:
	for gate in _gates:
		if gate.method == method and gate.prefix == path_prefix and gate.arrived:
			_gates.erase(gate)
			gate.opened.emit()
			return
	for gate in _gates:
		if gate.method == method and gate.prefix == path_prefix:
			_gates.erase(gate)
			return


## Queues the answer to the next `method` request whose path begins with `path_prefix`. `body` is bytes, text or JSON data.
func answer(method: String, path_prefix: String, status: int, body: Variant = "") -> void:
	queue.append({"method": method, "path_prefix": path_prefix, "status": status, "body": _bytes(body)})


## Answers every later `method` request under `path_prefix` that the queue does not, by calling `handler(request) -> {status, body}`.
func respond(method: String, path_prefix: String, handler: Callable) -> void:
	responders.append({"method": method, "path_prefix": path_prefix, "handler": handler})


func count(method: String, path_prefix: String) -> int:
	return requests.filter(func(r: Dictionary) -> bool: return r.method == method and _path(r.url).begins_with(path_prefix)).size()


func send(method: String, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var request := {"method": method, "url": url, "headers": headers, "body": body}
	requests.append(request)
	if held:
		await released
	var path := _path(url)
	for gate in _gates:
		if not gate.arrived and gate.method == method and path.begins_with(gate.prefix):
			gate.arrived = true
			await gate.opened
			break
	for i in queue.size():
		if queue[i].method == method and path.begins_with(queue[i].path_prefix):
			var found: Dictionary = queue.pop_at(i)
			return {"status": found.status, "body": found.body}
	for responder in responders:
		if responder.method == method and path.begins_with(responder.path_prefix):
			var made: Dictionary = responder.handler.call(request)
			return {"status": made.status, "body": _bytes(made.get("body", ""))}
	# Loud on purpose: a missing answer must fail the test, not look like an outage.
	return {"status": 599, "body": JSON.stringify({"error": "FakeTransport: nothing queued for %s %s" % [method, path]}).to_utf8_buffer()}


func _bytes(body: Variant) -> PackedByteArray:
	return body if body is PackedByteArray else (body if body is String else JSON.stringify(body)).to_utf8_buffer()


func _path(url: String) -> String:
	return "/" + url.split("/", true, 3)[3]
