extends "res://tests/test_case.gd"
## Flying near a star scorches the hull: harder the closer, never at all out of range.

const SHIP := "res://scenes/ship.tscn"
const STAR_RADIUS := 600.0


## A star that pulls on nothing, so ships hold their place beside it.
func star() -> void:
	spawn("res://scenes/gravity_body.tscn", Vector2.ZERO, {"preset": GravityBody.Preset.STAR, "radius": STAR_RADIUS, "strength": 0.0})


## A ship `above` px from the star's surface (edge to edge).
func ship_above(above: float, props: Dictionary = {}) -> Ship:
	return spawn(SHIP, Vector2(0, -(STAR_RADIUS + Ship.RADIUS + above)), props)


func test_closer_burns_faster() -> void:
	star()
	var near := ship_above(30.0)
	var mid := ship_above(Ship.HEAT_RANGE * 0.5)
	var far := ship_above(Ship.HEAT_RANGE + 50.0)
	await frames(60)
	var lost := [Ship.MAX_HEALTH - near.health, Ship.MAX_HEALTH - mid.health, Ship.MAX_HEALTH - far.health]
	check(lost[0] > lost[1] * 2.0 and lost[1] > 1.0, "hull lost in 1 s near, mid: %s" % [lost])
	check(lost[2] == 0.0, "out of range must not burn: %s" % [lost])
	check(is_equal_approx(mid.heat(), 0.5), "heat halfway into range: %f" % mid.heat())


func test_heat_can_destroy_the_ship() -> void:
	star()
	var ship := ship_above(20.0, {"hull": 5.0})
	await frames(60)
	check(ship.health == 0.0 and ship.death_cause == "Burned up", "health %f, cause '%s'" % [ship.health, ship.death_cause])


func test_unlimited_hull_does_not_burn() -> void:
	star()
	var ship := ship_above(20.0, {"hull_unlimited": true})
	await frames(60)
	check(ship.health == ship.hull, "an unlimited hull lost health: %f" % ship.health)
