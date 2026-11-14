# Level Leaderboards Design

## Goal

Every campaign and community level gets a leaderboard: the top 20 runs by name, the player's own exact rank when their best run is on the server, and an honest estimate of where a best run would rank when the server does not have it. Players see their standing after a win, in a community level's details and in the campaign level list.

The server side mostly exists: verified scores (`POST /scores`, a run recording replayed by the server from a device that passes Google's strongest integrity check) and boards (`GET /boards/:sha256`) shipped with the community server, but the app never posted scores or showed boards (`2026-10-20-community-app-design.md` deferred them). This design adds the app side, two board fields and the missing official-level registration.

**Included:** posting new bests, a retry queue for unposted bests, board display in three places, the rank estimate, the board answer's new fields, and fixing official-level registration.

**Excluded:** watching other players' replays from a board, player profiles, boards for older level versions, changes to how runs are verified or scored, and desktop or non-Play builds (they stay offline, as every community feature).

## Decisions

| Topic | Decision |
|---|---|
| Levels | Campaign levels and community levels. Training stages and editor drafts never have boards. |
| Ranks | A posted best has an exact rank ("#37 of 412"). A best the server does not have gets an estimate from the board's score distribution ("about top 15% · ~62 of 412"), always labelled as an estimate and never placed inside the top 20. |
| Posting | Automatic, only when a win beats the player's best on that level. If the post cannot complete (offline, failed check, server error), the best unposted run is kept and retried later. |
| Board size | The top 20. |
| Where | Result screen after a win, community details sheet, campaign level list. |

## Posting runs

A run is posted when all hold: Play build with community available, signed in, a campaign or community level (not training, not an editor Test or Publish flight, not a replay), a win, and `Progress.record_win` reports a new best.

1. When the result card shows, the run's recording (already saved as the level's best demo) is queued: one entry per level, holding the level id, its sha256 and the demo path. A newer best on the same level replaces the queued entry.
2. The queue sends `POST /scores` with the demo bytes and a strong-integrity token bound to them, as the server already requires. The result card shows "Posting…", then the exact rank from the answer (`rank`), or "Will post when online" and the estimate.
3. Retries run with the existing background flush (`Community._schedule`, spaced by `FLUSH_GAP_SECONDS`, serialized with other integrity requests), and when the player opens Community or a board. A `400`/`404` answer (the server rejects the run or no longer knows the level) drops the entry and keeps the local best; connection failures and `5xx` keep it. A failed strong-integrity check keeps it but is retried at most once per app launch.
4. The queue file belongs to the signed-in player, like the play-history outbox: entries of another account are not sent, and deleting the community account deletes the queue.
5. Best runs made before this feature are not posted retroactively; they get an estimate until the player beats them.

## Board answer

`GET /boards/:sha256` keeps every existing field (`level`, `rows`, `you`) and its ranking rules (banned players are neither listed nor counted; ties by earlier post, then player id). Changes:

- `rows` holds the top 20 by default; an optional `limit` (1–100) keeps older clients' 100 available.
- New `count`: the number of ranked players on that version.
- New `quantiles`: 21 integers, the points at 0%, 5%, …, 100% of the ranked scores sorted from lowest to highest (nearest-rank), or `[]` when `count` is 0. They are aggregates; no player is identified by them.

The board answer is cached per sha256 on the device (as list pages are) so estimates and the campaign list work offline.

## Rank estimate

For a local best `b` with no posted score on that version, using the cached `count` `n` and `quantiles` `q`:

1. If `n` is 0: "No ranked runs yet".
2. Find the fraction `f` of ranked scores at or above `b` by linear interpolation between neighbouring quantiles (`b` above `q[20]` gives 0; below `q[0]` gives 1).
3. Estimated rank `r = max(21, round(f · n) + 1)` when `b` is below the 20th row's points, otherwise "would be in the top 20" without a position (it is not verified).
4. Text: "about top P% · ~r of n+1", with `P = max(1, ceil(100 · r / (n + 1)))`. It is labelled "Estimate" and styled dim.

Pure function `RankEstimate.estimate(points, count, quantiles, top20_lowest) -> Dictionary` in `scripts/rank_estimate.gd`, unit-tested.

## Where boards show

- **Result screen (win):** a line under the score: "Rank #37 of 412" (posted), "Posting…", or the estimate. A **Board** button opens the board sheet.
- **Board sheet:** an opaque `Overlay` titled with the level name: the top 20 (rank, name, points, time), then the player's own row (exact, or the estimate, or "Not played yet"), highlighted. Uses `Style` and the existing row conventions; keyboard and gamepad focus as other sheets.
- **Community details sheet:** a "Board" section with the top 5 and the player's row, and a **Full board** button opening the board sheet.
- **Campaign level list:** next to the best total, a small dim "#37" or "~top 15%" from the cached board; nothing when no board is cached. Opening the list refreshes boards of levels the player has completed, at most one request per level per hour.

## Official level registration

Since r124 Cloudflare's ordinary Bot Fight Mode answers GitHub runner requests to `POST /admin/official` with `403` ("Just a moment..."); a normal WAF custom skip rule cannot bypass it. The owner approved trusted deployment registration instead of modifying zone security.

- After both release creation and server/database deployment succeed, CI registers the trusted checkout's canonical bundled hashes through authenticated Wrangler D1 execution, using the existing `CLOUDFLARE_API_TOKEN` and optional `CLOUDFLARE_ACCOUNT_ID` deployment environment. Never run registration on untrusted pull-request input.
- Resolve the real `zero-gx` database id by name, not the committed placeholder. Validate release/name/count boundaries before network access; use strictly allowlisted SQL values and the same `sha256` upsert semantics as `postOfficial`. Registration is idempotent and preserves old hashes.
- Make every configured-credential registration failure fail the job; a missing deployment token explicitly skips, matching deployment policy. Credentials never appear in arguments or logs and are scoped to the registration step.
- Keep Bot Fight Mode, zone security, `workers_dev = false` and the existing admin-authenticated public endpoint unchanged. No WAF bypass or alternate public host is needed.
- After review, register the already published current release from its trusted checkout and verify every bundled hash with a read-only D1 query. No remote database writes occur during implementation.

## Server and privacy

- No new tables. `count` and `quantiles` come from one query over `scores` for the version (excluding banned players), in the same batch as the rows.
- Players' names on boards are already public by design (`PRIVACY.md` "Who can see it" lists leaderboards). Add the rank estimate's inputs (score distribution) to that list as aggregate data.
- The privacy policy discloses automatic account-owned new-best campaign/community score and recording uploads, offline retry, account-deletion erasure and public score-distribution aggregates. A campaign win with no known community account never signs in or queues retrospectively; explicitly opening a board may sign in. Publish the matching website policy before rollout.

## Testing

- `RankEstimate`: exact quantile hits, interpolation, below the lowest and above the highest score, `n` = 0, `n` = 1, the top-20 boundary, percent never 0.
- Score queue: one entry per level, newer best replaces older, sent once on success, kept on connection failure and `5xx`, dropped on `400`/`404`, other account's entries not sent, cleared on account deletion, never queued for training, drafts or test flights.
- Server: `count` and `quantiles` (nearest-rank, banned excluded, empty board), default `limit` 20 and `limit=100`, existing fields unchanged.
- UI: result line states (posted rank, posting, offline estimate), board sheet rows and own row, details section, campaign list badge, desktop shows none of it; screenshots at 1280×720 reviewed before merge.
- CI: stub the authenticated Wrangler boundary; verify missing-credential skip, validated canonical hashes and release, idempotent upsert with old hashes preserved, invalid release/names rejected before network, real database-id resolution, visible remote failures and no credential leakage. Registration depends on both release creation and database deployment.
