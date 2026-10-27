# Medals: bronze, silver and gold per stage

## Goal

Every won stage earns one of three medals from its best score, so a player can see at a glance which
stages are done well and which deserve another run. Medals are spaceship-flavoured code-drawn icons in
the game's existing icon style, not stars.

## Par

A stage has one tuning number, `par`: the points a competent run scores. Medals are fixed fractions of
it, rounded up to whole points:

| Medal | Best score |
|---|---|
| Gold | ≥ par |
| Silver | ≥ 0.7 × par |
| Bronze | ≥ 0.4 × par |
| none | won, below bronze |

A stage without a par shows no medal (and no thresholds). Training stages have no par.

### Official levels

`par` is an optional top-level integer key of the level file (`levels/level_NN.json`), authored from a
real play of the level by the maintainers, at least `Progress.MIN_POINTS`. Both validators
(`LevelFormat.validate`, `server/src/core/level.ts validateLevel`) accept it; `LevelFormat.build`
carries it to `Level.par` and `serialize` writes it back, so the editor round trip keeps it. Player
drafts may carry it too (the editor does not expose it; a draft imported from an official file keeps
it). Adding `par` changes an official level's hash; the release job that registers official levels
already handles a new hash as a new version.

### Community levels

`par` is derived from the submitted proof run: its points by the default weights, exactly what the
server would score the same demo as. It is computed in the levels repository's `preview` job
(`check.yml`), by the game (`tools/sketch_level.gd` gains an optional third argument, the demo, and
writes `par` into the sketch file), and committed to the submission PR inside
`levels/<id>/v<N>.sketch.json` by `preview-comment.yml`, exactly like the rest of the sketch. The
`preview` job's byte comparison stays strict, so the derived par cannot be hand-edited.

A moderator adjusts a community par with a PR label `par:<points>` (a positive integer, at most one such
label; `check-pr` refuses two or a malformed one with "At most one par:<points> label is allowed, with a
whole number of points.", so the required check fails before merge). At merge the Worker reads it from
the signed delivery like the difficulty label; the label wins over the sketch's `par`. No Worker
computation: the Worker copies one number.

`versions` gains `par INTEGER` (migration `0008_version_par.sql`): the label's value, else the sketch's
`par`, else `NULL`. `GET /levels` returns `par` (integer or null). The app writes it beside the cached
level when it downloads one (`Community.download`), so a community stage knows its par offline, and
reads it when it builds the stage.

Follow-up, not in this design: raising a community par automatically when its author posts a better
score than the proof.

## Where medals show

- **Official and Community rows:** the earned medal to the left of the best total (official rows) or
  at the end of the title line (community rows), only when the stage is won. Community rows read the
  local best under `community_<sha256>` the same way official rows read theirs.
- **Result card:** the medal earned by this run, under the total, with one line for what is next:
  "Silver at 840" (the lowest threshold above this run), or "Gold" alone when nothing is above. A run
  below bronze shows "Bronze at 420". Stages without par show neither.
- **Best demo** entries (the Replay button's stage) show the same medal as the row.

Medals are drawn by `ScoreIcon` with a new `Kind.MEDAL` and a tier, in the existing flat single-colour
style: a ship-silhouette medallion on a short ribbon, bronze `#c8803c`, silver `#c9d2e3`, gold `#ffcf4a`.
The exact shape is settled in the browser preview before implementation, like the thumbnails.

## Computation

`Progress.medal(points: int, par: int) -> Medal` (`enum Medal { NONE, BRONZE, SILVER, GOLD }`) and
`Progress.next_threshold(points, par) -> int` (0 when gold) are the only places the fractions live;
`BRONZE_FRACTION := 0.4`, `SILVER_FRACTION := 0.7` are constants in `Progress`. The server stores and
serves par; it never computes a medal.

## Testing

- `test_progress.gd`: medal boundaries (exactly 0.4 par is bronze, one point under is none; rounding up
  of fractional thresholds), next threshold, no par → NONE and 0.
- `test_level_format.gd`: `par` accepted, kept by the round trip, rejected below `MIN_POINTS` and when
  not an integer; the stable-layout test keeps passing for files without it.
- `test_flow.gd`: an official row shows the medal of its best; the result card shows the earned medal
  and the next threshold; a stage without par shows neither.
- `test_community_screens.gd`: a row with `par` and a local best shows a medal; without a local best
  none.
- Server: `GET /levels` returns `par`; merge stores the label's value over the sketch's, the sketch's
  when unlabelled, `NULL` when neither; two `par:` labels or a non-integer label are refused at merge
  with the sentence "Exactly one par:<points> label is allowed."; `check-pr` accepts a sketch with a
  `par` key.
- Preview job: the sketch file written for a submission contains `par` equal to the server's score of
  the proof (one fixture pair checked in `test_level_format.gd` against `DemoCheck.score`).
