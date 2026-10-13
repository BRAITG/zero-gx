extends Node
## Procedural sound effects, rendered to PCM once at startup: the prototype ships no audio files.
## Autoloaded as `Sfx` so a sound started just before a scene change keeps playing.

const RATE := 22050
const VOICES := 8
const PEAK := 0.8

## Looping engine rumble for the ship's own player.
var thrust: AudioStreamWAV
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # taps on the tuning panel play while the game is paused
	_rng.seed = 1
	_streams.impact = _wav(_render(0.25, 2000.0, func(t: float, n: float) -> float:
		return n * exp(-t * 25.0) + 0.6 * sin(TAU * 80.0 * t) * exp(-t * 12.0)))
	_streams.explosion = _wav(_render(1.2, 600.0, func(t: float, n: float) -> float:
		return n * exp(-t * 3.5) + 0.5 * sin(TAU * 45.0 * t) * exp(-t * 5.0)))
	_streams.goal = _wav(_render(0.6, 1.0, func(t: float, _n: float) -> float:
		var note := mini(int(t / 0.2), 2)
		return sin(TAU * [523.25, 659.25, 783.99][note] * t) * exp(-fmod(t, 0.2) * 8.0)))
	_streams.tap = _wav(_render(0.05, 1.0, func(t: float, _n: float) -> float:
		return sin(TAU * 900.0 * t) * exp(-t * 80.0)))
	_streams.pickup = _wav(_render(0.24, 1.0, func(t: float, _n: float) -> float:
		return sin(TAU * (660.0 if t < 0.12 else 990.0) * t) * exp(-fmod(t, 0.12) * 20.0)))
	thrust = _wav(_render(2.0, 400.0, func(_t: float, n: float) -> float: return n))
	thrust.loop_mode = AudioStreamWAV.LOOP_FORWARD
	thrust.loop_end = int(2.0 * RATE)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## One-shot: "impact", "explosion", "goal", "pickup" or "tap". Steals the oldest voice when all are busy.
func play(sound: String, volume_db := 0.0) -> void:
	var player := _players[_next]
	_next = (_next + 1) % VOICES
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.play()


## `shape(t, noise)` gives the sample at time t; noise is white noise through a one-pole low-pass.
func _render(seconds: float, cutoff_hz: float, shape: Callable) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	var smoothing := 1.0 - exp(-TAU * cutoff_hz / RATE)
	var noise := 0.0
	var peak := 0.0
	for i in samples.size():
		noise += smoothing * (_rng.randf_range(-1.0, 1.0) - noise)
		samples[i] = shape.call(float(i) / RATE, noise)
		peak = maxf(peak, absf(samples[i]))
	for i in samples.size():
		samples[i] *= PEAK / peak
	return samples


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(samples[i] * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
