class_name CommunityWire
extends RefCounted
## Bytes the game and the community server must agree on: the Play Integrity nonce binding and the multipart body of a submission. The server twin is server/src/session.ts (boundNonce).


## base64url (RFC 4648 §5) without padding.
static func base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


## base64url of SHA-256(nonce as UTF-8 ‖ SHA-256(part 1) ‖ SHA-256(part 2) ‖ …): the nonce Play Integrity signs for a request carrying `parts`.
static func bound_nonce(nonce: String, parts: Array[PackedByteArray]) -> String:
	var joined := nonce.to_utf8_buffer()
	for part in parts:
		joined.append_array(_sha256(part))
	return base64url(_sha256(joined))


## `fields` (name → String) then `files` (name → [filename, bytes]), each part framed by CRLF.
static func multipart(fields: Dictionary, files: Dictionary, boundary: String) -> PackedByteArray:
	var body := PackedByteArray()
	for name in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, name, fields[name]]).to_utf8_buffer())
	for name in files:
		var file: Array = files[name]
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [boundary, name, file[0]]).to_utf8_buffer())
		body.append_array(file[1])
		body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body


## The lowercase hex SHA-256 of `bytes`: the hash that identifies a level file.
static func sha256_hex(bytes: PackedByteArray) -> String:
	return _sha256(bytes).hex_encode()


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		hash.update(bytes)
	return hash.finish()
