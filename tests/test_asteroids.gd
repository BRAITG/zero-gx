extends "res://tests/test_case.gd"

const ASTEROID := "res://scenes/asteroid.tscn"
const GRAVITY_BODY := "res://scenes/gravity_body.tscn"


func asteroids() -> Array:
	return world.get_children().filter(func(n): return n is Asteroid)


func record(sig: Signal) -> Array:
	var hits := []
	sig.connect(func(arg = null): hits.append(arg))
	return hits


func test_swallowed_by_black_hole() -> void:
	spawn(GRAVITY_BODY, Vector2(400, 0), {"preset": GravityBody.Preset.BLACK_HOLE})
	var rock = spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(200, 0)})
	await frames(180)
	check(not is_instance_valid(rock), "a black hole must destroy the asteroid")


func test_planet_emits_struck_on_asteroid_hit() -> void:
	var target: GravityBody = spawn(GRAVITY_BODY, Vector2(400, 0))
	var struck := record(target.struck)
	var rock = spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(400, 0)})
	await frames(90)
	check(struck.has(rock), "struck must name the asteroid")


func test_ship_knocks_an_asteroid_away() -> void:
	var rock = spawn(ASTEROID, Vector2(200, 0))
	var ship = spawn("res://scenes/ship.tscn", Vector2.ZERO, {"linear_velocity": Vector2(400, 0), "aim_point": Vector2(1000, 0)})
	await frames(60)
	check(rock.linear_velocity.x > ship.linear_velocity.x + 50.0, "no bounce: rock %s, ship %s" % [rock.linear_velocity, ship.linear_velocity])


func test_asteroids_bounce_off_each_other() -> void:
	var moving = spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(300, 0)})
	var still = spawn(ASTEROID, Vector2(200, 0))
	await frames(60)
	check(still.linear_velocity.x > moving.linear_velocity.x + 50.0, "no bounce: %s vs %s" % [moving.linear_velocity, still.linear_velocity])
