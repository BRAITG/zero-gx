class_name Demo
extends RefCounted
## A recorded run: one ship sample and the changed asteroids per physics frame, plus level events.
## Values are quantized on the way in, so a decoded demo returns exactly what was stored.

const FORMAT_VERSION := 1
const STEP := 1.0 / 30.0
const MAX_FRAMES := 18000
const MAX_BYTES := 524288
const POSITION_SCALE := 8  # stored units per px
const MAX_DECOMPRESSED := 8 * 1024 * 1024
const MAGIC := "ZGXD"
const ROTATION_SCALE := 1000.0  # stored milliradians per radian
const FUEL_SCALE := 10.0  # tenths

enum Event { PICKUP_TAKEN = 1, PLANET_SHATTERED = 2, SHIP_LOST = 3, GOAL_REACHED = 4, ASTEROID_SPAWNED = 5, ASTEROID_REMOVED = 6 }

# Asteroid log entry flags: how an entry's three values relate to the asteroid's previous ones.
const DELTA := 0
const ABSOLUTE := 1
const REMOVED := 2

# Bytes a frame needs at minimum: ship (4 + 4 + 2 + 1 + 2 + 2) and the changed-asteroid count (2).
const FRAME_MIN_BYTES := 17
const EVENT_BYTES := 7

var level_sha256 := "0".repeat(64)
var truncated := false

var _ship := PackedInt32Array()  # per frame: x, y, rotation, flags, fuel, hull
var _log: Array[PackedInt32Array] = []  # per frame, flat 5-int entries: id, flag, then three values
var _events: Array = []
var _alive := {}  # id -> Vector3i last stored (x, y, rotation)
var _tracks := {}  # id -> Array[_Span], oldest first; an id can come back after it was removed


class _Span:
	var start: int
	var data := PackedInt32Array()  # three ints per frame the asteroid was alive


## Append one frame. `asteroids` is every live asteroid (id < 65536); one missing from it is gone.
## Returns false, and marks the demo truncated, once the frame limit is reached.
func add_frame(ship: Dictionary, asteroids: Dictionary) -> bool:
	if frame_count() >= MAX_FRAMES:
		truncated = true
		return false
	var position: Vector2 = ship["position"]
	var rocks := {}
	for id in asteroids:
		var xform: Transform2D = asteroids[id]
		rocks[id] = Vector3i(_to_stored(xform.origin.x), _to_stored(xform.origin.y), _to_milliradians(xform.get_rotation()))
	_push(PackedInt32Array([
		_to_stored(position.x),
		_to_stored(position.y),
		_to_milliradians(ship["rotation"]),
		1 if ship["firing"] else 0,
		_to_tenths(ship["fuel"]),
		_to_tenths(ship["hull"]),
	]), rocks)
	return true


## Record an event at the frame being recorded (the next `add_frame` call).
func add_event(code: Event, args: Array = []) -> void:
	_events.append([frame_count(), code, args.duplicate()])


func frame_count() -> int:
	return _ship.size() / 6


func seconds() -> float:
	return frame_count() * STEP


func ship_at(frame: int) -> Dictionary:
	if frame < 0 or frame >= frame_count():
		return {}
	var i := frame * 6
	return {
		"position": Vector2(_ship[i], _ship[i + 1]) / POSITION_SCALE,
		"rotation": _ship[i + 2] / ROTATION_SCALE,
		"firing": _ship[i + 3] & 1 != 0,
		"fuel": _ship[i + 4] / FUEL_SCALE,
		"hull": _ship[i + 5] / FUEL_SCALE,
	}


## Asteroids alive at `frame`, id -> Transform2D.
func asteroids_at(frame: int) -> Dictionary:
	var out := {}
	for id in _tracks:
		for span: _Span in _tracks[id]:
			var i := (frame - span.start) * 3
			if i >= 0 and i < span.data.size():
				out[id] = Transform2D(span.data[i + 2] / ROTATION_SCALE, Vector2(span.data[i], span.data[i + 1]) / POSITION_SCALE)
				break
	return out


## Each event is [frame, code, args].
func events() -> Array:
	return _events


func encode() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_data(MAGIC.to_ascii_buffer())
	buf.put_u8(FORMAT_VERSION)
	buf.put_data(_hash_bytes())
	buf.put_u32(frame_count())
	buf.put_u8(1 if truncated else 0)
	for f in frame_count():
		var i := f * 6
		buf.put_32(_ship[i])
		buf.put_32(_ship[i + 1])
		buf.put_16(_ship[i + 2])
		buf.put_u8(_ship[i + 3])
		buf.put_u16(_ship[i + 4])
		buf.put_u16(_ship[i + 5])
		var entries := _log[f]
		buf.put_u16(entries.size() / 5)
		for e in range(0, entries.size(), 5):
			buf.put_u16(entries[e])
			buf.put_u8(entries[e + 1])
			match entries[e + 1]:
				ABSOLUTE:
					buf.put_32(entries[e + 2])
					buf.put_32(entries[e + 3])
					buf.put_16(entries[e + 4])
				DELTA:
					buf.put_16(entries[e + 2])
					buf.put_16(entries[e + 3])
					buf.put_16(entries[e + 4])
	buf.put_u32(_events.size())
	for event in _events:
		buf.put_u32(event[0])
		buf.put_u8(event[1])
		buf.put_u16(event[2][0] if not event[2].is_empty() else 0)
	return buf.data_array.compress(FileAccess.COMPRESSION_GZIP)


## Null for anything malformed, oversized, truncated, or of another format version.
static func decode(bytes: PackedByteArray) -> Demo:
	# Not gzip: decompress_dynamic would log an error on it.
	if bytes.size() > MAX_BYTES or bytes.size() < 2 or bytes[0] != 0x1f or bytes[1] != 0x8b:
		return null
	var raw := bytes.decompress_dynamic(MAX_DECOMPRESSED, FileAccess.COMPRESSION_GZIP)
	var buf := StreamPeerBuffer.new()
	buf.data_array = raw
	if raw.size() < 42 or buf.get_data(4)[1].get_string_from_ascii() != MAGIC or buf.get_u8() != FORMAT_VERSION:
		return null
	var demo := Demo.new()
	demo.level_sha256 = (buf.get_data(32)[1] as PackedByteArray).hex_encode()
	var frames := buf.get_u32()
	demo.truncated = buf.get_u8() != 0
	if frames > MAX_FRAMES:
		return null
	var rocks := {}
	for f in frames:
		if buf.get_available_bytes() < FRAME_MIN_BYTES:
			return null
		var ship := PackedInt32Array([buf.get_32(), buf.get_32(), buf.get_16(), buf.get_u8(), buf.get_u16(), buf.get_u16()])
		rocks = rocks.duplicate()
		for n in buf.get_u16():
			if buf.get_available_bytes() < 3:
				return null
			var id := buf.get_u16()
			var flag := buf.get_u8()
			if flag == REMOVED and rocks.erase(id):
				continue
			if flag == ABSOLUTE and buf.get_available_bytes() >= 10:
				rocks[id] = Vector3i(buf.get_32(), buf.get_32(), buf.get_16())
			elif flag == DELTA and rocks.has(id) and buf.get_available_bytes() >= 6:
				rocks[id] += Vector3i(buf.get_16(), buf.get_16(), buf.get_16())
			else:
				return null
		demo._push(ship, rocks)
	if buf.get_available_bytes() < 4:
		return null
	var event_count := buf.get_u32()
	if buf.get_available_bytes() != event_count * EVENT_BYTES:
		return null
	for n in event_count:
		var frame := buf.get_u32()
		var code := buf.get_u8()
		var arg := buf.get_u16()
		if frame > frames or code < Event.PICKUP_TAKEN or code > Event.ASTEROID_REMOVED:
			return null
		var takes_arg: bool = code != Event.SHIP_LOST and code != Event.GOAL_REACHED
		demo._events.append([frame, code, [arg] if takes_arg else []])
	return demo


## Store one frame of already quantized values, logging only what changed since the last one.
func _push(ship: PackedInt32Array, rocks: Dictionary) -> void:
	_ship.append_array(ship)
	var entries := PackedInt32Array()
	for id in rocks:
		var now: Vector3i = rocks[id]
		var span: _Span
		if _alive.has(id):
			span = _tracks[id].back()
			var step: Vector3i = now - _alive[id]
			if step == Vector3i.ZERO:
				pass
			elif absi(step.x) <= 32767 and absi(step.y) <= 32767:
				entries.append_array([id, DELTA, step.x, step.y, step.z])
			else:
				entries.append_array([id, ABSOLUTE, now.x, now.y, now.z])
		else:
			span = _Span.new()
			span.start = frame_count() - 1
			if not _tracks.has(id):
				_tracks[id] = []
			_tracks[id].append(span)
			entries.append_array([id, ABSOLUTE, now.x, now.y, now.z])
		span.data.append_array([now.x, now.y, now.z])
		_alive[id] = now
	for id in _alive.keys():
		if not rocks.has(id):
			entries.append_array([id, REMOVED, 0, 0, 0])
			_alive.erase(id)
	_log.append(entries)


func _hash_bytes() -> PackedByteArray:
	if level_sha256.length() == 64 and level_sha256.is_valid_hex_number(false):
		return level_sha256.hex_decode()
	var zeros := PackedByteArray()
	zeros.resize(32)
	return zeros


static func _to_stored(px: float) -> int:
	return clampi(roundi(px * POSITION_SCALE), -2147483648, 2147483647)


static func _to_milliradians(radians: float) -> int:
	return roundi(wrapf(radians, -PI, PI) * ROTATION_SCALE)


## Tenths in a u16; INF (an unlimited resource) is stored as 0.
static func _to_tenths(value: float) -> int:
	return clampi(roundi(value * FUEL_SCALE), 0, 65535) if is_finite(value) else 0
