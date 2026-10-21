class_name FakeTransport
extends CommunityTransport
## Answers community requests from a queue instead of the network, and records every request.

## Each entry answers one request: {method, path_prefix, status, body}.
var queue: Array[Dictionary] = []
## Every request made, in order: {method, url, headers, body, timeout}.
var requests: Array[Dictionary] = []
## While true, `send` records a request and then waits for `release()` before it answers.
var held := false

signal released


func release() -> void:
	held = false
	released.emit()


## Queues the answer to the next `method` request whose path begins with `path_prefix`. `body` is bytes, text or JSON data.
func answer(method: String, path_prefix: String, status: int, body: Variant = "") -> void:
	var bytes: PackedByteArray = body if body is PackedByteArray else (body if body is String else JSON.stringify(body)).to_utf8_buffer()
	queue.append({"method": method, "path_prefix": path_prefix, "status": status, "body": bytes})


func count(method: String, path_prefix: String) -> int:
	return requests.filter(func(r: Dictionary) -> bool: return r.method == method and _path(r.url).begins_with(path_prefix)).size()


func send(method: String, url: String, headers: PackedStringArray, body: PackedByteArray, timeout := CommunityTransport.TIMEOUT_SECONDS) -> Dictionary:
	requests.append({"method": method, "url": url, "headers": headers, "body": body, "timeout": timeout})
	if held:
		await released
	var path := _path(url)
	for i in queue.size():
		if queue[i].method == method and path.begins_with(queue[i].path_prefix):
			var found: Dictionary = queue.pop_at(i)
			return {"status": found.status, "body": found.body}
	# Loud on purpose: a missing answer must fail the test, not look like an outage.
	return {"status": 599, "body": JSON.stringify({"error": "FakeTransport: nothing queued for %s %s" % [method, path]}).to_utf8_buffer()}


func _path(url: String) -> String:
	return "/" + url.split("/", true, 3)[3]
