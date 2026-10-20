class_name CommunityPlatform
extends RefCounted
## What community needs from the device: a Play Games sign-in and a Play Integrity token. This base class is a device without them (every desktop build): community is unavailable and every call fails with a sentence. Overrides may be coroutines.

const UNAVAILABLE := "Community needs Play Games on Android."


func available() -> bool:
	return false


## `{"auth_code": String}`, the server auth code of the player's Play Games account, or `{"error": String}`.
func sign_in() -> Dictionary:
	return {"error": UNAVAILABLE}


## `{"token": String}`, a Play Integrity token whose nonce is `nonce`, or `{"error": String}`.
func integrity(_nonce: String) -> Dictionary:
	return {"error": UNAVAILABLE}
