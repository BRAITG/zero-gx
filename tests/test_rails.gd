extends "res://tests/test_case.gd"

const ASTEROID := "res://scenes/asteroid.tscn"
const GRAVITY_BODY := "res://scenes/gravity_body.tscn"
const SHIP := "res://scenes/ship.tscn"


func orbiter(parent: Node, radius: float) -> Asteroid:
	parent.name = "Parent"
	return spawn(ASTEROID, Vector2.ZERO, {"orbit_parent": NodePath("../Parent"), "orbit_radius": radius, "orbit_speed": 1.0})


func test_orbit_is_exact_under_foreign_gravity() -> void:
	var planet = spawn(GRAVITY_BODY, Vector2.ZERO)
	spawn(GRAVITY_BODY, Vector2(400, 0), {"preset": GravityBody.Preset.BLACK_HOLE})
	var rock := orbiter(planet, 150.0)
	for second in 60:
		await frames(60)
		var d := rock.global_position.distance_to(planet.global_position)
		if abs(d - 150.0) >= 1.0:
			check(false, "orbit radius %f at %d s" % [d, second + 1])
			return


func test_ship_knocks_asteroid_off_rails() -> void:
	var planet = spawn(GRAVITY_BODY, Vector2.ZERO)
	var rock := orbiter(planet, 150.0)
	spawn(SHIP, Vector2(150, 300), {"linear_velocity": Vector2(0, -400), "aim_point": Vector2(150, -1000)})
	await frames(90)
	check(not rock.on_rails and not rock.freeze, "a hit must release the asteroid (on_rails=%s freeze=%s)" % [rock.on_rails, rock.freeze])
	await frames(60)
	var d := rock.global_position.distance_to(planet.global_position)
	check(abs(d - 150.0) > 5.0, "released asteroid still on its circle (d=%f)" % d)


func test_released_when_parent_shatters() -> void:
	var planet = spawn(GRAVITY_BODY, Vector2.ZERO, {"destructible": true})
	var rock := orbiter(planet, 250.0)
	await frames(2)
	planet.take_damage(1e9)
	await frames(2)
	check(is_instance_valid(rock) and not rock.on_rails, "the orbiter must be released when its planet shatters")
	check(abs(rock.linear_velocity.length() - 250.0) <= 12.5, "released with speed %f, expected orbital 250" % rock.linear_velocity.length())
