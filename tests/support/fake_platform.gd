class_name FakePlatform
extends CommunityPlatform
## A device with Play Games and Play Integrity that answers like the server's test verifier: auth code `test:<id>:<name>`, token `ok:<nonce>`.

var is_available := true
## A sentence here makes the matching call fail with it.
var sign_in_error := ""
var integrity_error := ""
## Every nonce `integrity` was asked to sign.
var nonces: Array[String] = []


func available() -> bool:
	return is_available


func sign_in() -> Dictionary:
	return {"error": sign_in_error} if sign_in_error != "" else {"auth_code": "test:p1:Pilot"}


func integrity(nonce: String) -> Dictionary:
	nonces.append(nonce)
	return {"error": integrity_error} if integrity_error != "" else {"token": "ok:" + nonce}
