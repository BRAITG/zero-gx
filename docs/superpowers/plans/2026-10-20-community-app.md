# Community in the App, First Slice: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android players sign in with Play Games, submit a finished level, and browse, download and play approved community levels from the live server, also offline.

**Architecture:** A `Community` autoload owns every server call, the session and the download cache. It talks to the network through a small transport object and to Android through a small platform object; tests replace both with fakes. Sign-in uses the vendored `godot-play-game-services` plugin, and Play Integrity uses a new Kotlin plugin of ours. Screens only call `Community`. On desktop the platform object reports itself unavailable and every community button stays hidden.

**Tech Stack:** Godot 4.7.2, GDScript, `HTTPRequest`, Android plugin v2 (Kotlin, Gradle), `godot-play-game-services` v3.4.0, Play Integrity API (classic request), the existing Cloudflare Worker.

**Spec:** `docs/superpowers/specs/2026-10-20-community-app-design.md`

## Global Constraints

- Server: `https://zerogx.braitg.dev`, read from `community/api_url` in `project.godot`. Requests and responses are exactly as in the spec's table and `server/src/` (`GET /nonce` → `{nonce}`; `POST /session` JSON `{authCode, integrityToken, nonce}` → `{token, player: {id, name}}`; `Authorization: Bearer <token>`; `X-Nonce`, `X-Integrity` headers; `GET /levels?sort=top|new&page=N`, 50 rows a page; `GET /index` → `{commit}`; `POST /submissions` multipart `level`, `demo`, optional `level_id`; `GET /me/submissions`).
- Bound nonce: `base64url(SHA-256(nonce UTF-8 ‖ SHA-256(level bytes) ‖ SHA-256(demo bytes)))`, no padding, identical to `boundNonce` in `server/src/session.ts`.
- Downloads: `https://cdn.jsdelivr.net/gh/BRAITG/zero-gx-levels@<commit>/levels/<level_id>/v<latest>.json`; reject a file whose SHA-256 differs from the row's `sha256`; cache as `user://community/<sha256>.json`.
- Session: stored in `user://community.cfg` with its expiry (7 days). A `401` signs in again once and retries once. Every call that needs a nonce fetches a new one.
- Submitted level bytes are exactly `LevelFormat.to_json(draft)` UTF-8; demo bytes are exactly the stored demo file of `MyLevels.demo(id)`.
- Desktop (Windows, macOS, Linux) keeps everything except online features: no Community button, no Submit, no server calls. The plugins' Android libraries are never part of a desktop export. `GodotPlayGameServices.initialize()` is called only on Android.
- Errors are one sentence: the server's message, or "No connection" when offline.
- Public values (`community/google_web_client_id`, `community/cloud_project_number`, the Play Games game id) live in `project.godot` and the export preset; they start empty until `docs/release/play-games-setup.md` is done. Secrets never enter the repo.
- Tests never touch the player's data: `Community` paths are redirected in `tests/run_tests.gd` like `MyLevels.dir`.

## Review Focus

1. **A demo that no longer matches its draft** (the player edited after finishing). Submit must not be offered, because `MyLevels.demo(id)` returns null. Task 4 pins it.
2. **The session expires during a request.** One silent re-sign-in and one retry, never a loop; a second `401` shows "Sign in again.". Task 2 pins it.
3. **A nonce reused after a failed call.** The server consumes it, so the retry must fetch a fresh one. Task 2 pins it.
4. **Offline with an empty cache.** Community shows "No connection" and no rows, and it doesn't crash. Task 4 pins it.
5. **jsDelivr serving a stale or tampered file.** The hash check rejects it and nothing is cached. Task 2 pins it.

---

### Task 1: Bound nonce and multipart body

**Files:**
- Create: `scripts/community_wire.gd` (`class_name CommunityWire`, static functions only)
- Create: `fixtures/bound_nonce.json`
- Test: `tests/test_community_wire.gd`, `server/test/bound_nonce.test.ts` (or the server test folder that fits)

**Interfaces:**
- Produces:
  - `CommunityWire.base64url(bytes: PackedByteArray) -> String`: URL-safe, no padding.
  - `CommunityWire.bound_nonce(nonce: String, parts: Array[PackedByteArray]) -> String`.
  - `CommunityWire.multipart(fields: Dictionary, files: Dictionary, boundary: String) -> PackedByteArray`: `fields` name → String, `files` name → `[filename, PackedByteArray]`; CRLF line breaks; `Content-Disposition: form-data; name="…"; filename="…"` and `Content-Type: application/octet-stream` for files.

- [ ] **Step 1: Write the fixture.** `fixtures/bound_nonce.json`: `{"nonce": "<43-char base64url>", "level_base64": "<base64 of a small level file>", "demo_base64": "<base64 of fixtures' level_01 demo>", "bound": "<expected>"}`. Compute `bound` with the server's `boundNonce` once (a one-off `npx tsx` script in `server/`, not committed).
- [ ] **Step 2: Write the failing tests.** Godot: `bound_nonce(fixture.nonce, [level, demo]) == fixture.bound`; `base64url` of `[0xfb, 0xff]` is `"-_8"`; `multipart` of one field and one file parses back with `HTTPClient`-independent checks (boundary lines, headers, exact file bytes). Server: `boundNonce(fixture…)` equals `fixture.bound`.
- [ ] **Step 3: Run them.** `TEST_FILTER=test_community_wire GODOT=godot tests/run.sh` fails (no `CommunityWire`); `cd server && npx vitest run <file>` passes.
- [ ] **Step 4: Implement `CommunityWire`.** Use `HashingContext` with `HASH_SHA256` and `Marshalls.raw_to_base64`, then swap characters and strip `=`.
- [ ] **Step 5: Run the tests.** Both pass; then the full suite.
- [ ] **Step 6: Commit.** `feat(community): bound nonce and multipart body, checked against the server`.

---

### Task 2: The `Community` client

**Files:**
- Create: `scripts/community.gd` (autoload `Community`, registered in `project.godot` after `Settings`)
- Create: `scripts/community_transport.gd` (`class_name CommunityTransport`, the real `HTTPRequest` transport)
- Create: `scripts/community_platform.gd` (`class_name CommunityPlatform`, base class: unavailable; the Android subclass comes in Task 3)
- Modify: `tests/run_tests.gd` (redirect `Community` paths and reset it per test)
- Test: `tests/test_community.gd`, with fakes in `tests/support/fake_transport.gd` and `tests/support/fake_platform.gd`

**Interfaces:**
- Consumes: `CommunityWire` (Task 1), `MyLevels.demo(id)` (non-null only while the stored demo matches the draft), `MyLevels.load_level(id)`, `LevelFormat.to_json`, `LevelFormat.sha256`. The demo bytes to upload are the stored file `FileAccess.get_file_as_bytes(MyLevels._demo_path(id))`; make `_demo_path` public as `demo_path` and update its callers.
- Produces:
  - `CommunityTransport.send(method: String, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary`, a coroutine returning `{"status": int, "body": PackedByteArray}`, where status `0` means no connection.
  - `CommunityPlatform.available() -> bool`; `sign_in() -> Dictionary` (coroutine: `{"auth_code": String}` or `{"error": String}`); `integrity(nonce: String) -> Dictionary` (`{"token": String}` or `{"error": String}`).
  - `Community`: `var transport: CommunityTransport`, `var platform: CommunityPlatform`, `var dir := "user://community/"`, `var session_path := "user://community.cfg"`.
  - `Community.available() -> bool` (platform available).
  - `Community.signed_in() -> bool` (stored token not expired).
  - `Community.sign_in() -> String` (coroutine; `""` on success, else the error sentence).
  - `Community.list(sort: String, page: int) -> Dictionary` (`{"rows": Array}` or `{"error": String, "rows": <cached rows or []>, "offline": bool}`).
  - `Community.level_path(sha256: String) -> String`.
  - `Community.download(row: Dictionary) -> String` (`""` when the file is cached and verified).
  - `Community.can_submit(id: String) -> bool`, `Community.submit(id: String) -> String`, `Community.statuses() -> Dictionary` (level_id → `{status, version, comment}`; the last known statuses are kept in `session_path`).
  - `Community.level_id_of(id: String) -> String` (from `MyLevels`' `index.cfg`, key `level_id`; `""` if never submitted).
  - `Community.delete_account() -> String` (coroutine: `DELETE /me`; on success clears the stored session, statuses and `level_id`s, returns `""`; else the error sentence). Required by `PRIVACY.md` ("delete your community account at any time in the game, from the community screen") and Google Play's account-deletion policy.

- [ ] **Step 1: Write the fakes.** `FakeTransport` answers from a queue of `{method, path_prefix, status, body}` and records every request (method, url, headers, body). `FakePlatform` returns `{"auth_code": "test:p1:Pilot"}` and `{"token": "ok:" + nonce}`, with switches to fail either.
- [ ] **Step 2: Write the failing tests** in `tests/test_community.gd`:
  - Sign-in: `GET /nonce` then `POST /session` with the nonce, `test:p1:Pilot` and `ok:<nonce>`; the token is stored with its expiry, and `signed_in()` is true after reloading `Community`.
  - A `401` on `GET /levels` re-signs in once (fresh nonce) and retries once; a second `401` returns "Sign in again." without a third request.
  - Offline (status 0) list with cached rows returns them with `offline` true; with no cache returns `rows` empty and "No connection".
  - Download: the URL is built from `GET /index`'s commit, the row's `level_id` and `latest`; a body whose SHA-256 differs from `row.sha256` is rejected and not cached; a matching one is cached at `level_path(sha256)` and a second download makes no request.
  - Submit: the multipart body carries exactly the draft's `to_json` bytes and the demo file bytes; `X-Integrity` is `ok:` + `bound_nonce(nonce, [level, demo])`; the returned `level_id` is stored and sent on the next submit; a server error text (for example 429) comes back as the result sentence; a failed submit fetches a new nonce on the next try.
  - `can_submit` is false for a draft without a matching demo, and false when `available()` is false.
  - `statuses()` maps `GET /me/submissions` rows and falls back to the last known ones offline.
  - `delete_account()` sends `DELETE /me` with the session, then `signed_in()` is false and `statuses()` is empty; a failure keeps the session and returns the server's sentence.
- [ ] **Step 3: Run them.** `TEST_FILTER=test_community` fails (no `Community`).
- [ ] **Step 4: Implement.** `CommunityTransport` uses one `HTTPRequest` child per call with `request_raw`, awaiting `request_completed`. Use `ConfigFile` for `session_path`. Every public coroutine returns the shapes above; no UI.
- [ ] **Step 5: Run the tests.** All pass; then the full suite, which must stay clean on desktop (the base platform is unavailable, so `Community` makes no calls).
- [ ] **Step 6: Commit.** `feat(community): client for sign-in, levels, downloads and submissions`.

---

### Task 3: Android plumbing

**Files:**
- Add: `addons/GodotPlayGameServices/` (the v3.4.0 release `addons.zip`, unchanged; licence MIT, credited in `scenes/credits.gd` or the credits data the game uses)
- Create: `android/plugins/integrity/` (Gradle library module: `build.gradle`, `src/main/java/dev/braitg/zerogx/integrity/IntegrityPlugin.kt`, `AndroidManifest.xml`)
- Create: `addons/zero_gx_integrity/` (`plugin.cfg`, `export_plugin.gd`, `bin/zero_gx_integrity-release.aar`, `bin/zero_gx_integrity-debug.aar`)
- Create: `scripts/community_android.gd` (`class_name CommunityAndroid extends CommunityPlatform`)
- Modify: `project.godot` (enabled editor plugins, the `GodotPlayGameServices` autoload the plugin registers, `community/api_url`, `community/google_web_client_id`, `community/cloud_project_number`)
- Modify: `export_presets.cfg` (both Android presets: `gradle_build/use_gradle_build=true`, the plugin's `godot_play_game_services/game_id` option; desktop presets untouched)
- Modify: `.github/workflows/build.yml` (debug APK export adds `--install-android-build-template`)
- Modify: `scripts/community.gd` (pick `CommunityAndroid` when `OS.has_feature("android")`)
- Test: `tests/test_community_android.gd` (headless: the Android platform reports unavailable without the singletons; desktop exports contain no AAR)

**Interfaces:**
- Consumes: `PlayGamesSignInClient` (`sign_in()`, `user_authenticated(is_authenticated: bool)`, `request_server_side_access(server_client_id: String, force_refresh_token: bool)`, `server_side_access_requested(token: String)`), `GodotPlayGameServices.initialize()`.
- Produces: the Kotlin plugin singleton `ZeroGxIntegrity` with `request(nonce: String, cloudProjectNumber: Long)` and signals `integrity_token(token: String)`, `integrity_failed(message: String)`. `CommunityAndroid` implements Task 2's `CommunityPlatform` contract on top of both plugins.

- [ ] **Step 1: Vendor the sign-in plugin.** Unzip v3.4.0 `addons.zip` into `addons/`, enable it, and commit the autoload it registers. Confirm a headless desktop run shows no new errors: the autoload loads, and `initialize()` is not called on desktop.
- [ ] **Step 2: Write the Integrity plugin.** A Godot Android plugin v2: `class IntegrityPlugin(godot: Godot) : GodotPlugin(godot)`, `getPluginName() = "ZeroGxIntegrity"`, `@UsedByGodot fun request(nonce: String, cloudProjectNumber: Long)` calling `IntegrityManagerFactory.create(activity).requestIntegrityToken(IntegrityTokenRequest.builder().setNonce(nonce).setCloudProjectNumber(cloudProjectNumber).build())` and emitting one of the two signals. Dependencies: `compileOnly "org.godotengine:godot:4.7.2.stable"`, `implementation "com.google.android.play:integrity:1.4.0"`. Its `export_plugin.gd` mirrors the Play Games plugin's (Android only, AAR plus the Maven dependency).
- [ ] **Step 3: Build the AARs.** Run `./gradlew :integrity:assembleRelease :integrity:assembleDebug` with JDK 17 (Gradle does not run on the local JDK 27; use `/usr/libexec/java_home -v 17`, or install `temurin@17` if it is missing). Copy both AARs into `addons/zero_gx_integrity/bin/`.
- [ ] **Step 4: Switch the debug preset to Gradle** and add `--install-android-build-template` to its CI export. Export both Android presets locally and run `aapt dump badging` / `unzip -l` to check both AARs' classes and the `com.google.android.gms.games.APP_ID` meta-data are in the APK. Export the macOS preset and check it contains no AAR.
- [ ] **Step 5: Write `CommunityAndroid`.** `available()` is true when both singletons exist. `sign_in()` signs in, then requests server-side access with `community/google_web_client_id`, and returns the auth code or the reason ("Play Games sign-in was cancelled"). `integrity(nonce)` calls `ZeroGxIntegrity.request` with `community/cloud_project_number`.
- [ ] **Step 6: Run the tests.** The full suite passes; a headless test checks that `CommunityAndroid.available()` is false without the singletons.
- [ ] **Step 7: Commit.** `feat(android): Play Games sign-in and Play Integrity plugins`.

---

### Task 4: Screens

**Files:**
- Create: `scenes/community_screen.gd` (`class_name CommunityScreen extends Control`)
- Modify: `scenes/main.gd` (a Community button beside My levels, only when `Community.available()`)
- Modify: `scenes/my_levels_screen.gd` (Submit button and status line per row)
- Modify: `scripts/progress.gd` (`build` accepts `community_<sha256>` ids, read from `Community.level_path`)
- Modify: `README.md` (one short paragraph on community features and that they are Android-only)
- Test: `tests/test_community_screens.gd`

**Interfaces:**
- Consumes: every `Community` function from Task 2; `Progress.open(id)`; `Overlay.open`; `Style.focus_first`; the screens' existing `_button` helpers.
- Produces: `CommunityScreen.new()`; community stage ids `"community_" + sha256`.

- [ ] **Step 1: Write the failing tests**, with `Community.platform` set to an available `FakePlatform` and a `FakeTransport`:
  - The main menu shows a Community button only when `Community.available()`; with the default (desktop) platform it is absent.
  - Community lists Top rows (title, `vN`, author, likes); New switches the sort; More asks for page 1; offline with no cache shows "No connection" and no rows.
  - Play on a row downloads, then opens `community_<sha256>`, which builds from the cached file; a rejected download shows the spec's sentence and opens nothing.
  - My levels: Submit shows only for a completed draft with a matching demo; after a submit the row shows "Pending"; `statuses()` rows map to "Pending", "Approved vN" and "Rejected: <comment>"; without an available platform neither Submit nor statuses show.
  - Community has a **Delete my community account** button (shown only when signed in) that opens a confirmation `Overlay` ("This removes your scores, likes, reports and your name from Zero-GX's servers. Levels you shared stay, shown as by Deleted player."); confirming calls `delete_account()` and returns to the main menu; cancelling sends nothing.
- [ ] **Step 2: Run them.** `TEST_FILTER=test_community_screens` fails.
- [ ] **Step 3: Implement the screens.** Follow `my_levels_screen.gd`'s layout, buttons and focus conventions. Sign-in happens on the first tap of Community, or on Submit when signed out, with the error shown in an `Overlay`.
- [ ] **Step 4: Run the tests.** They pass; then the full suite.
- [ ] **Step 5: Smoke on desktop.** In `.worktrees/play`, imported, launch the game: no Community button, no Submit, My levels unchanged, and no new errors in the log.
- [ ] **Step 6: Commit.** `feat(community): Community screen, Submit and submission status`.

---

### Task 5: Device proof (the author)

Needs `docs/release/play-games-setup.md` done and the three public values filled in `project.godot` and the preset (one commit: `chore(community): Play Games and Cloud project ids`). Community exists only in the Play build (custom feature `community` on the `Android Play` preset), and only a Play install is recognised by Play Integrity: a sideloaded debug APK gets `UNRECOGNIZED_VERSION`, and the server requires `PLAY_RECOGNIZED` (`server/src/verify.ts`). So the proof runs on the internal-testing install, not on a sideloaded APK.

- [ ] **Step 1:** Upload the CI bundle to internal testing (the build workflow does it with `PLAY_SERVICE_ACCOUNT`) and install it from the Play Store on a phone registered as a tester. Sign in from Community.
- [ ] **Step 2:** Submit a completed draft; check the pull request in `BRAITG/zero-gx-levels` and merge it.
- [ ] **Step 3:** Within about 10 minutes the level appears under New. Play it.
- [ ] **Step 4:** Turn networking off and play it again from Community.
