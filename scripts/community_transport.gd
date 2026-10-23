class_name CommunityTransport
extends Node
## The real HTTP layer of `Community`: one HTTPRequest child per call. Tests replace it with tests/support/fake_transport.gd.

const METHODS := {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT, "DELETE": HTTPClient.METHOD_DELETE}
const TIMEOUT_SECONDS := 30.0  # a request that never answers must end as "no connection"
# shortcut: answers are read into memory whole, uncapped; the server and the levels CDN are ours and the server limits levels to 64 KB, so cap `body_size_limit` if another host is ever called


## Coroutine: `{"status": int, "body": PackedByteArray}`; status 0 means the request never got an answer within `TIMEOUT_SECONDS`.
func send(method: String, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var started := http.request_raw(url, headers, METHODS[method], body)
	var answer := [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if started == OK:
		answer = await http.request_completed  # [result, status, headers, body]
	http.queue_free()
	return {"status": answer[1], "body": answer[3]} if answer[0] == HTTPRequest.RESULT_SUCCESS else {"status": 0, "body": PackedByteArray()}
