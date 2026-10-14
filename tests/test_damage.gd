extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const BARRIER := "res://scenes/barrier.tscn"
const GRAVITY_BODY := "res://scenes/gravity_body.tscn"
const WALL_X := 300.0


## A vertical barrier at x = 300 from y = -500 to 500.
func wall(kind: int) -> Node:
	var barrier: Node = load(BARRIER).instantiate()
	barrier.kind = kind
	barrier.get_node("Shape").points = PackedVector2Array([Vector2(WALL_X, -500), Vector2(WALL_X, 500)])
	world.add_child(barrier)
	return barrier


func ship_at(pos: Vector2, velocity: Vector2) -> Node:
	return spawn(SHIP, pos, {"linear_velocity": velocity, "aim_point": pos + velocity.normalized() * 1000.0})


func damage_head_on(kind: int) -> float:
	wall(kind)
	var ship = ship_at(Vector2.ZERO, Vector2(500, 0))
	await frames(90)
	return 100.0 - ship.health


func test_head_on_orange_damage() -> void:
	var damage: float = await damage_head_on(Barrier.Kind.ORANGE)
	check(damage >= 35.0 and damage <= 55.0, "head-on orange damage %f, expected 35..55" % damage)


func test_graze_hurts_less() -> void:
	wall(Barrier.Kind.ORANGE)
	var ship = ship_at(Vector2(200, 0), Vector2(500, 0).rotated(deg_to_rad(-75)))
	await frames(90)
	var damage: float = 100.0 - ship.health
	check(damage < 0.4 * 45.0, "15° graze damage %f, expected under 40%% of a head-on hit" % damage)


func test_blue_is_mild() -> void:
	var damage: float = await damage_head_on(Barrier.Kind.BLUE)
	check(damage >= 3.5 and damage <= 5.5, "head-on blue damage %f, expected 3.5..5.5" % damage)


func test_red_kills_on_touch() -> void:
	wall(Barrier.Kind.RED)
	var ship = ship_at(Vector2(250, 0), Vector2(30, 0))
	await frames(120)
	check(ship.health == 0.0, "a slow touch on red must kill; health %f" % ship.health)


func test_fast_hit_does_not_tunnel() -> void:
	wall(Barrier.Kind.BLUE)
	var ship = ship_at(Vector2.ZERO, Vector2(3000, 0))
	await frames(60)
	check(ship.position.x < WALL_X, "ship tunneled to x=%f" % ship.position.x)


func test_resting_contact_is_harmless() -> void:
	wall(Barrier.Kind.BLUE)
	spawn(GRAVITY_BODY, Vector2(500, 0))  # Pulls the ship into the wall and keeps it there.
	var ship = ship_at(Vector2(WALL_X - Ship.RADIUS - 0.5, 0), Vector2.ZERO)
	await frames(300)
	check(ship.health == 100.0, "resting contact cost %f health" % (100.0 - ship.health))


func test_black_hole_kills() -> void:
	spawn(GRAVITY_BODY, Vector2(200, 0), {"preset": GravityBody.Preset.BLACK_HOLE})
	var ship = ship_at(Vector2.ZERO, Vector2(50, 0))
	await frames(120)
	check(ship.health == 0.0, "touching a black hole must kill; health %f" % ship.health)


func test_planet_surface_damage() -> void:
	spawn(GRAVITY_BODY, Vector2(400, 0))
	var ship = ship_at(Vector2.ZERO, Vector2(500, 0))
	await frames(90)
	var damage: float = 100.0 - ship.health
	check(damage >= 15.0 and damage <= 55.0, "head-on planet damage %f, expected 15..55" % damage)


func test_bounce_does_not_jerk_camera() -> void:
	wall(Barrier.Kind.BLUE)
	var ship = ship_at(Vector2.ZERO, Vector2(500, 0))
	var camera: Camera2D = ship.find_children("*", "Camera2D", true, false)[0]
	var last := camera.offset
	var worst := 0.0
	for i in 90:
		await frames(1)
		worst = maxf(worst, camera.offset.distance_to(last))
		last = camera.offset
	check(ship.linear_velocity.x < 0.0, "ship should have bounced")
	check(worst < 30.0, "camera offset jumped %.0f px in one frame" % worst)
