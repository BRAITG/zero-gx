extends "res://tests/test_case.gd"
## The shared fixtures (tools/make_fixtures.gd) hold the contract the community server's TypeScript port is tested against.

const DIR := "res://fixtures/"


## Each expected substring appears in some error, and every error contains one: nothing unlisted.
func mismatch(errors: PackedStringArray, expected: Array) -> String:
	for word: String in expected:
		if not Array(errors).any(func(e: String) -> bool: return word in e):
			return "missing \"%s\" in %s" % [word, errors]
	for error in errors:
		if not expected.any(func(word: String) -> bool: return word in error):
			return "unexpected \"%s\"" % error
	return ""


func test_fixtures_match_their_expectations() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "expected.json"))
	check(expected.levels.size() > 0 and expected.demos.size() > 0, "expected.json lists no fixtures")
	for file: String in expected.levels:
		var problem := mismatch(LevelFormat.validate(LevelFormat.read(DIR + "levels/" + file)), expected.levels[file])
		check(problem == "", "%s: %s" % [file, problem])
	for file: String in expected.demos:
		var entry: Dictionary = expected.demos[file]
		var level := LevelFormat.read(DIR + "levels/" + entry.level)
		var demo := Demo.load_file(DIR + "demos/" + file)
		check(demo != null, "%s does not decode" % file)
		if demo == null:
			continue
		var problem := mismatch(DemoCheck.check(level, demo), entry.errors)
		check(problem == "", "%s: %s" % [file, problem])
		if entry.points != null:
			check(DemoCheck.score(level, demo).points == int(entry.points), "%s: scored %d, expected %s" % [file, DemoCheck.score(level, demo).points, entry.points])
	for id in Progress.levels():
		check(expected.official_hashes.get(id) == LevelFormat.sha256(LevelFormat.read(Progress.LEVELS_DIR + id + LevelFormat.EXTENSION)), "%s: official hash is stale" % id)
