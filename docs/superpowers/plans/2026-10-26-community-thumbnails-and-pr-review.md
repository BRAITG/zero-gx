# Community Thumbnails and PR Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Community levels get a bird's-eye thumbnail drawn from a sketch derived in GitHub Actions, and a submission PR gets a rendered image and a browser player link in a comment.

**Architecture:** The game owns sketch derivation (`LevelFormat.sketch`) and drawing (`Thumbnail.of_sketch`); a `pull_request` job in `zero-gx-levels` derives the sketch and renders the level with the Godot editor binary; a trusted `workflow_run` job commits the sketch to the PR branch, the image to a `previews` branch, and posts one comment. The Worker stores the sketch at merge and returns it in `GET /levels`. A Web export of a viewer-only scene on `zero-gx` GitHub Pages plays a proof run from raw URLs at a commit SHA.

**Tech Stack:** Godot 4.7.2 (GDScript), Cloudflare Worker (TypeScript, D1, vitest), GitHub Actions (`xvfb-run`, `actions/github-script`), Godot Web export without threads.

**Spec:** `docs/superpowers/specs/2026-10-26-community-thumbnails-and-pr-review-design.md`

## Global Constraints

- Sketch under 2048 bytes, one line, sorted keys, no spaces, integer numbers; identical bytes for identical levels.
- The Worker computes nothing: it fetches `levels/<id>/v<N>.sketch.json` at merge and stores it.
- `pull_request` jobs hold no secrets and no write token; `workflow_run` jobs never check out or run PR code.
- Viewer accepts only `https://raw.githubusercontent.com/BRAITG/zero-gx-levels/<40 hex>/...` URLs.
- Existing gates (validation, approval, difficulty label) unchanged. Existing tests stay green: `tests/run.sh`, `cd server && npm test && npm run typecheck`.
- Tool scripts follow `tools/render_thumbnails.gd`: `extends SceneTree`, `_initialize` → `_run.call_deferred()`, `load()` game scripts inside `_run` (autoloads are not compiled yet when a `-s` script is parsed).
- Public text (docs, comments, PR comment copy) in normal professional English.

## Review Focus

1. A level with 150 asteroids and 300 walls must still sketch under 2 KB (Task 1 test `test_sketch_of_a_maximal_level_fits`).
2. A sketch with missing or malformed keys (`{}`, `{"bounds": "x"}`, `null` from the server) must draw the background and never raise (Task 3 test `test_sketch_thumbnail_survives_bad_input`).
3. A PR that carries a sketch whose bytes differ from the derived one must fail the `preview` job (Task 6, step 5 verifies by editing the file in a test PR).
4. A second run on the same head SHA (after the sketch commit) must not post a second comment or a second image (Task 7 verification on the test PR: one comment, one file).
5. The viewer must refuse a demo whose level hash does not match the fetched level (Task 8 test `test_viewer_refuses_a_demo_of_another_level`).

---

### Task 1: `LevelFormat.sketch`

**Files:**
- Modify: `scripts/level_format.gd` (add after `serialize`, ~l.358)
- Test: `tests/test_level_format.gd`

**Interfaces:**
- Produces: `static func sketch(data: Dictionary) -> Dictionary` and `static func sketch_json(sketch: Dictionary) -> String` (one line, `JSON.stringify(sketch, "", true)`, no trailing newline). Sketch keys exactly as the spec: `bounds` `[x, y, w, h]`, `ship` `[x, y]`, `goal` `[x, y]`, `walls` `[{kind, points, closed?}]`, `bodies` `[{kind, position, radius}]`, `pickups` `[{kind, position}]`, `asteroids` `[[x, y], ...]`. All numbers `int`.
- Consumes: `body_value(body, "radius")`, `Ship.RADIUS`, `_vec`.

- [ ] **Step 1: Write the failing tests** in `tests/test_level_format.gd`

```gdscript
func test_sketch_keeps_shape_and_is_stable() -> void:
	var data := LevelFormat.read(Progress.LEVELS_DIR + "level_08.json")
	var sketch := LevelFormat.sketch(data)
	check(sketch.walls.size() == data.walls.size() and sketch.bodies.size() == data.get("bodies", []).size(), "every wall and body survives: %s" % [sketch])
	check(sketch.walls[0].kind == data.walls[0].kind, "wall kinds survive")
	var bounds: Array = sketch.bounds
	for wall in data.walls:
		for p in wall.points:
			check(p[0] >= bounds[0] and p[0] <= bounds[0] + bounds[2] and p[1] >= bounds[1] and p[1] <= bounds[1] + bounds[3], "bounds enclose %s" % [p])
	var text := LevelFormat.sketch_json(sketch)
	check(text == LevelFormat.sketch_json(LevelFormat.sketch(data)), "same level, same bytes")
	check(text.length() < 2048 and not text.contains("\n") and not text.contains(" "), "one compact line under 2 KB: %d" % text.length())
	check(text.find("\"asteroids\"") < text.find("\"bodies\""), "keys sorted")


func test_sketch_of_a_maximal_level_fits() -> void:
	var data := minimal()
	data.walls = []
	for w in LevelFormat.MAX_WALLS:
		var points := []
		for i in LevelFormat.MAX_WALL_POINTS:
			points.append([w * 50 + i * 7 + (i % 3) * 20, (i * 13) % 300])
		data.walls.append({"kind": "blue", "points": points})
	data.asteroids = []
	for i in LevelFormat.MAX_ASTEROIDS:
		data.asteroids.append({"position": [i * 31, (i * 17) % 500]})
	check(LevelFormat.sketch_json(LevelFormat.sketch(data)).length() < 2048, "maximal level must fit")
```

- [ ] **Step 2: Run** `TEST_FILTER=test_level_format.gd::test_sketch tests/run.sh` — expected: FAIL, `sketch` not found.

- [ ] **Step 3: Implement** in `scripts/level_format.gd`:
  - `static func sketch(data: Dictionary) -> Dictionary`: collect bounds over ship, goal, wall points, body centres ± radius, pickups, asteroid positions, grown by `Ship.RADIUS`; simplify each wall with Ramer–Douglas–Peucker (`static func _simplify(points: PackedVector2Array, tolerance: float) -> PackedVector2Array`, keeps first and last; closed walls keep their `closed` flag) starting at `maxf(w, h) / 320.0`; loop: build the dictionary, measure `sketch_json(...).length()`, double the tolerance up to 8 times, then pop asteroids from the end until under 2048.
  - `static func sketch_json(sketch: Dictionary) -> String: return JSON.stringify(sketch, "", true)`.
  - Round with `roundi`; omit `closed` when false.

- [ ] **Step 4: Run** the filter again — expected: PASS. Then `tests/run.sh` — expected: `0 failed`.

- [ ] **Step 5: Commit** `feat(level): derive a thumbnail sketch from a level`.

---

### Task 2: `tools/sketch_level.gd`

**Files:**
- Create: `tools/sketch_level.gd`

**Interfaces:**
- Produces: `godot --headless --path . -s res://tools/sketch_level.gd -- <level.json> <out.json>`; exit 0 and writes `sketch_json` to `<out.json>`; exit 1 with a `push_error` on an unreadable or invalid level (use `LevelFormat.validate`). Arguments via `OS.get_cmdline_user_args()`.

- [ ] **Step 1: Implement** following the `render_thumbnails.gd` conventions (`load("res://scripts/level_format.gd")` inside `_run`).

- [ ] **Step 2: Verify**: `godot --headless --path . -s res://tools/sketch_level.gd -- levels/level_05.json /tmp/s.json && wc -c /tmp/s.json && head -c 200 /tmp/s.json` — expected: exit 0, size < 2048, starts with `{"asteroids":`.
  Then `godot --headless --path . -s res://tools/sketch_level.gd -- fixtures/levels/invalid.wall_kind.json /tmp/bad.json; echo $?` — expected: `1`.

- [ ] **Step 3: Commit** `feat(tools): sketch_level command`.

---

### Task 3: `Thumbnail.of_sketch`

**Files:**
- Modify: `scenes/thumbnail.gd`
- Test: `tests/test_thumbnail.gd` (new)

**Interfaces:**
- Produces: `static func of_sketch(sketch: Variant) -> Thumbnail` (a `Thumbnail` whose `stage_id == ""` and `var sketch: Dictionary`); `_draw` branches on `sketch.is_empty()`. Drawing a sketch: fit `bounds` into `CANVAS` with a 12-unit margin, uniform scale `s`; `func _fit(p: Array) -> Vector2` maps level coordinates to canvas; walls via `_wall` on fitted points; bodies by kind with radius `maxf(4.0, r * s)`; pickups `_pickup(at, kind, 0.35)`; asteroids `_asteroid(at, 0.5, i)`; goal `_goal(at, 10)`; ship `_ship(at, 0.0, 1.2, false)`.
- Robustness: any missing or wrongly typed key is skipped; `null` or a non-Dictionary argument gives an empty sketch; a `push_warning` once per bad sketch, no error.

- [ ] **Step 1: Write the failing tests** in `tests/test_thumbnail.gd`

```gdscript
extends "res://tests/test_case.gd"


func test_every_official_sketch_draws() -> void:
	for id in Array(Progress.levels()) + Array(Progress.trainings()):
		var dir: String = Progress.TUTORIALS_DIR if id.begins_with("tutorial_") else Progress.LEVELS_DIR
		var thumbnail := Thumbnail.of_sketch(LevelFormat.sketch(LevelFormat.read(dir + id + ".json")))
		thumbnail.size = Thumbnail.CANVAS
		world.add_child(thumbnail)
		await frames(1)
		check(thumbnail.stage_id == "" and not thumbnail.sketch.is_empty(), "%s sketch thumbnail" % id)
		thumbnail.free()


func test_sketch_thumbnail_survives_bad_input() -> void:
	for bad in [null, {}, {"bounds": "x"}, {"bounds": [0, 0, 0, 0], "walls": [{"kind": 3, "points": "no"}]}, "text"]:
		var thumbnail := Thumbnail.of_sketch(bad)
		thumbnail.size = Thumbnail.CANVAS
		world.add_child(thumbnail)
		await frames(1)
		thumbnail.free()
	check(true, "no script error above")  # run_tests.gd fails the test on any logged script error
```

- [ ] **Step 2: Run** `TEST_FILTER=test_thumbnail.gd tests/run.sh` — expected: FAIL, `of_sketch` not found.

- [ ] **Step 3: Implement** in `scenes/thumbnail.gd`: `_init(id := "")`, `static func of_sketch(sketch: Variant) -> Thumbnail`, `func _draw_sketch() -> void` called from `_draw` when `stage_id == ""`; keep the official `match` as is.

- [ ] **Step 4: Run** the filter — expected: PASS; `tests/run.sh` — expected: `0 failed`.

- [ ] **Step 5: Render for a look**: extend `tools/render_thumbnails.gd` with a second loop writing `build/thumbnails/sketch/<id>.png` from `Thumbnail.of_sketch(LevelFormat.sketch(...))` for every official level; run it and view `build/thumbnails/sketch/level_08.png`.

- [ ] **Step 6: Commit** `feat(ui): draw a level sketch as a thumbnail`.

---

### Task 4: Community rows show the sketch

**Files:**
- Modify: `scenes/community_screen.gd:103-126` (`_add_row`)
- Test: `tests/test_community_screens.gd`

**Interfaces:**
- Consumes: `Thumbnail.of_sketch(row.get("sketch"))`.
- Row dict from the server gains `sketch` (Dictionary or null).

- [ ] **Step 1: Write the failing test** next to `test_community_lists_top_rows_with_title_version_author_and_likes` (l.241)

```gdscript
func test_community_rows_show_a_sketch_thumbnail() -> void:
	var net := _fake()
	_signed_in(net)
	var with_sketch := _row(_bytes())
	with_sketch.sketch = LevelFormat.sketch(LevelFormat.read(Progress.LEVELS_DIR + "level_01.json"))
	var without := _row(_bytes(), "Bare")
	without.sketch = null
	net.answer("GET", "/levels", 200, [with_sketch, without])
	var screen := await _community()
	var thumbnails := screen.find_children("*", "Thumbnail", true, false)
	check(thumbnails.size() == 2, "every row carries a thumbnail: %d" % thumbnails.size())
	check(not thumbnails[0].sketch.is_empty() and thumbnails[1].sketch.is_empty(), "the sketch reaches the first row only")
	check(_texts(screen).any(func(t: String) -> bool: return t.contains("Bare")), "a row without a sketch keeps its title")
```

- [ ] **Step 2: Run** `TEST_FILTER=test_community_screens.gd::test_community_rows_show tests/run.sh` — expected: FAIL (0 thumbnails).

- [ ] **Step 3: Implement**: in `_add_row`, before the title label in the `line` HBox, add `Thumbnail.of_sketch(row.get("sketch"))` with `custom_minimum_size = Vector2(164, 92)` (the official rows' size: `Main.ROW_HEIGHT - 2 * Main.ROW_MARGIN` tall, 16:9).

- [ ] **Step 4: Run** the filter — PASS; `tests/run.sh` — `0 failed`.

- [ ] **Step 5: Commit** `feat(community): sketch thumbnails on level rows`.

---

### Task 5: Worker stores and serves the sketch; `check-pr` allows it

**Files:**
- Create: `server/migrations/0007_version_sketch.sql` (`ALTER TABLE versions ADD COLUMN sketch TEXT;`)
- Modify: `server/src/submissions.ts:268-278`, `server/src/community.ts:61-75`, `server/src/cli.ts:10-11,63-99`, `server/README.md:25`
- Test: `server/test/worker/submissions.test.ts` (~l.630), `server/test/worker/community.test.ts:138`, `server/test/cli.test.ts`

**Interfaces:**
- `GET /levels` rows gain `sketch: object | null` (parsed from the column).
- `check-pr`: `SKETCH_FILE = /^levels\/(lvl_[a-z0-9]{10})\/v([1-9][0-9]*)\.sketch\.json$/`; allowed only when `levels/<id>/v<N>.json` is added in the same PR; must be ≤ 2048 bytes and parse as a JSON object. Error sentences: `"${path} may only be added together with levels/${id}/v${n}.json."`, `"${path} is larger than 2 KB."`, `"${path} is not a JSON object."`.

- [ ] **Step 1: Write the failing tests**
  - `community.test.ts:138`: add `sketch: null` to the expected row; add a test that `UPDATE versions SET sketch = '{"bounds":[0,0,1,1]}' WHERE ...` makes the row's `sketch` equal `{ bounds: [0, 0, 1, 1] }`.
  - `submissions.test.ts` "reviewed difficulty on merge": a merge with `mergedFile(gh, level, 1, text)` plus `gh.files.set("levels/<level>/v1.sketch.json", {text: '{"bounds":[0,0,1,1]}', sha})` stores that text in `versions.sketch`; a merge without the sketch file stores `null`.
  - `cli.test.ts`: accepts `{ ...newLevel(), ["levels/${A}/v1.sketch.json"]: '{"bounds":[0,0,1,1]}' }`; rejects a sketch alone with "may only be added together with"; rejects a 3000-byte sketch with "larger than 2 KB"; rejects `[]` with "is not a JSON object".

- [ ] **Step 2: Run** `cd server && npm test` — expected: the new tests FAIL.

- [ ] **Step 3: Implement** migration, merge fetch (`getFile(env, fetchFn, \`levels/${row.level}/v${row.version}.sketch.json\`)` → `?5` in the `INSERT INTO versions`), `getLevels` (`v.sketch` selected; map to parsed object or `null`), `check-pr` rules, README line for `GET /levels`.

- [ ] **Step 4: Run** `cd server && npm test && npm run typecheck` — expected: all pass.

- [ ] **Step 5: Commit** `feat(server): store and serve level sketches; allow them in submission PRs`.

---

### Task 6: `render_level.gd` and the `preview` job (spike first)

**Files:**
- Create: `tools/render_level.gd`
- Modify: `levels-repo/.github/workflows/check.yml`

**Interfaces:**
- `godot --path . -s res://tools/render_level.gd -- <level.json> <out.png>`: builds `LevelFormat.build(data, load("res://scenes/level_preview.gd"))` plus a `Starfield` in a `SubViewport` 1600 px wide (height from the sketch bounds' aspect, clamped 400–1600), a `Camera2D` centred on the bounds with zoom fitting them with a 5 % margin, waits two frames and `frame_post_draw`, saves PNG, exit 0; exit 1 on any failure (unreadable level, save error). Refuses `--headless` like `render_thumbnails.gd`.
- `preview` job outputs artifact `preview-<head_sha>` with `sketch.json`, `preview.png`, `pr.json` `{"number", "head_sha", "level", "version"}`.

- [ ] **Step 1: Spike in Actions.** On a scratch branch of `BRAITG/zero-gx-levels`, add a job that downloads the pinned Godot Linux editor (copy the download step from `.github/workflows/build.yml:50-64`, editor only), installs `xvfb mesa-utils libgl1-mesa-dri`, and runs `xvfb-run -a ~/godot/godot --path tool --rendering-driver opengl3 -s res://tools/render_thumbnails.gd` (exists on `master` after #42). Expected: `Rendered to build/thumbnails/` in the log and a non-empty PNG uploaded as an artifact. If it fails: try `LIBGL_ALWAYS_SOFTWARE=1`, then the Linux export binary; if both fail, stop and report (the spec's fallback drops the image).

- [ ] **Step 2: Implement** `tools/render_level.gd`; verify locally: `godot --path . -s res://tools/render_level.gd -- levels/level_09.json /tmp/l9.png` → view `/tmp/l9.png`: whole level visible, black hole and walls in frame.

- [ ] **Step 3: Write the `preview` job** in `levels-repo/.github/workflows/check.yml` (`needs: check`, same permissions): checkout PR head (`persist-credentials: false`), checkout `BRAITG/zero-gx@master` into `tool`, Godot download (cached), `xvfb` install, find the added `levels/<id>/v<N>.json` via `git diff --name-only origin/$BASE_REF...HEAD`, run `sketch_level.gd` to `out/sketch.json`; if `levels/<id>/v<N>.sketch.json` exists in the PR, `cmp` it with `out/sketch.json` and fail with "The sketch in the pull request does not match the level." on a difference; run `render_level.gd` to `out/preview.png`; write `out/pr.json`; `actions/upload-artifact` name `preview-${{ github.event.pull_request.head.sha }}`, path `out`.

- [ ] **Step 4: Verify** by opening a submission PR against the scratch workflow (reuse the spike branch): the job is green, the artifact holds the three files, `sketch.json` < 2 KB.

- [ ] **Step 5: Verify the mismatch rule**: push a commit to that PR with `levels/<id>/v<N>.sketch.json` containing `{}` → the `preview` job fails with the sentence above.

- [ ] **Step 6: Commit** (in `zero-gx`: `tools/render_level.gd`, `levels-repo/.github/workflows/check.yml`) `feat(levels-repo): sketch and render previews for submission PRs`.

---

### Task 7: `preview-comment.yml`

**Files:**
- Create: `levels-repo/.github/workflows/preview-comment.yml`

**Interfaces:**
- Trigger: `workflow_run` of "Check submission", `types: [completed]`, `conclusion == 'success'`. Permissions: `contents: write`, `pull-requests: write`, `actions: read`.
- Steps (one `actions/github-script` step after `actions/download-artifact` by run id): read `pr.json`; require `pr.head_sha == workflow_run.head_sha`; look up the PR by number and require `pr.head.sha == head_sha` (skip quietly otherwise: the PR moved on); via the Git Data API, if `levels/<level>/v<version>.sketch.json` on the PR's head differs from `sketch.json`, create a commit on the PR branch with it (message `Add level sketch`); on branch `previews` (create as orphan if missing), write `<number>/<head_sha>.png` and delete other files under `<number>/` in one commit; upsert the comment whose body contains `<!-- zero-gx-preview -->` with:
  ```
  <!-- zero-gx-preview -->
  **Preview of `<level>` v<version>** at `<head_sha>`

  ![Level render](https://raw.githubusercontent.com/BRAITG/zero-gx-levels/previews/<number>/<head_sha>.png)

  [Watch the proof run in the browser](https://braitg.github.io/zero-gx/viewer/?level=https://raw.githubusercontent.com/BRAITG/zero-gx-levels/<head_sha>/levels/<level>/v<version>.json&demo=https://raw.githubusercontent.com/BRAITG/zero-gx-levels/<head_sha>/proof/<level>/v<version>.demo.gz)
  ```
  When the PR is closed or merged (`pull_request` `closed` trigger in the same workflow, trusted context), delete `<number>/` from `previews`.

- [ ] **Step 1: Write the workflow** with all actions pinned by SHA like `check.yml`.

- [ ] **Step 2: Verify on the test PR** from Task 6: after `check.yml` completes, exactly one comment appears with a visible image and the viewer link; the PR branch gains `v<N>.sketch.json`; `check.yml` reruns and the comment is edited, not duplicated; `previews/<number>/` holds one PNG.

- [ ] **Step 3: Verify cleanup**: close the test PR → `previews/<number>/` is gone.

- [ ] **Step 4: Commit** `feat(levels-repo): preview comment with render and viewer link`.

---

### Task 8: Web viewer and Pages deploy

**Files:**
- Create: `scenes/viewer_main.gd`, `scenes/viewer_main.tscn` (root `Control` with the script)
- Modify: `export_presets.cfg` (preset `Web`, `variant/thread_support=false`, `export_path="build/web/index.html"`, main scene override to `res://scenes/viewer_main.tscn` via `application/run/main_scene` feature override in `project.godot` for feature `web`), `.github/workflows/build.yml` (templates `web_nothreads_release.zip` in the unzip list, cache key suffix `-web`, a `web` job on push to `master`: export, `actions/upload-pages-artifact` from `build/web` under `viewer/`, `actions/deploy-pages`, permissions `pages: write`, `id-token: write`)
- Test: `tests/test_viewer_main.gd` (new)

**Interfaces:**
- `ViewerMain.allowed_url(url: String) -> bool`: `^https://raw\.githubusercontent\.com/BRAITG/zero-gx-levels/[0-9a-f]{40}/.+$`.
- `ViewerMain.start(level_bytes: PackedByteArray, demo_bytes: PackedByteArray) -> String`: returns `""` and shows `DemoViewer.create(data, demo, back)` when `Demo.peek_level_sha256(demo_bytes) == CommunityWire.sha256_hex(level_bytes)`, the level parses and validates, and the demo decodes; otherwise returns the reason (`"The demo was recorded on a different level."`, `"The level file is not a valid Zero-GX level."`, `"The demo file is not a valid Zero-GX demo."`) and shows it in a Label. `back` reloads the viewer scene.
- `_ready`: reads `level` and `demo` from `JavaScriptBridge.eval("location.search")` (on non-web builds, from `OS.get_cmdline_user_args()` for local testing), rejects URLs failing `allowed_url` with `"Only files from BRAITG/zero-gx-levels at a commit can be shown."`, fetches both with `HTTPRequest`, calls `start`.

- [ ] **Step 1: Write the failing tests**

```gdscript
extends "res://tests/test_case.gd"

const GOOD := "https://raw.githubusercontent.com/BRAITG/zero-gx-levels/" + "a".repeat(40) + "/levels/lvl_aaaaaaaaaa/v1.json"


func test_only_commit_pinned_levels_repo_urls_are_allowed() -> void:
	check(ViewerMain.allowed_url(GOOD), "a raw URL at a commit is allowed")
	for bad in [GOOD.replace("a".repeat(40), "main"), GOOD.replace("zero-gx-levels", "zero-gx"), GOOD.replace("https", "http"), "https://evil.example/" + GOOD]:
		check(not ViewerMain.allowed_url(bad), "must refuse %s" % bad)


func test_viewer_refuses_a_demo_of_another_level() -> void:
	var viewer := ViewerMain.new()
	world.add_child(viewer)
	var level_01 := FileAccess.get_file_as_bytes("res://fixtures/levels/level_01.json")
	var level_05 := FileAccess.get_file_as_bytes("res://fixtures/levels/level_05.json")
	var demo_01 := FileAccess.get_file_as_bytes("res://fixtures/demos/level_01.demo.gz")
	check(viewer.start(level_05, demo_01) == "The demo was recorded on a different level.", "hash mismatch must be refused")
	check(viewer.start(level_01, demo_01) == "", "the matching pair plays")
	check(viewer.find_children("*", "DemoViewer", true, false).size() == 1, "a DemoViewer is shown")
```

- [ ] **Step 2: Run** `TEST_FILTER=test_viewer_main.gd tests/run.sh` — expected: FAIL.

- [ ] **Step 3: Implement** `scenes/viewer_main.gd` (`class_name ViewerMain extends Control`) and the scene.

- [ ] **Step 4: Run** the filter — PASS; `tests/run.sh` — `0 failed`.

- [ ] **Step 5: Export locally** after installing the 4.7.2 web templates: `godot --headless --path . --export-release "Web" build/web/index.html`; serve `build/web` with `python3 -m http.server 8080`; open `http://localhost:8080/?level=<GOOD-style URL of a real merged level>&demo=<its proof>` in the browser tool; expected: the run plays; also open with no query → the refusal sentence shows. Check the console for errors from `GodotPlayGameServices` or `Community` autoloads; guard them with `OS.has_feature("web")` if they log.

- [ ] **Step 6: Enable Pages** on `BRAITG/zero-gx` (Settings → Pages → Source: GitHub Actions). User step; ask once, then continue.

- [ ] **Step 7: Add the `web` job** to `build.yml`; push; expected: the job deploys and `https://braitg.github.io/zero-gx/viewer/` loads.

- [ ] **Step 8: Commit** `feat(web): browser demo viewer on GitHub Pages`.

---

### Task 9: Deploy the levels-repo workflows and verify end to end

**Files:**
- `BRAITG/zero-gx-levels`: `.github/workflows/check.yml`, `.github/workflows/preview-comment.yml` (copied from `levels-repo/` here)

- [ ] **Step 1:** Open a PR in `zero-gx-levels` with both workflow files; merge after its own check passes.
- [ ] **Step 2:** Apply the Worker migration and deploy the server (`deploy-server` job on `master` after #42 merges, or `wrangler d1 migrations apply` + `wrangler deploy` per `server/README.md`).
- [ ] **Step 3:** Publish a level from the app on a device; on its PR: comment present, image visible, viewer plays the run; after approval and merge, the app's Community list shows the sketch thumbnail on that level's row.
- [ ] **Step 4:** Update `README.md` (Community section: thumbnails; a new "Reviewing a submission" paragraph with the comment and the viewer) and `server/README.md` (`GET /levels` `sketch`). Commit `docs: community thumbnails and PR previews`.
