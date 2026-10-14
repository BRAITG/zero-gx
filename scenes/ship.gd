class_name Ship
extends RigidBody2D
## The player: turns toward the touch point, thrusts while the finger is down, burns fuel.

signal destroyed
signal stranded

const MAX_FUEL := 100.0
const FUEL_BURN := 10.0  # per second of thrust
const MAX_HEALTH := 100.0
## s an empty ship has left to reach the goal; a boost pauses the countdown.
const EMPTY_TIMEOUT := 5.0
const LOOKAHEAD := 0.3  # s of velocity the camera leads by
const LOOKAHEAD_MAX := 250.0  # px
## 1/s; eases the lookahead so a bounce's velocity flip doesn't jump the view.
const LOOKAHEAD_SMOOTHING := 3.0
const RADIUS := 16.0
const DAMAGE_PER_SPEED := 0.05  # health per px/s of normal speed change
const MIN_IMPACT_SPEED := 20.0  # px/s; below this a contact is resting, not a hit
## Hard limit whatever the tuning: 20 px per 60 Hz step is under half of barrier thickness +
## ship diameter, so no hit can tunnel.
const TUNNEL_LIMIT := 1200.0
## px/s²; above the tuned speed cap the ship slows toward it instead of snapping down.
const OVERSPEED_DECEL := 400.0
const ENGINE_VOLUME_DB := -10.0
## Damage at which an impact plays at full volume; lighter hits are quieter.
const LOUD_IMPACT_DAMAGE := 30.0

var thrusting := false
var aim_point := Vector2.ZERO
## Starting fuel; a level can give less than a full tank.
@export var fuel := MAX_FUEL
var health := MAX_HEALTH
## Thrust multiplier from a thrust pickup; also scales the speed cap. 1.0 without an effect.
var power := 1.0
## A boost fires the engine at full power, free of fuel, with a wobbling nose.
var boosting := false

var _empty_time := 0.0
var _stranded_sent := false
## Seconds since the first thrust or boost; the level's score clock.
var flight_time := 0.0
## Why the ship was destroyed, for the loss panel.
var death_cause := ""
var _clock_running := false
var _camera: Camera2D
var _engine: AudioStreamPlayer
var _previous_velocity := Vector2.ZERO
## Falls toward the tuned cap at OVERSPEED_DECEL, so neither thrust nor gravity can hold the
## ship above the cap while it slows down.
var _allowed_speed := TUNNEL_LIMIT
## Where the finger rests on screen; null when no touch is held. Re-projected every step,
## because the camera follows the ship and a still finger sends no new events.
var _touch_screen: Variant = null
var _effect_left := 0.0  # s of power effect or boost remaining
var _wobble_phase := 0.0
var _spin := 0.0  # rad/s left from the last glancing hit; decays with Tuning.spin_decay


func _ready() -> void:
	mass = 1.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	physics_material_override = load("res://physics/frictionless.tres")
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.ignore_rotation = true
	add_child(_camera)
	_engine = AudioStreamPlayer.new()
	_engine.stream = Sfx.thrust
	_engine.volume_db = ENGINE_VOLUME_DB
	add_child(_engine)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var step := state.step
	if _touch_screen != null:
		aim_point = get_canvas_transform().affine_inverse() * (_touch_screen as Vector2)
	var to_aim := aim_point - state.transform.origin
	if thrusting and to_aim.length() > 1.0:  # finger up: hold heading and coast
		var turn := wrapf(to_aim.angle() - state.transform.get_rotation(), -PI, PI)
		var rate := Tuning.boost_turn_rate if boosting else Tuning.turn_rate
		state.angular_velocity = clampf(turn / step, -rate, rate)
		_spin = 0.0
	else:
		state.angular_velocity = _spin  # zero unless a recent hit set the ship spinning
		_spin *= exp(-step / Tuning.spin_decay)
	var forward := Vector2.RIGHT.rotated(state.transform.get_rotation())
	if boosting:
		state.angular_velocity += _wobble()
		state.apply_central_force(forward * Tuning.thrust)
	elif thrusting and fuel > 0.0:
		state.apply_central_force(forward * Tuning.thrust * power)
		fuel = maxf(fuel - FUEL_BURN * step, 0.0)
	_clock_running = _clock_running or boosting or (thrusting and fuel > 0.0)
	if _clock_running:
		flight_time += step
	_tick_effect(step)
	_limit_speed(state)
	if fuel == 0.0 and not boosting:
		_empty_time += step
		if _empty_time >= EMPTY_TIMEOUT and not _stranded_sent:
			_stranded_sent = true
			stranded.emit()
	_take_impacts(state)
	queue_redraw()


## Seconds before an empty ship loses the level; negative while there is fuel.
func empty_seconds_left() -> float:
	return -1.0 if fuel > 0.0 else maxf(EMPTY_TIMEOUT - _empty_time, 0.0)


func _limit_speed(state: PhysicsDirectBodyState2D) -> void:
	var speed := state.linear_velocity.length()
	_allowed_speed = clampf(minf(_allowed_speed, speed) - OVERSPEED_DECEL * state.step, Tuning.max_speed * power, TUNNEL_LIMIT)
	if speed > _allowed_speed:
		state.linear_velocity *= _allowed_speed / speed


## Thrust pickup: multiplies thrust and the speed cap for Tuning.effect_seconds, replacing any
## active effect.
func apply_power(multiplier: float) -> void:
	if health <= 0.0:
		return
	boosting = false
	power = multiplier
	_effect_left = Tuning.effect_seconds


## Boost pickup: a free full-power burn for Tuning.boost_seconds, replacing any active effect.
func start_boost() -> void:
	if health <= 0.0:
		return
	power = 1.0
	boosting = true
	_effect_left = Tuning.boost_seconds
	_wobble_phase = randf() * TAU


## HUD text for the active effect, e.g. "Thrust ×1.5 · 6 s"; empty without one.
func effect_text() -> String:
	if boosting:
		return "Boost"
	if power != 1.0:
		return "Thrust ×%.1f · %d s" % [power, ceili(_effect_left)]
	return ""


func _tick_effect(step: float) -> void:
	if _effect_left <= 0.0:
		return
	_effect_left -= step
	if _effect_left <= 0.0:
		power = 1.0
		boosting = false


## Smooth random turning in ±Tuning.boost_wobble: two sines at unrelated rates never repeat soon.
func _wobble() -> float:
	var t := Tuning.boost_seconds - _effect_left
	return Tuning.boost_wobble * (0.6 * sin(2.3 * t + _wobble_phase) + 0.4 * sin(5.1 * t + 2.0 * _wobble_phase))



## Godot 2D reports zero contact impulses for polygon contacts, so the hit strength is the
## velocity change across this step, projected on each contact's normal. One hit per step.
func _take_impacts(state: PhysicsDirectBodyState2D) -> void:
	var velocity_change := state.linear_velocity - _previous_velocity
	_previous_velocity = state.linear_velocity
	var worst := 0.0
	var spin_kick := 0.0
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		var normal := state.get_contact_local_normal(i)
		if collider is Asteroid and collider.on_rails:
			# Equal and opposite to what the ship received along the contact normal.
			collider.release.call_deferred(-velocity_change.project(normal) * mass)
		var multiplier: float = collider.impact_multiplier() if collider and collider.has_method("impact_multiplier") else 0.0
		if multiplier == Impact.LETHAL:
			death_cause = "Lethal surface"
			take_damage(health)
			return
		var speed_change := absf(velocity_change.dot(normal))
		if speed_change >= MIN_IMPACT_SPEED:
			worst = maxf(worst, speed_change * DAMAGE_PER_SPEED * multiplier)
			var sliding := (state.linear_velocity - state.linear_velocity.project(normal)).length()
			spin_kick = maxf(spin_kick, Tuning.spin_per_speed * sliding)
	if spin_kick > 0.0:
		# Turn the nose toward the outgoing direction: glancing hits slide fast, so spin most.
		var toward := signf(wrapf(state.linear_velocity.angle() - state.transform.get_rotation(), -PI, PI))
		_spin = clampf(_spin + spin_kick * toward, -Tuning.spin_max, Tuning.spin_max)
	if worst > 0.0:
		take_damage(worst)


func _process(delta: float) -> void:
	var target := (linear_velocity * LOOKAHEAD).limit_length(LOOKAHEAD_MAX)
	_camera.offset = _camera.offset.lerp(target, 1.0 - exp(-LOOKAHEAD_SMOOTHING * delta))
	var burning := not freeze and (boosting or (thrusting and fuel > 0.0))
	if burning != _engine.playing:
		_engine.playing = burning


func _unhandled_input(event: InputEvent) -> void:
	# Touches arrive as emulated left-mouse events; GUI controls consume theirs first.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		thrusting = event.pressed
		_touch_screen = event.position if event.pressed else null
		aim_point = get_canvas_transform().affine_inverse() * event.position
	elif event is InputEventMouseMotion and _touch_screen != null:
		_touch_screen = event.position


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if health > 0.0:
		Sfx.play("impact", linear_to_db(clampf(amount / LOUD_IMPACT_DAMAGE, 0.2, 1.0)))
		return
	thrusting = false
	if death_cause == "":
		death_cause = "Hull destroyed"
	Sfx.play("explosion")
	destroyed.emit()
	set_deferred("freeze", true)
	hide()


func _draw() -> void:
	var nose := Vector2(RADIUS * 1.4, 0)
	draw_colored_polygon(PackedVector2Array([nose, Vector2(-RADIUS, RADIUS * 0.8), Vector2(-RADIUS * 0.5, 0), Vector2(-RADIUS, -RADIUS * 0.8)]), Color("#e8f1ff"))
	if boosting or (thrusting and fuel > 0.0):
		draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 0.6, RADIUS * 0.4), Vector2(-RADIUS * 2.0, 0), Vector2(-RADIUS * 0.6, -RADIUS * 0.4)]), Color("#ff9a3c"))
