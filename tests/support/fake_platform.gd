class_name FakePlatform
extends CommunityPlatform
## A device with Play Games and Play Integrity that answers like the server's test verifier: auth code `test:<account>:<name>`, token `ok:<nonce>`.

var is_available := true
## The Play Games account that signs in; the server's test verifier turns it into the player.
var account := "p1"
## A sentence here makes the matching call fail with it.
var sign_in_error := ""
var integrity_error := ""
## Every nonce `integrity` was asked to sign.
var nonces: Array[String] = []
## How many times `sign_in` was called.
var sign_ins := 0
## While true, `sign_in` counts the call and then waits for `release_sign_in()`.
var sign_in_held := false

signal sign_in_released


func release_sign_in() -> void:
	sign_in_held = false
	sign_in_released.emit()


func available() -> bool:
	return is_available


func sign_in() -> Dictionary:
	sign_ins += 1
	if sign_in_held:
		await sign_in_released
	return {"error": sign_in_error} if sign_in_error != "" else {"auth_code": "test:%s:Pilot" % account}


func integrity(nonce: String) -> Dictionary:
	nonces.append(nonce)
	return {"error": integrity_error} if integrity_error != "" else {"token": "ok:" + nonce}
