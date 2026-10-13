extends "res://tests/test_case.gd"

const SHIP := "res://scenes/ship.tscn"
const PICKUP := "res://scenes/pickup.tscn"
const ASTEROID := "res://scenes/asteroid.tscn"


## Fly a ship through a pickup of `kind`; returns [ship, pickup] after 60 frames.
func fly_through(kind: int) -> Array:
	var pickup := spawn(PICKUP, Vector2(150, 0), {"kind": kind})
	var ship := spawn(SHIP, Vector2.ZERO, {"linear_velocity": Vector2(300, 0)})
	await frames(60)
	return [ship, pickup]


func test_ship_collects_thrust_up() -> void:
	var got: Array = await fly_through(Pickup.Kind.THRUST_UP)
	check(got[0].power == Tuning.power_up, "power %f, expected %f" % [got[0].power, Tuning.power_up])
	check(not is_instance_valid(got[1]), "pickup still there after collection")


func test_thrust_down_and_boost_apply() -> void:
	var down: Array = await fly_through(Pickup.Kind.THRUST_DOWN)
	check(down[0].power == Tuning.power_down, "power %f, expected %f" % [down[0].power, Tuning.power_down])
	down[0].free()
	var boost: Array = await fly_through(Pickup.Kind.BOOST)
	check(boost[0].boosting, "boost pickup did not start a boost")


func test_asteroid_passes_through() -> void:
	var pickup := spawn(PICKUP, Vector2(150, 0), {"kind": Pickup.Kind.THRUST_UP})
	spawn(ASTEROID, Vector2.ZERO, {"linear_velocity": Vector2(300, 0)})
	await frames(60)
	check(is_instance_valid(pickup), "an asteroid collected the pickup")
