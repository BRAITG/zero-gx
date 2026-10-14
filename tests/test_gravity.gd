extends "res://tests/test_case.gd"

const GRAVITY_BODY := "res://scenes/gravity_body.tscn"
const PLANET_PULL: float = GravityBody.PRESETS[GravityBody.Preset.PLANET][1]


func probe(pos: Vector2) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.can_sleep = false
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 2.0
	body.add_child(shape)
	body.position = pos
	world.add_child(body)
	return body


## Gravity the physics server applied to `body` in the last step.
func pull(body: RigidBody2D) -> Vector2:
	return PhysicsServer2D.body_get_direct_state(body.get_rid()).total_gravity


func near(a: float, b: float, tolerance: float) -> bool:
	return abs(a - b) <= abs(b) * tolerance


func test_inverse_square() -> void:
	spawn(GRAVITY_BODY, Vector2.ZERO)
	var close := probe(Vector2(128, 0))
	var far := probe(Vector2(256, 0))
	await frames(3)  # Area overlap registers on the third step.
	var expected_close := PLANET_PULL * pow(64.0 / 128.0, 2)
	check(near(pull(close).length(), expected_close, 0.02), "pull at 128 = %s, expected %f" % [pull(close), expected_close])
	check(pull(close).x < 0, "pull must point at the planet: %s" % pull(close))
	check(near(pull(close).length(), 4.0 * pull(far).length(), 0.02), "not inverse-square: %s vs %s" % [pull(close), pull(far)])


func test_zero_beyond_reach() -> void:
	spawn(GRAVITY_BODY, Vector2.ZERO)
	var outside := probe(Vector2(500, 0))
	await frames(10)
	check(pull(outside) == Vector2.ZERO, "pull beyond reach = %s" % pull(outside))
	check(outside.linear_velocity == Vector2.ZERO, "moved beyond reach: %s" % outside.linear_velocity)


func test_pulls_add() -> void:
	spawn(GRAVITY_BODY, Vector2(-200, 0))
	spawn(GRAVITY_BODY, Vector2(200, 0))
	var middle := probe(Vector2(0, 100))
	await frames(3)  # Area overlap registers on the third step.
	var d := Vector2(200, 100).length()
	var expected_y := 2.0 * PLANET_PULL * pow(64.0 / d, 2) * (100.0 / d)
	check(abs(pull(middle).x) < 0.01 * expected_y, "x pulls must cancel: %s" % pull(middle))
	check(near(-pull(middle).y, expected_y, 0.02), "summed pull %s, expected y %f" % [pull(middle), -expected_y])


func test_multipliers() -> void:
	var planet = spawn(GRAVITY_BODY, Vector2.ZERO)
	var hole = spawn(GRAVITY_BODY, Vector2(2000, 0), {"preset": 1})
	var star = spawn(GRAVITY_BODY, Vector2(9000, 0), {"preset": 2})
	check(planet.impact_multiplier() == 1.0, "planet multiplier %f" % planet.impact_multiplier())
	check(hole.impact_multiplier() == Impact.LETHAL, "black hole must be lethal")
	check(star.impact_multiplier() == Impact.LETHAL, "star must be lethal")


func test_planet_gravity_multiplier() -> void:
	Tuning.set_value("planet_gravity", 2.0)
	spawn(GRAVITY_BODY, Vector2.ZERO)
	spawn(GRAVITY_BODY, Vector2(0, 5000), {"preset": GravityBody.Preset.STAR})
	var near_planet := probe(Vector2(128, 0))
	var near_star := probe(Vector2(0, 5000 - 1200))
	await frames(3)
	var expected := 2.0 * PLANET_PULL * pow(64.0 / 128.0, 2)
	check(near(pull(near_planet).length(), expected, 0.02), "planet pull %f, expected %f" % [pull(near_planet).length(), expected])
	var star := 3000.0 * pow(600.0 / 1200.0, 2)
	check(near(pull(near_star).length(), star, 0.02), "star pull %f, expected unchanged %f" % [pull(near_star).length(), star])


func test_field_opacity_follows_pull() -> void:
	var planet: GravityBody = spawn(GRAVITY_BODY, Vector2.ZERO)
	var hole: GravityBody = spawn(GRAVITY_BODY, Vector2(0, 3000), {"preset": GravityBody.Preset.BLACK_HOLE})
	check(planet.field_alpha(100) > planet.field_alpha(300), "opacity must fall with distance")
	check(planet.field_alpha(300) > 0.0, "the weak outer field must stay visible")
	check(planet.field_alpha(planet.reach + 1) == 0.0, "no field beyond reach")
	check(hole.field_alpha(100) > planet.field_alpha(100), "a stronger body must look stronger")
	var before := planet.field_alpha(100)
	Tuning.set_value("planet_gravity", 2.0)
	check(planet.field_alpha(100) > before, "the planet gravity slider must show in the field")
