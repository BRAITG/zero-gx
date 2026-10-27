# Community level thumbnails and pull-request review

Second half of issue #40. The first half (composed thumbnails for official levels and Training, the
single-column stage list) shipped in #42.

## Goals

1. Every Community level shows a thumbnail in the list: a bird's-eye picture of the level in the game's
   own look, drawn by the game from a small *sketch* that travels with the level's metadata.
2. A moderator can review a submission from its pull request in `BRAITG/zero-gx-levels` without
   downloading files: a full render of the level in a PR comment, and a one-click browser player that
   replays the submitted proof run over the submitted level.
3. Derivation and rendering happen in GitHub Actions. The Cloudflare Worker fetches and stores; it
   computes nothing.

## Non-goals

- Composed, hand-authored scenes for community levels (official levels keep theirs).
- Video rendering, GIFs, or embedding the player inside the PR page (GitHub cannot embed interactive
  HTML).
- Thumbnails for the player's own drafts in My levels (the same sketch code makes that easy later).

## The sketch

A JSON object derived from a level file by the game, under 2 KB:

```json
{
  "bounds": [x, y, w, h],
  "ship": [x, y],
  "goal": [x, y],
  "walls": [{"kind": "blue", "points": [[x, y], ...]}],
  "bodies": [{"kind": "planet", "position": [x, y], "radius": 64}],
  "pickups": [{"kind": "boost", "position": [x, y]}],
  "asteroids": [[x, y], ...]
}
```

- `bounds` is the axis-aligned box around everything, grown by the ship's radius.
- Walls keep their kind; their points are simplified with Ramer–Douglas–Peucker. The tolerance starts
  at `max(w, h) / 320` (one thumbnail pixel) and doubles until the whole sketch serialises under 2 KB.
  Closed walls stay closed.
- Numbers are rounded to integers; the file is one line of JSON with sorted keys and no spaces
  (`JSON.stringify(sketch, "", true)`), so the same level always gives the same bytes. If the sketch
  cannot bring it under 2 KB after eight tolerance doublings, asteroids are dropped from the end, then walls, pickups and bodies, each from the end, until it fits. `bounds`, `ship` and `goal` never drop.

`LevelFormat.sketch(data: Dictionary) -> Dictionary` derives it. `tools/sketch_level.gd` is the
command-line wrapper: `godot --headless --path . -s res://tools/sketch_level.gd -- <level.json> <out.json>`.
It runs headless: deriving a sketch draws nothing.

## Drawing a sketch

`Thumbnail` gains a second entry point, `Thumbnail.of_sketch(sketch: Dictionary)`. It fits `bounds`
into the 320×180 canvas with a 12-unit margin and one uniform scale, then draws with the helpers the
official thumbnails use: `_wall` (line widths stay in canvas units, not level units), `_planet`,
`_black_hole`, `_star` (radius scaled, at least 4 units), `_pickup` at a fixed small scale, asteroids as
small rocks, `_goal` at a fixed 10-unit radius, `_ship` at scale 1.2 pointing right. The starfield
background is the same. A sketch that fails to parse draws the background only and logs a warning; the
list never breaks on a bad sketch.

The community list row keeps its current card (`CommunityScreen._add_row`) and gains the sketch
thumbnail at the left of its title line, at the official rows' thumbnail size.

## Submission flow

Nothing changes for the player. The sketch is added to the submission by the levels repository's own
workflow, so it is part of what the moderator reviews and merges.

1. The Worker opens the submission PR as today: `levels/<id>/v<N>.json`, `proof/<id>/v<N>.demo.gz`,
   `meta.json`. Submission branches live in `BRAITG/zero-gx-levels` itself (the bot pushes them), so
   `pull_request` workflows run with the repository's own `GITHUB_TOKEN`.
2. `check.yml` (the existing `pull_request` job, `contents: read`) gains a `preview` job that runs regardless of
   `check`'s result (`check` fails until a moderator sets the difficulty label, and the preview is what they set it from),
   behind a first step that refuses any path a submission may not touch:
   - checks out the PR head and `BRAITG/zero-gx` at `master` into `tool/`, downloads the pinned Godot
     Linux editor (the same download `build.yml` uses, cached);
   - derives `levels/<id>/v<N>.sketch.json` with `tools/sketch_level.gd`;
   - renders `preview.png` with `tools/render_level.gd` under `xvfb-run` (software OpenGL): the level
     built with `scenes/level_preview.gd` in a `SubViewport`, camera fitted to the sketch's bounds, 1600 px
     wide;
   - uploads `sketch.json`, `preview.png` and a small `pr.json` (`number`, `head_sha`, `level`, `version`)
     as one artifact named `preview-<head_sha>`.
   This job runs untrusted data through trusted code and holds no secrets beyond a read token.
3. `preview-comment.yml`, a `workflow_run` job on `check.yml` completed (trusted context,
   `contents: write`, `pull-requests: write`):
   - downloads the artifact, refuses it unless `pr.json`'s `head_sha` matches the workflow run's head SHA;
   - commits `levels/<id>/v<N>.sketch.json` to the PR's branch (the bot's branch in this repository) if
     the file differs from what is there. The sketch is now part of the submission;
   - commits `preview.png` to the orphan branch `previews` as `<pr>/<head_sha>.png` (earlier SHAs of the
     same PR are deleted in the same commit, so the branch holds one image per PR; images and comments
     stay after the PR is merged or closed);
   - posts, or edits, the one comment it owns on the PR (found by a hidden marker): the render as an
     image, the viewer link, and the head SHA it was made from. An updated PR gets an updated comment;
     a stale proof is never shown because the link carries the SHA.
   The sketch commit is made with `GITHUB_TOKEN`: GitHub creates a "Check submission" run for it but parks it as
   `action_required`, so the new head has no `check` status until the next label or unlabel event runs `check`
   there (that run then finds the sketch present and identical and only refreshes the comment). A moderator who
   labelled before the comment appeared relabels once.
4. At merge, the Worker (which already fetches the merged `v<N>.json` to hash it) also fetches
   `v<N>.sketch.json` from the default branch and stores it in a new `versions.sketch TEXT` column
   (migration `0007_version_sketch.sql`). A missing sketch (a PR merged before this shipped, or merged
   without the workflow) stores `NULL`; the row is still listed.
5. `GET /levels` returns `sketch` (an object, or `null`) on every row. The app draws it. Rows without a
   sketch show the background only.

The `preview` job re-derives the sketch and compares bytes when the PR already carries one; a mismatch
fails the job, so a hand-edited sketch never reaches `main` with a green check. `check-pr` in
`server/src/cli.ts` only learns that `levels/<id>/v<N>.sketch.json` is an allowed file in a submission
PR when `levels/<id>/v<N>.json` is in the same PR.

## The browser player

A Godot **Web** export of a viewer-only entry scene, published to `BRAITG/zero-gx-levels`'s GitHub Pages
site by that repository's own `viewer` workflow (template `levels-repo/.github/workflows/viewer.yml`): it
checks out `BRAITG/zero-gx` at `master`, exports the `Web` preset and deploys it, daily and on demand.
Pages stays off on `zero-gx`: its site would shadow the organisation site's `/zero-gx/privacy/` page, which
Google Play requires.

- Export preset `Web` with threads disabled (`variant/thread_support=false`): GitHub Pages cannot set the
  cross-origin isolation headers threads need. Main scene for the preset: `scenes/viewer_main.gd`.
- `viewer_main.gd` reads `level` and `demo` from the page's query string (`JavaScriptBridge`), accepts
  only `https://raw.githubusercontent.com/BRAITG/zero-gx-levels/<40-hex sha>/...` URLs, fetches both with
  `HTTPRequest`, checks the demo's level hash against the fetched level, then shows `DemoViewer` full
  screen. Any failure shows the reason in plain text. Nothing else in the game is reachable from the
  viewer: no community sign-in, no progress.
- The PR comment links
  `https://braitg.dev/zero-gx-levels/viewer/?level=<raw level URL at head SHA>&demo=<raw demo URL at head SHA>`.
  The export is about 30 MB on first load and cached by the browser afterwards.
- The viewer is also useful outside PRs (a moderator can paste any two such URLs), but nothing else
  depends on it.

## Security

- The `pull_request` job never has write tokens or secrets. It executes the game engine on untrusted
  JSON and demo bytes, which the validation step already does with the TypeScript port.
- The `workflow_run` job never checks out or executes PR code: it downloads one artifact, checks the SHA,
  and writes two files plus a comment. It commits only to bot-owned submission branches and `previews`.
- The viewer loads only from the allow-listed raw URL prefix and never carries credentials.
- Existing gates are untouched: validation, moderator approval and the difficulty label decide; the
  preview is information for the moderator, not a check.

## Testing

- `tests/test_level_format.gd`: a sketch of a fixture level is stable (same bytes twice), under 2 KB
  for the largest official level, keeps every wall kind and body, and its bounds enclose all points.
- `tests/test_thumbnail.gd`: `Thumbnail.of_sketch` draws without errors for every official level's
  sketch and for `{}`; a sketch larger than the canvas is scaled to fit (checked through the computed
  transform).
- `tests/test_community_screens.gd`: a list row with a sketch shows a `Thumbnail`; one without shows the
  background thumbnail and the same title.
- `server/test`: `GET /levels` returns `sketch` as parsed JSON or `null`; merge handling stores the sketch
  when present and `NULL` when the file is missing; `check-pr` accepts a sketch beside its level and
  refuses one without a level.
- Workflows are verified on a real submission PR in `zero-gx-levels` before this is called done: comment
  posted, image visible, viewer link plays the run.

## Open risk

Godot needs a renderer for `render_level.gd`; `--headless` cannot rasterise. The plan relies on
`xvfb-run` with Mesa's software OpenGL on `ubuntu-24.04`. The first implementation step is a spike that
proves this in Actions with the editor binary. If that fails, the second try is the Linux export of the
game under `xvfb-run` with `--rendering-driver opengl3`. If both fail, the comment ships without the
image (sketch and viewer link still work) and the render is dropped from this design.
