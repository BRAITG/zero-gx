extends "res://tests/test_case.gd"


func test_empty_population_is_not_an_estimate() -> void:
	check(RankEstimate.estimate(50, 0, []) == {"text": "No ranked runs yet", "badge": "", "approximate": false}, "an empty board must not invent a rank")
	_unavailable(RankEstimate.estimate(50, 0, _linear()))


func test_one_and_small_populations_can_be_in_the_top_twenty() -> void:
	for count in range(1, 20):
		for points in [0, 50, 100]:
			_top_twenty(RankEstimate.estimate(points, count, _equal(50)))
			_top_twenty(RankEstimate.estimate(points, count, _small(), 10))


func test_endpoints_and_interpolation_use_the_whole_population() -> void:
	var q := _linear()
	check(RankEstimate.estimate(0, 100, q).text == "Estimate: about top 100% · ~100 of 101", "minimum equality excludes the known minimum from the strictly higher count")
	check(RankEstimate.estimate(100, 100, q).text == "Estimate: about top 51% · ~51 of 101", "the median must use the full population, not the top twenty")
	check(RankEstimate.estimate(105, 100, q).text == "Estimate: about top 49% · ~49 of 101", "halfway between quantiles must interpolate")
	_top_twenty(RankEstimate.estimate(200, 100, q))
	_top_twenty(RankEstimate.estimate(201, 100, q))


func test_twentieth_score_equality_is_a_potential_top_entry() -> void:
	var q := _linear()
	_top_twenty(RankEstimate.estimate(160, 100, q, 160))
	_top_twenty(RankEstimate.estimate(161, 100, q, 160))
	check(RankEstimate.estimate(159, 100, q, 160).text == "Estimate: about top 22% · ~22 of 101", "strictly lower points must retain a worse interpolated rank than the rank-21 floor")
	check(RankEstimate.estimate(1, 20, q, 0).text == "Estimate: would be in the top 20", "the twentieth score itself must not be rank 21")


func test_rank_twenty_one_floor_needs_twenty_players_and_a_boundary() -> void:
	var q := _linear()
	check(RankEstimate.estimate(190, 100, q).text == "Estimate: about top 6% · ~6 of 101", "no twentieth score means no invented rank-21 floor")
	check(RankEstimate.estimate(190, 100, q, 195).text == "Estimate: about top 21% · ~21 of 101", "a known strictly higher twentieth score sets the floor")
	check(RankEstimate.estimate(199, 20, q, 200).text == "Estimate: about top 100% · ~21 of 21", "the rank-21 floor must remain within the population")
	q[18] = 190
	check(RankEstimate.estimate(190, 100, q).text == "Estimate: about top 2–6% · ~2–6 of 101", "a repeated high score retains the uncertainty after its last equal sample")
	check(RankEstimate.estimate(190, 100, q, 195).text == "Estimate: about top 21% · ~21 of 101", "the known twentieth-score floor clamps both tie-interval endpoints")


func test_ties_at_the_maximum_always_have_potential_top_standing() -> void:
	_top_twenty(RankEstimate.estimate(50, 100, _equal(50)))
	check(RankEstimate.estimate(49, 100, _equal(50)).text == "Estimate: about top 100% · ~101 of 101", "below an equal population must be last")
	_top_twenty(RankEstimate.estimate(51, 100, _equal(50)))
	_top_twenty(RankEstimate.estimate(50, 100, _equal(50), 50))
	var repeated_max := _linear()
	repeated_max[19] = 200
	_top_twenty(RankEstimate.estimate(200, 100, repeated_max))


func test_plateau_uses_its_end_and_next_nearest_rank_sample() -> void:
	var q := _linear()
	for i in range(8, 13):
		q[i] = 100
	var estimate := RankEstimate.estimate(100, 1000, q)
	check(estimate.text == "Estimate: about top 36–41% · ~352–401 of 1001", "only the tie's end determines the strictly higher-score count")
	check(estimate.badge == "Estimate: ~top 36–41%", "compact estimates must preserve the interval")
	check(RankEstimate.estimate(85, 1000, q).text == "Estimate: about top 63% · ~626 of 1001", "interpolation into a plateau must not divide by zero")
	check(RankEstimate.estimate(115, 1000, q).text == "Estimate: about top 38% · ~376 of 1001", "interpolation out of a plateau must use its last endpoint")
	check(RankEstimate.estimate(100, 103, q).text == "Estimate: about top 37–41% · ~38–42 of 104", "interval endpoints must use nearest-rank sample positions, not rounded percentile fractions")


func test_minimum_equality_excludes_known_equal_scores() -> void:
	var q := _linear()
	for i in q.size():
		q[i] += 10
	check(RankEstimate.estimate(10, 100, q).text == "Estimate: about top 100% · ~100 of 101", "minimum equality cannot be behind all existing scores")
	check(RankEstimate.estimate(9, 100, q).text == "Estimate: about top 100% · ~101 of 101", "strictly below the minimum must be behind all existing scores")
	for i in range(5):
		q[i] = 10
	check(RankEstimate.estimate(10, 1000, q).text == "Estimate: about top 76–81% · ~752–801 of 1001", "a repeated minimum uses the last equal sample, not the first")


func test_ascending_scores_never_worsen_the_conservative_estimated_rank() -> void:
	var plateau := _linear()
	for i in range(8, 13):
		plateau[i] = 100
	var pattern := RegEx.new()
	pattern.compile("~([0-9]+)(?:–([0-9]+))? of")
	for count: int in [20, 21, 100, 103, 1000]:
		for q: Array in [_linear(), _equal(50), plateau]:
			for boundary: Variant in [null, 160]:
				if boundary != null and boundary > q[20]:
					continue
				var previous_rank := count + 1
				for points in range(0, 202):
					var estimate := RankEstimate.estimate(points, count, q, boundary)
					var match_result := pattern.search(estimate.text)
					var rank := 1
					if match_result != null:
						rank = match_result.get_string(2 if match_result.get_string(2) != "" else 1).to_int()
					else:
						check(estimate.text == "Estimate: would be in the top 20", "monotonicity must not hide an unavailable estimate")
					check(rank <= previous_rank, "ascending score %d must not worsen conservative rank %d to %d" % [points, previous_rank, rank])
					previous_rank = rank


func test_malformed_distributions_are_unavailable() -> void:
	for q: Array in [[], [1], [1, 2, 3], _equal(1) + [1]]:
		_unavailable(RankEstimate.estimate(50, 100, q))
	for bad: Variant in [null, "10", true, {}, [], INF, -INF, NAN, -1, 1.5]:
		var q := _linear()
		q[10] = bad
		_unavailable(RankEstimate.estimate(50, 100, q))
	var descending := _linear()
	descending[10] = 1
	_unavailable(RankEstimate.estimate(50, 100, descending))
	_unavailable(RankEstimate.estimate(-1, 100, _linear()))
	_unavailable(RankEstimate.estimate(50, -1, _linear()))
	for bad: Variant in ["10", false, {}, INF, -INF, NAN, -1, 1.5, 201]:
		_unavailable(RankEstimate.estimate(50, 100, _linear(), bad))


func test_json_numeric_quantiles_and_thresholds_are_accepted() -> void:
	var q: Array = JSON.parse_string(JSON.stringify(_linear()))
	var estimate := RankEstimate.estimate(100, 100, q, 160.0)
	check(estimate.text == "Estimate: about top 51% · ~51 of 101", "JSON numbers must work without caller conversions")
	check(estimate.badge == "Estimate: ~top 51%" and estimate.approximate, "a compact numeric estimate must still be labelled")


func test_percentiles_never_zero_and_numeric_ranks_stay_in_bounds() -> void:
	var pattern := RegEx.new()
	pattern.compile("top ([0-9]+)(?:–([0-9]+))?% · ~([0-9]+)(?:–([0-9]+))? of ([0-9]+)")
	for count in [20, 21, 100, 1000]:
		for q: Array in [_linear(), _equal(50)]:
			for points in range(0, 202):
				var estimate := RankEstimate.estimate(points, count, q)
				check(estimate.text.begins_with("Estimate:") and estimate.badge.begins_with("Estimate:") and estimate.approximate, "every estimate must be explicitly labelled")
				var match_result := pattern.search(estimate.text)
				if match_result == null:
					check(estimate.text == "Estimate: would be in the top 20", "an estimate must be a bounded numeric standing or a potential top twenty")
					continue
				for group in [1, 2]:
					if match_result.get_string(group) != "":
						var percentile := match_result.get_string(group).to_int()
						check(percentile >= 1 and percentile <= 100, "percentiles must be 1..100")
				for group in [3, 4]:
					if match_result.get_string(group) != "":
						var rank := match_result.get_string(group).to_int()
						check(rank >= 1 and rank <= count + 1, "rank bounds must be 1..n+1")
				check(match_result.get_string(5).to_int() == count + 1, "the denominator includes the local candidate")


func _linear() -> Array:
	return [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200]


func _equal(points: int) -> Array:
	var q: Array = []
	q.resize(21)
	q.fill(points)
	return q


func _small() -> Array:
	return [10, 10, 10, 10, 10, 10, 10, 20, 20, 20, 20, 20, 20, 20, 30, 30, 30, 30, 30, 30, 30]


func _unavailable(estimate: Dictionary) -> void:
	check(estimate == {"text": "", "badge": "", "approximate": false}, "invalid input must not look like an empty board or a zero score")


func _top_twenty(estimate: Dictionary) -> void:
	check(estimate == {"text": "Estimate: would be in the top 20", "badge": "Estimate: ~top 20", "approximate": true}, "an unverified potential top run must not claim an exact rank")
