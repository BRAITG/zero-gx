<p align="center">
  <img src="store/icon-512.png" alt="Zero-GX icon" width="160">
</p>

<h1 align="center">Zero-GX</h1>

<p align="center">
  <strong>No friction. No brakes. Just you, your fuel, and gravity.</strong>
</p>

<p align="center">
  <a href="https://github.com/BRAITG/zero-gx/releases"><img alt="Latest build" src="https://img.shields.io/github/v/release/BRAITG/zero-gx?include_prereleases&label=latest%20build"></a>
  <a href="https://github.com/BRAITG/zero-gx/actions/workflows/build.yml"><img alt="Build" src="https://github.com/BRAITG/zero-gx/actions/workflows/build.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: AGPL-3.0-or-later" src="https://img.shields.io/badge/license-AGPL--3.0--or--later-blue"></a>
  <img alt="Godot 4.7" src="https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/platform-Android-3ddc84?logo=android&logoColor=white">
</p>

Zero-GX is a 2D physics game for Android, built with Godot. Fly a ship from start to goal through courses of energy barriers, using planets, black holes and stars as gravity wells, with limited fuel and hull. Nothing slows you down: every push you make, you have to undo. The original design is in [`docs/superpowers/specs/2026-10-12-zero-gx-prototype-design.md`](docs/superpowers/specs/2026-10-12-zero-gx-prototype-design.md).

<p align="center">
  <img src="store/screenshots/1-level_05.png" alt="Slingshot around a planet" width="49%">
  <img src="store/screenshots/2-level_09.png" alt="Skirting a black hole" width="49%">
  <img src="store/screenshots/3-level_10.png" alt="Fighting a star's pull" width="49%">
  <img src="store/screenshots/4-level_08.png" alt="An asteroid field" width="49%">
</p>

## Features

- **Real momentum.** One finger turns and thrusts; let go and you coast forever.
- **Gravity as a tool.** Swing around planets, keep clear of black holes, cross the pull of stars.
- **Twelve levels, plus seven training stages**, scored on fuel left, hull left and time.
- **A level editor in the app.** Build, test and replay your own courses.
- **Free software.** AGPL-3.0-or-later, with only free assets.

## Play on Android

Every push to `master` publishes a debug-signed APK as a prerelease on the [Releases page](https://github.com/BRAITG/zero-gx/releases). Open the latest one on the phone, download `zero-gx.apk`, allow installs from the browser, and open the file. Builds share one signing key, so a newer APK installs over an older one.

Controls: touch and hold anywhere. The ship turns toward your finger and thrusts while you hold; release to coast.

## Play or edit on a computer

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/).
2. Open `project.godot`.
3. Press F5. The mouse stands in for a finger.

Levels live in `levels/` as level files (see [Level files](#level-files)). Build your own in the app: **My levels** in the main menu opens the level editor (`scenes/editor.gd`). Pick a tool from the bottom palette (walls, planets, black holes, stars, asteroids, pickups, start and goal); one finger places or drags, two fingers pan and pinch-zoom. Walls, the start and the goal snap to a 1 m grid; turn on **10 m grid** for 10 m steps. Everything else goes exactly where you put it, and pressing on something already placed picks it up instead of adding another. **Select** then tap opens a thing's sheet, with sliders kept within its kind's limits; **Settings** sets the title, hint, fuel, hull and velocity arrow. **Test** flies the level: finishing it marks the level completed until its next change, and returning keeps your undo history. Your levels are saved on the device in `user://levels/` (`scripts/my_levels.gd`); the editor's model with undo is `scripts/level_doc.gd`.

## Tests

```sh
tests/run.sh   # needs `godot` on PATH, or GODOT=/path/to/godot
```

The suite runs headless at a fixed 60 FPS. `tests/test_levels.gd` checks the level-design rules: every level is well formed, and with no player input no asteroid ever hits a planet within 60 seconds.

## Build pipeline

`.github/workflows/build.yml` runs the tests, exports the APK and the desktop builds (Windows, macOS, Linux), and uploads them as a workflow artifact on every pull request. On `master`, and on a manual run with `publish` checked, it also publishes a prerelease with all of them. The desktop builds are unsigned: on macOS, right-click the app and choose Open; on Windows, SmartScreen warns, so choose More info → Run anyway. The debug keystore is the `ANDROID_DEBUG_KEYSTORE_B64` repository secret.

## Community server

Players share levels and compete on boards through a Cloudflare Worker with a D1 database and R2 storage, under [`server/`](server/). Setup, routes and the operations runbook are in [`server/README.md`](server/README.md). Submitted levels live in a separate public repository, `BRAITG/zero-gx-levels`, created from the template in [`levels-repo/`](levels-repo/). The design is in [`docs/superpowers/specs/2026-10-16-community-design.md`](docs/superpowers/specs/2026-10-16-community-design.md).

## Tutorials

Seven guided stages (`tutorials/`, under **Training** in the main menu) teach one idea each: no friction, walls, fuel, orange and red walls, gravity, black holes, and stars. Each is a script of steps built on `scenes/tutorial.gd`. A white arrow from the ship shows its velocity in the tutorials; players can turn it on for levels in **Settings** (`scripts/settings.gd`, saved in `user://settings.cfg`). Distances and speeds are shown in metres: 10 px is 1 m.

## Level files

Official levels and tutorials are plain JSON (`levels/level_NN.json`, `tutorials/tutorial_N.json`) in a stable layout (sorted keys, 2-space indent, trailing newline), so the SHA-256 of a level's file identifies one version of it. Player drafts are gzip-compressed (`user://levels/<id>.json.gz`). The format is described in `docs/superpowers/specs/2026-10-16-level-format-design.md`; `scripts/level_format.gd` reads, writes, validates and builds them. Tutorials pair their file with a lesson script (`tutorials/tutorial_N.gd`). Fuel and hull are per-level values and either can be unlimited. The in-app editor saves this format, and community levels and the server will use it too.

## Demos

Every run of an official level or a draft is recorded as a demo (tutorials are not recorded): the ship and asteroids 30 times a second, plus events such as pickups taken, planets shattered, asteroids spawned or removed, the score clock starting, the goal reached and the ship lost. Recording begins with the first physics tick, before the first thrust. A demo is gzip-compressed and capped at 512 KB and 10 minutes. `scenes/demo_recorder.gd` records it. `scripts/demo_check.gd` (`DemoCheck`) checks it against its level: the level's hash, start and goal, speed, walls, red walls, stars and black holes, fuel, and the claimed points, time, fuel and hull. `scenes/demo_viewer.gd` replays a demo without physics, with pause, 0.5x, 1x and 2x speeds and a timeline. The end panel's **Replay** opens the viewer. In **My levels**, **Watch** appears for a draft whose last finished test run still matches its current content. The best run of each official level is kept in `user://demos/`.

## Scoring and progress

A won stage scores `1000 + fuel left × 15 + hull left × 3 − seconds × 2` points (at least 100). The clock starts at the first thrust. The weights are sliders in the Tune panel. Finishing a stage unlocks the next one, tutorials first. Best points are saved in `user://progress.cfg` (`scripts/progress.gd`). The Tune panel can unlock every stage for the session and reset saved progress.

## Tuning

The values you will most often want to change (speed cap, thrust, turn rates, pickup strength and duration, boost, impact spin, planet and black hole pull, points weights) live in `scripts/tuning.gd`. Sound volume is in **Settings** (saved with the other settings). Change the tuning values live on the phone with the **Tune** button in the main menu or the level HUD; the changes last until the app closes. Fixed numbers are named constants:

| File | What it tunes |
|---|---|
| `scripts/tuning.gd` | defaults and slider ranges of the live tuning values |
| `scenes/ship.gd` | fuel, burn rate, hull, impact damage, hard speed limit, slowdown above the cap, camera lookahead and shake, trail, engine volume |
| `scenes/barrier.gd` | damage multiplier per colour, bounce, collision thickness; laser colour, width, glow and pulse |
| `scenes/gravity_body.gd` | planet / black hole / star size, pull, reach and colours; shatter behaviour |
| `scenes/asteroid.gd` | size, mass, damage dealt to planets |
| `scenes/pickup.gd` | pickup size and colours |
| `scripts/sfx.gd` | which sound plays for what, and the synthesized ambient drone |
| `scripts/style.gd` | UI theme (fonts, panels, buttons) and the 2D bloom |
| `scenes/starfield.gd` | parallax star layers and nebulae |

## Assets

Fonts (Orbitron, Exo 2; SIL Open Font License) and sound effects (Kenney, CC0) live in `assets/`. Sources and licenses: `assets/LICENSES.md`. The app icon (`assets/icon*.svg`, with Android adaptive foreground and background layers) is original. Everything else is drawn in code. The in-game **Credits** screen (`scenes/credits.gd`) shows every attribution and license text the shipped game must carry, including Godot's; add new third-party assets there and in `assets/LICENSES.md`.

## License

Zero-GX is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See `LICENSE`. `LICENSE-EXCEPTION` adds one permission under section 7 of that license: the game may be linked with Google Play's client libraries (Play Games Services sign-in and Play Integrity), which are not free software.

The bundled fonts and sound effects keep their own licenses (SIL Open Font License 1.1 and CC0 1.0); see `assets/LICENSES.md`. Godot Engine is MIT-licensed.
