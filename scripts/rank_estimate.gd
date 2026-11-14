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
	if count < 20 or (top20_lowest != null and points >= top20_lowest) or points >= quantiles[20]:
		return {"text": "Estimate: would be in the top 20", "badge": "Estimate: ~top 20", "approximate": true}

	var low_rank := count + 1
	var high_rank := count + 1
	for i in quantiles.size():
		if points == quantiles[i]:
			var last := i
			while last < 20 and quantiles[last + 1] == points:
				last += 1
			high_rank = count - _sample_position(last, count) + 1
			# Only the unsampled bucket after the last equal score can change the strictly higher count.
			low_rank = count - _sample_position(last + 1, count) + 2 if last > i else high_rank
			break
		if points < quantiles[i]:
			if i > 0:
				var between := float(points - quantiles[i - 1]) / float(quantiles[i] - quantiles[i - 1])
				var before := count - _sample_position(i - 1, count) + 1
				var after := count - _sample_position(i, count) + 1
				low_rank = roundi(lerpf(before, after, between))
				high_rank = low_rank
			break

	var population := count + 1
	var floor_rank := 21 if count >= 20 and top20_lowest != null and points < top20_lowest else 1
	low_rank = clampi(low_rank, floor_rank, population)
	high_rank = clampi(high_rank, floor_rank, population)
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


## One-based nearest-rank position; both 0% and the first sample can point to the minimum.
static func _sample_position(index: int, count: int) -> int:
	return maxi(1, ceili(float(index) * count / 20.0))
