class_name RankEstimate
extends RefCounted
## Unverified local standing from the full population's ascending 0,5,…,100% quantiles.


static func estimate(points: int, count: int, quantiles: Array, top20_lowest: Variant = null) -> Dictionary:
	var unavailable := {"text": "", "badge": "", "approximate": false}
	if points < 0 or count < 0 or count == 9223372036854775807:
		return unavailable
	if count == 0:
		return {"text": "No ranked runs yet", "badge": "", "approximate": false} if quantiles.is_empty() and top20_lowest == null else unavailable
	if quantiles.size() != 21:
		return unavailable
	for i in quantiles.size():
		if not _valid_points(quantiles[i]) or (i > 0 and quantiles[i] < quantiles[i - 1]):
			return unavailable
	if top20_lowest != null and (not _valid_points(top20_lowest) or top20_lowest < quantiles[0] or top20_lowest > quantiles[20]):
		return unavailable
	if count < 20 or (top20_lowest != null and points >= top20_lowest) or points > quantiles[20] or (points == quantiles[20] and quantiles[19] < quantiles[20]):
		return {"text": "Estimate: would be in the top 20", "badge": "Estimate: ~top 20", "approximate": true}

	var low_fraction := 1.0
	var high_fraction := 1.0
	for i in quantiles.size():
		if points == quantiles[i]:
			var last := i
			while last < 20 and quantiles[last + 1] == points:
				last += 1
			if last > i:
				# Ties may extend into both unsampled neighbouring buckets; do not invent their size.
				low_fraction = (20 - mini(20, last + 1)) / 20.0
				high_fraction = (20 - maxi(0, i - 1)) / 20.0
			else:
				low_fraction = (20 - i) / 20.0
				high_fraction = low_fraction
			break
		if points < quantiles[i]:
			if i > 0:
				var between := float(points - quantiles[i - 1]) / float(quantiles[i] - quantiles[i - 1])
				low_fraction = (20 - (i - 1) - between) / 20.0
				high_fraction = low_fraction
			break

	var population := count + 1
	var floor_rank := 21 if count >= 20 and top20_lowest != null and points < top20_lowest else 1
	var low_rank := clampi(roundi(low_fraction * count) + 1, floor_rank, population)
	var high_rank := clampi(roundi(high_fraction * count) + 1, floor_rank, population)
	var low_percent := clampi(ceili(100.0 * low_rank / population), 1, 100)
	var high_percent := clampi(ceili(100.0 * high_rank / population), 1, 100)
	var percent := str(low_percent) if low_percent == high_percent else "%d–%d" % [low_percent, high_percent]
	var rank := str(low_rank) if low_rank == high_rank else "%d–%d" % [low_rank, high_rank]
	return {
		"text": "Estimate: about top %s%% · ~%s of %d" % [percent, rank, population],
		"badge": "Estimate: ~top %s%%" % percent,
		"approximate": true,
	}


static func _valid_points(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(value)
