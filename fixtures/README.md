Shared fixtures: levels, demos and `expected.json` (the errors `LevelFormat.validate` and `DemoCheck.check` report, the server-side score, and the official level hashes). The Godot tests and the community server's tests both check their implementations against them.
Generated, not hand-edited. Regenerate with `godot --headless --path . -s tools/make_fixtures.gd`, then commit the result.
