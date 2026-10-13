extends Node
## Live tuning values, edited by the in-game tuning panel. Session only: nothing is saved.
## Autoloaded as `Tuning`; the ship and gravity bodies read it every physics step.

signal changed

const DEFAULTS := {
	"max_speed": 800.0,  # px/s; thrust power scales it
	"thrust": 600.0,  # px/s² (force on a mass-1 ship)
	"turn_rate": 10.0,  # rad/s, finger down
	"boost_turn_rate": 3.0,  # rad/s, finger down during a boost
	"boost_seconds": 1.5,
	"boost_wobble": 1.5,  # rad/s of random turning during a boost
	"power_up": 1.5,  # thrust multiplier
	"power_down": 0.6,  # thrust multiplier
	"effect_seconds": 8.0,
	"planet_gravity": 1.0,  # multiplier on planet pull only
	"spin_per_speed": 0.01,  # rad/s of impact spin per px/s of sliding speed
	"spin_max": 4.0,  # rad/s
	"spin_decay": 0.35,  # s, exponential time constant
}
## [min, max, step] per setting, for the panel's sliders.
const RANGES := {
	"max_speed": [400.0, 1200.0, 50.0],
	"thrust": [300.0, 1200.0, 50.0],
	"turn_rate": [1.0, 15.0, 0.5],
	"boost_turn_rate": [0.5, 10.0, 0.5],
	"boost_seconds": [0.5, 4.0, 0.25],
	"boost_wobble": [0.0, 4.0, 0.25],
	"power_up": [1.0, 3.0, 0.1],
	"power_down": [0.2, 1.0, 0.05],
	"effect_seconds": [2.0, 20.0, 1.0],
	"planet_gravity": [0.25, 4.0, 0.25],
	"spin_per_speed": [0.0, 0.03, 0.0025],
	"spin_max": [0.0, 8.0, 0.5],
	"spin_decay": [0.1, 2.0, 0.05],
}

var max_speed: float
var thrust: float
var turn_rate: float
var boost_turn_rate: float
var boost_seconds: float
var boost_wobble: float
var power_up: float
var power_down: float
var effect_seconds: float
var planet_gravity: float
var spin_per_speed: float
var spin_max: float
var spin_decay: float


func _init() -> void:
	reset()


func reset() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])
	changed.emit()


func set_value(key: String, value: float) -> void:
	assert(key in DEFAULTS, "unknown tuning value %s" % key)
	set(key, value)
	changed.emit()
