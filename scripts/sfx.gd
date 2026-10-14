extends Node
## Sound effects (Kenney CC0 samples in assets/sounds) and a synthesized ambient drone.
## Autoloaded as `Sfx` so a sound started just before a scene change keeps playing.

const VOICES := 8
const SOUNDS := ["zap", "impact", "explosion", "boom", "power_up", "power_down", "boost", "goal", "tap", "tick"]
const DRONE_RATE := 22050
const DRONE_SECONDS := 4.0  # every partial and the swell complete whole cycles, so the loop is seamless
const DRONE_VOLUME_DB := -20.0
const DRONE_PAD := 64  # frames rendered past the loop end

## Looping engine for the ship's own player.
var thrust: AudioStream
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # taps on the tuning panel play while the game is paused
	for sound: String in SOUNDS:
		_streams[sound] = load("res://assets/sounds/%s.ogg" % sound)
	thrust = load("res://assets/sounds/engine.ogg").duplicate()
	thrust.loop = true
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	var drone := AudioStreamPlayer.new()
	drone.stream = _drone()
	drone.volume_db = DRONE_VOLUME_DB
	add_child(drone)
	drone.play()


## One-shot from SOUNDS. Steals the oldest voice when all are busy.
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var player := _players[_next]
	_next = (_next + 1) % VOICES
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## A low, slowly beating pad: 55 Hz with a 55.25 Hz twin, a fifth and an octave, swelling every 4 s.
func _drone() -> AudioStreamWAV:
	var count := int(DRONE_SECONDS * DRONE_RATE)
	var data := PackedByteArray()
	# The mixer reads a little past loop_end when it wraps (crashed on Android without this):
	# render extra frames, which continue the waveform seamlessly because every partial is periodic.
	data.resize((count + DRONE_PAD) * 2)
	for i in count + DRONE_PAD:
		var t := float(i) / DRONE_RATE
		var pad := 0.45 * sin(TAU * 55.0 * t) + 0.35 * sin(TAU * 55.25 * t) + 0.25 * sin(TAU * 82.5 * t) + 0.15 * sin(TAU * 110.0 * t)
		var swell := 0.7 + 0.3 * sin(TAU * t / DRONE_SECONDS)
		data.encode_s16(i * 2, int(clampf(pad * swell * 0.6, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = DRONE_RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = count
	return wav
