# Final leaderboard fixwave

## Changes

Exactly the three requested corrections; no dependencies, server/API changes, score-verification changes, retroactive enqueueing, or additional UI refresh loops.

1. **POST provenance — `scenes/level.gd`, `tests/test_flow.gd`.** POST `points` describe the submitted run, whereas `rank` describes the stored best. Only `best: true` can supply a provisional exact row. With `best: false`, the result retains the board's separately labelled remote score and estimates the local run; without a usable board it remains unverified. Corrected the formerly impossible test fixture (submitted 1800, stored 9000, rank 2, best false), and covered failed refresh both with and without a previous board. This supersedes the incorrect POST-points interpretation recorded in the Task 5 historical report.
2. **Central cache invalidation — `scripts/community.gd`, `tests/test_community_boards.gd`.** A successful current-owner/current-revision score settlement expires the public board and that owner's private standing on disk by setting `fetched_at` to zero, preserving all cached rows and local best/demo data. Per-hash invalidation serials participate in request coalescing. A pre-upload GET cannot restore freshness or replace a newer board; when it is the only answer available, it can supply explicitly stale cached data. Existing account/generation guards remain in force. Tests exercise background upload with no open result/sheet, persistence across reset, opening the real sheet, held older GETs, independent post-upload GETs, and wrong owner/hash/superseded revision.
3. **Current-hash selection — `scenes/level.gd`, `tests/test_flow.gd`.** The result uses filename-scoped best points only when the saved best demo matches the current hash, as campaign rows already do. Otherwise it estimates the just-finished current run. The 9999-point old-hash historical best and its replay remain untouched; the current 1800-point non-best win is not enqueued. Both preview and full sheet receive current-hash points.

Seven new behavioral regression tests were written before production edits. No public signatures changed. The shared board renderer, existing UI refresh serialization, outbox format and score-validation policy were reused unchanged.

## Isolation

All test processes ran with:

```sh
export HOME=/var/tmp/leaderboards-final-fix.32QGfM/home
export XDG_DATA_HOME=/var/tmp/leaderboards-final-fix.32QGfM/data
export TMPDIR=/var/tmp/leaderboards-final-fix.32QGfM/tmp
```

Godot writes were observed under that HOME's `Library/Application Support/Godot/app_userdata/Zero-GX`, with the existing runner additionally redirecting Progress, Settings, MyLevels, Community and score/replay stores. Renders used the separate `/var/tmp/leaderboards-final-fix.32QGfM/render-home` and explicit `render_*` storage paths. Fake device/network boundaries only; no live endpoint requests or real player stores.

## Commands and output

### RED, before implementation

```sh
TEST_FILTER=test_final_fix godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd
```

Exit **1**, **1 passed, 6 failed**, each for the intended missing behavior: the two best-false cases, old-hash result, background expiration, held older GET freshness, and pre/post-upload coalescing. The existing owner/hash/revision guards already passed. Full output: `final-fix-red.log`.

### Covering checks, once after corrections

```sh
for suite in test_flow test_community_boards test_community_sync test_leaderboard; do
  TEST_FILTER="$suite" GODOT=godot tests/run.sh
 done
```

All four exited **0**:

| Filter | Output | Log |
| --- | --- | --- |
| `test_flow` | 70 passed, 0 failed | `final-fix-test_flow.log` |
| `test_community_boards` | 14 passed, 0 failed | `final-fix-test_community_boards.log` |
| `test_community_sync` | 60 passed, 0 failed | `final-fix-test_community_sync.log` |
| `test_leaderboard` | 13 passed, 0 failed | `final-fix-test_leaderboard.log` |

### Full game, once afterward

```sh
GODOT=godot tests/run.sh
```

Exit **0**, **825 passed, 0 failed**. Full output: `final-fix-full-game.log`. No SCRIPT ERROR or unexpected parse errors. Logs retain the existing Camera2D interpolation warning, NaN/bad-thumbnail validation warnings, deliberately corrupt `test_progress.cfg` parse error, and shutdown leak/resource-in-use warnings (full suite: one CanvasItem RID, four ObjectDB instances, one resource). Covering runs each report two ObjectDB instances at shutdown; these are not warning-free runs.

## Render evidence

Temporary harness loaded the real flow fixture helpers, Level, recorder, HUD, shared preview and monetization chrome. Network/device boundaries were faked; neither board data nor UI text was injected into controls. The thirty-player fixture has 10000 at rank 1, the signed-in player's stored 9000 at rank 2, and lower scores down to 100. Its top twenty and quantiles agree; POST best false returns submitted 1800, not stored 9000.

```sh
HOME=/var/tmp/leaderboards-final-fix.32QGfM/render-home \
  godot --path . --resolution 1280x720 --rendering-method gl_compatibility \
  --rendering-driver opengl3 --fixed-fps 60 --audio-driver Dummy \
  -s res://tools/render_final_fix.gd
```

Godot **4.7.2**, OpenGL/Metal on Apple M1 Pro, exit **0**. Both PNGs are **1280×720**. Actual result rectangle `(90, 6.5), (1100, 641)` fits above the **66-pixel** reserved footer; all visible actions are enclosed. Both images were visually inspected. No layout change was needed.

- `final-fix-best-false-fallback.png`: 1800 local estimate, separate cached remote 9000/rank 2, failed post-upload GET, offline/cached labels. Actual requests: **1 POST, 2 GETs**.
- `final-fix-current-hash.png`: current 1800 estimated separately from the current board's remote 9000; historical old-hash 9999 absent. Actual requests: **0 POST, 1 GET**.
- `final-fix-render.log`: geometry, HUD/preview text and request counts. The first temporary render attempt failed only on an untyped harness string; it was corrected before successful rendering. The temporary script was deleted. Render shutdown reports six ObjectDB instances and two resources in use.

## Intentionally skipped / remaining risk

No server suite, APK/export, Android hardware/native-banner check or live Play/Integrity/production check was run: the server/API and native bridge were not changed. Rendering proves desktop logical layout with a fake platform, not hardware behavior. Cached remote standings remain explicitly cached when a refresh fails; they are not claimed to be newly verified.
