extends "res://tests/test_case.gd"

const ASTEROID := "res://scenes/asteroid.tscn"
const GRAVITY_BODY := "res://scenes/gravity_body.tscn"


func asteroids() -> Array:
	return world.get_children().filter(func(n): return n is Asteroid)


func planet(health: float, destructible := true) -> GravityBody:
	return spawn(GRAVITY_BODY, Vector2(400, 0), {"destructible": destructible, "health": health})


func record(sig: Signal) -> Array:
	var hits := []
	sig.connect(func(arg = null): hits.append(arg))
	return hits


func test_swallowed_by_black_hole() -> void:
	spawn(GRAVITY_BODY, Vector2(400, 0), {"preset": GravityBody.Preset.BLACK_HOLE})
	var rock = spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(200, 0)})
	await frames(180)
	check(not is_instance_valid(rock), "a black hole must destroy the asteroid")


func test_planet_takes_damage_from_asteroid() -> void:
	var target := planet(100.0)
	var struck := record(target.struck)
	var rock = spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(400, 0)})
	await frames(90)
	check(target.health > 0.0 and target.health < 100.0, "planet health %f, expected 0..100 exclusive" % target.health)
	check(struck.has(rock), "struck must name the asteroid")


func test_indestructible_planet_ignores_hits() -> void:
	var target := planet(100.0, false)
	var struck := record(target.struck)
	spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(400, 0)})
	await frames(90)
	check(target.health == 100.0, "indestructible planet lost health: %f" % target.health)
	check(not struck.is_empty(), "struck is emitted even when the planet cannot break")


func shatter_planet() -> Dictionary:
	var target := planet(1.0)
	var shattered := record(target.shattered)
	var rock = spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(400, 0)})
	await frames(60)
	return {"planet": target, "shattered": shattered, "rock": rock}


func test_shatter() -> void:
	var result := await shatter_planet()
	check(not is_instance_valid(result.planet), "a planet at 0 health must be removed")
	check(result.shattered.size() == 1, "shattered emitted %d times" % result.shattered.size())
	var shards := asteroids().size() - (1 if is_instance_valid(result.rock) else 0)
	check(shards >= GravityBody.SHARDS_MIN and shards <= GravityBody.SHARDS_MAX, "%d shards, expected 12..20" % shards)


func test_gravity_gone_after_shatter() -> void:
	await shatter_planet()
	await frames(5)
	for rock in asteroids():
		rock.free()
	var probe := RigidBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	probe.add_child(shape)
	probe.position = Vector2(400, 150)
	world.add_child(probe)
	await frames(10)
	check(probe.linear_velocity == Vector2.ZERO, "a shattered planet still pulls: %s" % probe.linear_velocity)
