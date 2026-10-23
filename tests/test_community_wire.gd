extends "res://tests/test_case.gd"
## The community server checks the same fixture (fixtures/bound_nonce.json) in server/test/bound_nonce.test.ts.

const FIXTURE := "res://fixtures/bound_nonce.json"

var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func test_bound_nonce_matches_the_server() -> void:
	var parts: Array[PackedByteArray] = [Marshalls.base64_to_raw(fixture.level_base64), Marshalls.base64_to_raw(fixture.demo_base64)]
	check(CommunityWire.bound_nonce(fixture.nonce, parts) == fixture.bound, "bound nonce differs from the server's")


func test_base64url_is_url_safe_without_padding() -> void:
	check(CommunityWire.base64url(PackedByteArray([0xfb, 0xff])) == "-_8", "base64url of fb ff is not -_8")


func test_multipart_frames_fields_then_files_with_crlf() -> void:
	var demo := Marshalls.base64_to_raw(fixture.demo_base64)
	var body := CommunityWire.multipart({"title": "Hi"}, {"demo": ["level_01.demo.gz", demo]}, "XB")
	var expected := "--XB\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nHi\r\n--XB\r\nContent-Disposition: form-data; name=\"demo\"; filename=\"level_01.demo.gz\"\r\nContent-Type: application/octet-stream\r\n\r\n".to_utf8_buffer()
	expected.append_array(demo)
	expected.append_array("\r\n--XB--\r\n".to_utf8_buffer())
	check(body == expected, "multipart body differs from the expected framing")


## The optional third part: server/test/suggested_difficulty_nonce.test.ts checks the same fixture.
func test_three_part_bound_nonce_with_a_suggestion_matches_the_server() -> void:
	var suggested := _suggested()
	var level := Marshalls.base64_to_raw(suggested.level_base64)
	var demo := Marshalls.base64_to_raw(suggested.demo_base64)
	var label: PackedByteArray = suggested.suggested_difficulty.to_utf8_buffer()
	check(CommunityWire.sha256_hex(level) == suggested.level_sha256 and CommunityWire.sha256_hex(demo) == suggested.demo_sha256 and CommunityWire.sha256_hex(label) == suggested.suggested_difficulty_sha256, "the fixture parts must decode to the pinned hashes")
	var parts: Array[PackedByteArray] = [level, demo, label]
	check(CommunityWire.bound_nonce(suggested.nonce, parts) == suggested.bound, "three-part bound nonce differs from the server's")


func test_a_changed_or_dropped_suggestion_cannot_reuse_the_three_part_binding() -> void:
	var suggested := _suggested()
	var level := Marshalls.base64_to_raw(suggested.level_base64)
	var demo := Marshalls.base64_to_raw(suggested.demo_base64)
	for other: String in ["normal", "easy", "expert", "Hard", "hard ", ""]:
		var parts: Array[PackedByteArray] = [level, demo, other.to_utf8_buffer()]
		check(CommunityWire.bound_nonce(suggested.nonce, parts) != suggested.bound, "suggestion '%s' must not bind like 'hard'" % other)
	var two: Array[PackedByteArray] = [level, demo]
	check(CommunityWire.bound_nonce(suggested.nonce, two) != suggested.bound, "dropping the suggestion must change the binding")


func _suggested() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/suggested_difficulty_nonce.json"))
