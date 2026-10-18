extends "res://tests/test_case.gd"

const SHIP := {"position": Vector2.ZERO, "rotation": 0.0, "firing": false, "fuel": 1.0, "hull": 1.0}


func test_round_trip_keeps_every_object() -> void:
	var demo := Demo.new()
	demo.level_sha256 = "ab".repeat(32)
	for f in 90:
		var rocks := {0: Transform2D(f * 0.01, Vector2(100 + f, -50))}
		if f >= 30:
			rocks[7] = Transform2D(0.0, Vector2(400 - f * 2, 10))  # a shard from frame 30
		if f == 30: demo.add_event(Demo.Event.ASTEROID_SPAWNED, [7])
		demo.add_frame({"position": Vector2(f * 3.5, -f), "rotation": f * 0.05, "firing": f % 2 == 0, "fuel": 100 - f * 0.1, "hull": 100.0}, rocks)
	demo.add_event(Demo.Event.CLOCK_STARTED)
	demo.add_event(Demo.Event.GOAL_REACHED)
	var back := Demo.decode(demo.encode())
	check(Demo.peek_level_sha256(demo.encode()) == demo.level_sha256, "the header names the level")
	check(back.events().any(func(e: Array) -> bool: return e == [90, Demo.Event.CLOCK_STARTED, []]), "CLOCK_STARTED survives encoding: %s" % [back.events()])
	check(back != null and back.frame_count() == 90 and back.level_sha256 == demo.level_sha256, "header")
	check(back.ship_at(60).position.distance_to(Vector2(210, -60)) <= 1.0 / Demo.POSITION_SCALE, "ship at 60: %s" % back.ship_at(60))
	check(not back.asteroids_at(29).has(7) and back.asteroids_at(60)[7].origin.distance_to(Vector2(280, 10)) < 0.2, "shard appears at 30")
	check(back.events().back()[1] == Demo.Event.GOAL_REACHED, "events")


func test_decode_rejects_garbage() -> void:
	check(Demo.decode(PackedByteArray([1, 2, 3])) == null, "garbage must not decode")
	var good := Demo.new()
	good.add_frame(SHIP, {})
	var bytes := good.encode().decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	bytes.resize(bytes.size() - 3)
	check(Demo.decode(bytes.compress(FileAccess.COMPRESSION_GZIP)) == null, "a truncated body must not decode")
	bytes = good.encode().decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	bytes[0] = 0
	check(Demo.decode(bytes.compress(FileAccess.COMPRESSION_GZIP)) == null, "wrong magic")
	bytes = good.encode().decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	bytes[4] = Demo.FORMAT_VERSION + 1
	check(Demo.decode(bytes.compress(FileAccess.COMPRESSION_GZIP)) == null, "wrong version")
	var huge := PackedByteArray()
	huge.resize(Demo.MAX_BYTES + 1)
	check(Demo.decode(huge) == null, "oversized input")


func test_recording_stops_at_the_frame_limit() -> void:
	var demo := Demo.new()
	for f in Demo.MAX_FRAMES:
		demo.add_frame(SHIP, {})
	check(not demo.add_frame(SHIP, {}) and demo.truncated, "frame limit")


func test_far_and_jumping_asteroids_survive() -> void:
	var demo := Demo.new()
	var far := Vector2(50000, -50000)
	for f in 4:
		var rocks := {3: Transform2D(3.0, far + Vector2(f, 0))}
		if f == 2:
			rocks[3] = Transform2D(-3.1, far + Vector2(9000, 0))  # a jump too big for a delta, across the ±PI seam
		demo.add_frame(SHIP, rocks)
	var back := Demo.decode(demo.encode())
	check(back != null and back.asteroids_at(1)[3].origin.distance_to(far + Vector2(1, 0)) < 0.2, "far absolute")
	check(back.asteroids_at(2)[3].origin.distance_to(far + Vector2(9000, 0)) < 0.2, "jump")
	check(absf(angle_difference(back.asteroids_at(2)[3].get_rotation(), -3.1)) < 0.002, "rotation across the seam")


func test_an_asteroid_missing_from_a_frame_is_gone() -> void:
	var demo := Demo.new()
	demo.add_frame(SHIP, {1: Transform2D(0.0, Vector2(5, 5))})
	demo.add_frame(SHIP, {1: Transform2D(0.0, Vector2(5, 5))})  # unchanged: nothing to store
	demo.add_frame(SHIP, {})
	var back := Demo.decode(demo.encode())
	check(back.asteroids_at(1).has(1) and not back.asteroids_at(2).has(1), "removed at frame 2 without an event")


func test_malformed_hash_encodes_as_zeros() -> void:
	var demo := Demo.new()
	demo.level_sha256 = "not a hash"
	demo.add_frame(SHIP, {})
	check(Demo.decode(demo.encode()).level_sha256 == "0".repeat(64), "zero hash")



## A hostile body: `frame_rocks` asteroid ids added on frame 0, then empty frames up to `frames`.
func _hostile_body(frames: int, frame_rocks: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_data(Demo.MAGIC.to_ascii_buffer())
	buf.put_u8(Demo.FORMAT_VERSION)
	buf.put_data(Demo.new()._hash_bytes())
	buf.put_u32(frames)
	buf.put_u8(0)
	for f in frames:
		buf.put_32(0)
		buf.put_32(0)
		buf.put_16(0)
		buf.put_u8(0)
		buf.put_u16(0)
		buf.put_u16(0)
		var count := frame_rocks if f == 0 else 0
		buf.put_u16(count)
		for id in count:
			buf.put_u16(id)
			buf.put_u8(Demo.ABSOLUTE)
			buf.put_32(0)
			buf.put_32(0)
			buf.put_16(0)
	buf.put_u32(0)  # no events
	return buf.data_array.compress(FileAccess.COMPRESSION_GZIP)


func test_too_many_alive_asteroids_stop_recording_and_decoding() -> void:
	var rocks := {}
	for id in Demo.MAX_ALIVE + 1:
		rocks[id] = Transform2D.IDENTITY
	var demo := Demo.new()
	check(not demo.add_frame(SHIP, rocks) and demo.truncated and demo.frame_count() == 0, "add_frame refuses too many")
	# The same body with exactly MAX_ALIVE decodes, so only the alive cap can reject the larger one.
	check(Demo.decode(_hostile_body(1, Demo.MAX_ALIVE)) != null, "MAX_ALIVE asteroids decode")
	check(Demo.decode(_hostile_body(1, Demo.MAX_ALIVE + 1)) == null, "too many alive must not decode")


func test_decode_budget_caps_total_asteroid_frames() -> void:
	# MAX_ALIVE asteroids alive on every one of MAX_FRAMES frames: within MAX_ALIVE, over the budget.
	check(Demo.decode(_hostile_body(Demo.MAX_FRAMES, Demo.MAX_ALIVE)) == null, "budget exceeded must not decode")
	# The same shape over fewer frames decodes, so the budget is what rejected it.
	check(Demo.decode(_hostile_body(10, Demo.MAX_ALIVE)) != null, "a demo inside the budget decodes")
