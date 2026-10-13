# Zero-GX

A 2D zero-gravity physics game for Android, built with Godot 4.7. Fly a ship from point A to point B through courses built from energy barriers, using planets, black holes and stars as gravity wells, with limited fuel and hull. This is a prototype for judging whether the mechanics are fun. The design is in [`docs/superpowers/specs/2026-10-12-zero-gx-prototype-design.md`](docs/superpowers/specs/2026-10-12-zero-gx-prototype-design.md).

## Play on Android

Every push to `master` publishes a debug-signed APK as a prerelease on the [Releases page](https://github.com/BRAITG/zero-gx/releases). Open the latest one on the phone, download `zero-gx.apk`, allow installs from the browser, and open the file. Builds share one signing key, so a newer APK installs over an older one.

Controls: touch and hold anywhere. The ship turns toward your finger and thrusts while you hold; release to coast.

## Play or edit on a computer

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/).
2. Open `project.godot`.
3. Press F5. The mouse stands in for a finger.

Levels live in `levels/` and are edited in the Godot editor: drag a barrier's `Shape` points to reshape a wall, and drop in `scenes/gravity_body.tscn` or `scenes/asteroid.tscn` instances.

## Tests

```sh
tests/run.sh   # needs `godot` on PATH, or GODOT=/path/to/godot
```

The suite runs headless at a fixed 60 FPS. `tests/test_levels.gd` checks the level-design rules: every level is well formed, and with no player input no asteroid ever hits a planet within 60 seconds.

## Build pipeline

`.github/workflows/build.yml` runs the tests, exports the APK, and uploads it as a workflow artifact on every pull request. On `master`, and on a manual run with `publish` checked, it also publishes a prerelease. The debug keystore is the `ANDROID_DEBUG_KEYSTORE_B64` repository secret.

## Tuning

Gameplay numbers are named constants:

| File | What it tunes |
|---|---|
| `scenes/ship.gd` | fuel, burn rate, thrust, turn rate, hull, impact damage, speed cap |
| `scenes/barrier.gd` | damage multiplier per colour, bounce, collision thickness |
| `scenes/gravity_body.gd` | planet / black hole / star size, pull and reach; shatter behaviour |
| `scenes/asteroid.gd` | size, mass, damage dealt to planets |
