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
const ENGINE_VOLUME_DB := -28.0
## Damage at which an impact plays at full volume; lighter hits are quieter.
const LOUD_IMPACT_DAMAGE := 30.0
## Camera shake: trauma 0..1 adds up per hit, the offset grows with its square, and it decays.
const SHAKE_MAX := 18.0  # px at full trauma
const SHAKE_DECAY := 1.6  # trauma per second
const TRAIL_POINTS := 45  # rendered frames of exhaust trail, about 0.75 s
const HULL := Color("#dfe9ff")
const HULL_EDGE := Color("#7fb4ff")
const FLAME := Color("#ff8a3c")
const FLAME_CORE := Color("#fff1b8")
const HEAT_RANGE := 300.0  # px above a star's surface where its heat starts to scorch the hull
const HEAT_DAMAGE := 40.0  # hull per second at the surface; it falls with the square of the heat
const HEAT_RED := Color("#ff3b1f")
const BURN_VOLUME_DB := -22.0  # the burning roar at full heat
const VELOCITY_ARROW_SCALE := 0.25  # px of arrow per px/s
const VELOCITY_ARROW_MAX := 200.0  # px
const EXACT_ALIGN_DEGREES := 0.5  # the turn lands exactly on the aim within a tick; this only absorbs float error

var thrusting := false
## Turn toward aim_point without thrust (a ship that steers while its engine is on a separate button).
var steering := false
## Engine waits until the nose has pointed within Tuning.align_degrees of the finger.
var align_gate := true
## The ring assist sets this: the engine waits for the nose to be exactly on the ring, not Tuning.align_degrees.
var align_exact := false
var aim_point := Vector2.ZERO
## Starting fuel; a level can give less than a full tank.
@export var fuel := MAX_FUEL
## Nothing hurts the ship, lethal surfaces included (a tutorial's scripted close call).
var invulnerable := false
## Starting (and maximum) hull for this level.
@export var hull := MAX_HEALTH
## A level can make either unlimited: no fuel burn or empty-tank timeout; no damage but lethal.
@export var fuel_unlimited := false
@export var hull_unlimited := false
var health := MAX_HEALTH
## Thrust multiplier from a thrust pickup; also scales the speed cap. 1.0 without an effect.
var power := 1.0
## A boost fires the engine at full power, free of fuel, with a wobbling nose.
var boosting := false
## True while the engine actually fires: a boost, or the finger is down with fuel left and the
## nose has pointed within Tuning.align_degrees of the finger at some moment of this press.
var firing := false
## Draw the velocity vector from the ship (tutorials and the first levels).
var show_velocity := false
## Set once the nose first meets the finger during a press; cleared when the finger lifts. A drag
## keeps the engine on while the nose catches up; only a fresh press waits for alignment.
var _press_aligned := false

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
## Where the finger or cursor aims on screen (set by ShipInput); null when none. Re-projected every
## step, because the camera follows the ship and a still finger sends no new events.
var touch_screen: Variant = null
var _effect_left := 0.0  # s of power effect or boost remaining
var _wobble_phase := 0.0
var _spin := 0.0  # rad/s left from the last glancing hit; decays with Tuning.spin_decay
## False while a tutorial's rings own a one-finger ship: ShipInput leaves it alone. The schemes
## that aim freely (keys, pad, mouse, sticks) steer and fire regardless.
var accept_input := true
## Where a tutorial's `wait` ring holds the ship: motionless there, still free to turn; null lets it fly.
var anchor: Variant = null
var _respawn: Variant = null  # [position, velocity] to apply on the next physics step
var _lookahead := Vector2.ZERO
var _trauma := 0.0
var _flash := 0.0  # 1 right after a hit, fading to 0
## 0 out of any star's heat, 1 at a star's surface; see heat().
var _heat := 0.0
var _heat_phase := 0.0  # radians of the heat pulse
var _burn: AudioStreamPlayer
var _trail: Line2D
var _exhaust: CPUParticles2D
var _tick_rotation := [0.0, 0.0]  # `rotation` at the last two physics ticks


func _ready() -> void:
	_tick_rotation = [rotation, rotation]
	mass = 1.0
	z_index = 2  # above stars, which draw over walls
	health = hull
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
	_burn = AudioStreamPlayer.new()
	_burn.stream = Sfx.burn
	add_child(_burn)
	_trail = Line2D.new()
	_trail.top_level = true  # world-space points: the trail stays where the ship has been
	_trail.width = 4.0
	_trail.z_index = -1
	_trail.gradient = Gradient.new()
	_trail.gradient.set_color(0, Color(HULL_EDGE, 0.0))
	_trail.gradient.set_color(1, Color(HULL_EDGE, 0.45))
	add_child(_trail)
	_exhaust = CPUParticles2D.new()
	_exhaust.position = Vector2(-RADIUS * 0.8, 0)
	_exhaust.emitting = false
	_exhaust.amount = 48
	_exhaust.lifetime = 0.45
	_exhaust.local_coords = false
	_exhaust.direction = Vector2.LEFT
	_exhaust.spread = 12.0
	_exhaust.initial_velocity_min = 140.0
	_exhaust.initial_velocity_max = 260.0
	_exhaust.scale_amount_min = 2.0
	_exhaust.scale_amount_max = 4.0
	_exhaust.color_ramp = _ramp([Color(FLAME_CORE, 0.9), Color(FLAME, 0.7), Color(FLAME, 0.0)])
	add_child(_exhaust)


## Make the ship's follow camera the active one again (after a level tour).
func use_camera() -> void:
	_camera.make_current()


## Camera shake, 0..1; hits add up.
func shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


static func _ramp(colors: Array) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array(range(colors.size()).map(func(i: int) -> float: return float(i) / (colors.size() - 1)))
	ramp.colors = PackedColorArray(colors)
	return ramp


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _respawn != null:  # teleport inside the physics step, where it is safe
		state.transform = Transform2D(state.transform.get_rotation(), _respawn[0])
		state.linear_velocity = _respawn[1]
		state.angular_velocity = 0.0
		_previous_velocity = _respawn[1]
		_respawn = null
		return
	var step := state.step
	if anchor != null:  # held in place: no drift, whatever gravity does, but the turn below still runs
		state.transform = Transform2D(state.transform.get_rotation(), anchor as Vector2)
		state.linear_velocity = Vector2.ZERO
	if touch_screen != null:
		aim_point = get_canvas_transform().affine_inverse() * (touch_screen as Vector2)
	var to_aim := aim_point - state.transform.origin
	var aligned := true
	if (steering or (thrusting and align_gate)) and to_aim.length() > 1.0:  # finger up: hold heading and coast
		var turn := wrapf(to_aim.angle() - state.transform.get_rotation(), -PI, PI)
		var rate := Tuning.boost_turn_rate if boosting else Tuning.turn_rate
		state.angular_velocity = clampf(turn / step, -rate, rate)
		var tolerance := EXACT_ALIGN_DEGREES if align_exact else Tuning.align_degrees
		aligned = absf(turn) <= deg_to_rad(tolerance)
		_spin = 0.0
	else:
		state.angular_velocity = _spin  # zero unless a recent hit set the ship spinning
		_spin *= exp(-step / Tuning.spin_decay)
	var forward := Vector2.RIGHT.rotated(state.transform.get_rotation())
	_press_aligned = thrusting and (_press_aligned or aligned)
	firing = boosting or (thrusting and fuel > 0.0 and (_press_aligned or not align_gate))
	if boosting:
		state.angular_velocity += _wobble()
		state.apply_central_force(forward * Tuning.thrust)
	elif firing:
		state.apply_central_force(forward * Tuning.thrust * power)
		if not fuel_unlimited:
			fuel = maxf(fuel - FUEL_BURN * step, 0.0)
	_clock_running = _clock_running or firing
	if _clock_running:
		flight_time += step
	_tick_effect(step)
	_scorch(step)
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
	var hit_wall := false
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
			take_damage(health, true)
			return
		var speed_change := absf(velocity_change.dot(normal))
		if speed_change >= MIN_IMPACT_SPEED:
			var damage := speed_change * DAMAGE_PER_SPEED * multiplier
			if damage > worst:
				worst = damage
				hit_wall = collider is Barrier
			var sliding := (state.linear_velocity - state.linear_velocity.project(normal)).length()
			spin_kick = maxf(spin_kick, Tuning.spin_per_speed * sliding)
	if spin_kick > 0.0:
		# Turn the nose toward the outgoing direction: glancing hits slide fast, so spin most.
		var toward := signf(wrapf(state.linear_velocity.angle() - state.transform.get_rotation(), -PI, PI))
		_spin = clampf(_spin + spin_kick * toward, -Tuning.spin_max, Tuning.spin_max)
	if worst > 0.0:
		var loudness := clampf(worst / LOUD_IMPACT_DAMAGE, 0.2, 1.0)
		Sfx.play("zap" if hit_wall else "impact", linear_to_db(loudness))
		take_damage(worst)


func _process(delta: float) -> void:
	var target := (linear_velocity * LOOKAHEAD).limit_length(LOOKAHEAD_MAX)
	_lookahead = _lookahead.lerp(target, 1.0 - exp(-LOOKAHEAD_SMOOTHING * delta))
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAX * _trauma * _trauma
	_camera.offset = _lookahead + jitter
	_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
	_flash = maxf(_flash - 4.0 * delta, 0.0)
	_heat_phase += TAU * (1.5 + 6.0 * _heat) * delta  # pulses faster the hotter it gets
	var scorching := _heat > 0.0 and visible
	if scorching != _burn.playing:
		_burn.playing = scorching
	if scorching:
		_burn.volume_db = BURN_VOLUME_DB + linear_to_db(_heat)
	var burning := not freeze and firing
	if burning != _engine.playing:
		_engine.playing = burning
	_engine.pitch_scale = 0.85 + 0.35 * clampf(linear_velocity.length() / Tuning.max_speed, 0.0, 1.0)
	_exhaust.emitting = burning
	if not freeze:
		_trail.add_point(global_position)
		if _trail.get_point_count() > TRAIL_POINTS:
			_trail.remove_point(0)
	if _flash > 0.0 or _heat > 0.0 or show_velocity:
		queue_redraw()


## Bring the ship back whole at `at` with `velocity` and `with_fuel` (Training 6's rescue).
func respawn(at: Vector2, velocity: Vector2, with_fuel: float) -> void:
	health = hull
	fuel = with_fuel
	death_cause = ""
	thrusting = false
	anchor = null
	align_exact = false
	_stranded_sent = false
	_empty_time = 0.0
	_spin = 0.0
	_trail.clear_points()
	_respawn = [at, velocity]
	freeze = false
	set_deferred("freeze", false)  # a death in the physics step defers its freeze; outlast it
	show()


## `lethal` hits (red walls, black holes, stars) destroy the ship even with an unlimited hull.
func take_damage(amount: float, lethal := false) -> void:
	if health <= 0.0 or invulnerable:
		return
	if not hull_unlimited or lethal:
		health = maxf(health - amount, 0.0) if not lethal else 0.0
	var strength := clampf(amount / LOUD_IMPACT_DAMAGE, 0.2, 1.0)
	if health > 0.0:
		_flash = 1.0
		shake(0.5 * strength)
		Input.vibrate_handheld(int(20 + 60 * strength), strength)
		return
	thrusting = false
	if death_cause == "":
		death_cause = "Hull destroyed"
	Sfx.play("explosion")
	Sfx.play("boom")
	shake(1.0)
	Input.vibrate_handheld(350, 1.0)
	_explode()
	destroyed.emit()
	set_deferred("freeze", true)
	hide()


## A one-shot burst of sparks left behind in the level, since the ship itself hides.
func _explode() -> void:
	var sparks := CPUParticles2D.new()
	sparks.global_position = global_position
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 70
	sparks.lifetime = 0.9
	sparks.spread = 180.0
	sparks.initial_velocity_min = 80.0
	sparks.initial_velocity_max = 380.0
	sparks.damping_min = 60.0
	sparks.damping_max = 120.0
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 5.0
	sparks.color_ramp = _ramp([Color.WHITE, FLAME_CORE, FLAME, Color(FLAME, 0.0)])
	get_parent().add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(sparks.lifetime + 0.5).timeout.connect(sparks.queue_free)


## How hot the nearest star makes the ship: 0 beyond HEAT_RANGE from its surface, 1 touching it.
func heat() -> float:
	var hottest := 0.0
	for star: GravityBody in get_tree().get_nodes_in_group("stars"):
		var above := global_position.distance_to(star.global_position) - star.radius - RADIUS
		hottest = maxf(hottest, 1.0 - above / HEAT_RANGE)
	return clampf(hottest, 0.0, 1.0)


## A star's heat wears the hull down, faster the closer the ship flies.
func _scorch(step: float) -> void:
	_heat = heat() if health > 0.0 else 0.0
	if _heat <= 0.0 or invulnerable or hull_unlimited:
		return
	health -= HEAT_DAMAGE * _heat * _heat * step
	if health <= 0.0:
		health = 0.01  # take_damage ends the ship, with its explosion and signal
		death_cause = "Burned up"
		take_damage(1.0, true)


## The velocity arrow's length on screen: proportional to speed, capped.
func velocity_arrow_length() -> float:
	return minf(linear_velocity.length() * VELOCITY_ARROW_SCALE, VELOCITY_ARROW_MAX)


## Where the velocity arrow ends, in the ship's own drawing space: the world direction of travel,
## undone by the rotation the ship is drawn with.
func velocity_arrow_tip() -> Vector2:
	return linear_velocity.normalized().rotated(-_drawn_rotation()) * velocity_arrow_length()


## Physics interpolation draws the ship at a rotation between its last two physics ticks; the
## physics `rotation` is only right at a tick, and turning fast it differs from the drawn one.
func _drawn_rotation() -> float:
	return lerp_angle(_tick_rotation[0], _tick_rotation[1], Engine.get_physics_interpolation_fraction())


func _physics_process(_delta: float) -> void:
	_tick_rotation = [_tick_rotation[1], rotation]


func _draw() -> void:
	var nose := Vector2(RADIUS * 1.4, 0)
	var hull := PackedVector2Array([nose, Vector2(-RADIUS, RADIUS * 0.8), Vector2(-RADIUS * 0.5, 0), Vector2(-RADIUS, -RADIUS * 0.8), nose])
	if firing:
		var reach := RADIUS * randf_range(1.7, 2.4)  # flicker
		draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 0.6, RADIUS * 0.45), Vector2(-reach, 0), Vector2(-RADIUS * 0.6, -RADIUS * 0.45)]), FLAME)
		draw_colored_polygon(PackedVector2Array([Vector2(-RADIUS * 0.6, RADIUS * 0.22), Vector2(-reach * 0.7, 0), Vector2(-RADIUS * 0.6, -RADIUS * 0.22)]), FLAME_CORE)
	var glow := _heat * (0.6 + 0.4 * sin(_heat_phase))  # redder and stronger near a star
	if glow > 0.0:
		draw_circle(Vector2.ZERO, RADIUS * (1.4 + 0.8 * glow), Color(HEAT_RED, 0.45 * glow))
	draw_colored_polygon(hull.slice(0, 4), HULL.lerp(Color("#ff5a4a"), _flash).lerp(HEAT_RED, glow))
	draw_polyline(hull, HULL_EDGE.lerp(HEAT_RED, glow), 2.0, true)
	draw_circle(Vector2(RADIUS * 0.35, 0), RADIUS * 0.18, Color("#3aa0ff"))
	if show_velocity and linear_velocity.length() > 1.0:
		# World direction: undo the ship's own rotation.
		var tip := velocity_arrow_tip()
		var arrow := Color(1, 1, 1, 0.45)
		draw_line(Vector2.ZERO, tip, arrow, 3.0, true)
		var back := -tip.normalized() * 14.0
		draw_colored_polygon(PackedVector2Array([tip, tip + back.rotated(0.45), tip + back.rotated(-0.45)]), arrow)
