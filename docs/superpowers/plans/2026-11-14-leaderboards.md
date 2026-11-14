# Level Leaderboards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add campaign and community top-20 leaderboards, automatic best-run posting, and clearly marked rank estimates.

**Architecture:** Extend the existing batched board endpoint with count and quantiles. A durable account-owned score outbox feeds the existing Community scheduler; a shared board sheet and rank formatter serve results, details and campaign rows. Reuse existing replay validation and integrity binding unchanged.

**Tech Stack:** Godot 4.7.2 GDScript, TypeScript Cloudflare Workers, D1, existing Vitest and Godot test runners. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-14-leaderboards-design.md`

## Global Constraints

- Online boards and score uploads are Google Play Android only. Desktop and non-Play builds make no requests.
- Boards are version-hash scoped. Training, editor Test/Publish flights and replay playback never post.
- Preserve strong-integrity verification, nonce binding, score calculation and banned-player exclusions.
- Keep existing board response fields; default 20 rows, optional `limit` from 1 to 100.
- All HTTP/plugin waits remain at most 30 seconds. Background attempts are spaced by `FLUSH_GAP_SECONDS` and use the existing integrity serialization.
- Never publish an unverified estimate as a ranked row. No replay watching or player profiles.
- Work only in this task's linked worktree. Commit and push each completed slice.
- Official registration uses only the trusted release checkout and existing Cloudflare deployment credential/D1 control plane. Keep Bot Fight Mode, zone security, the public admin endpoint and `workers_dev = false` unchanged.

## Review Focus

1. A newer best arrives while an older upload awaits: acknowledging the older upload must not erase the newer queued run (Task 3).
2. Two accounts use the same device: neither cached private board state nor a replaced local replay may be attributed to the other account (Tasks 3–4).
3. Many equal scores and fewer than 20 players: estimates must stay finite and within population bounds, never invent rank 21 of 3 (Tasks 1–2).
4. A scene closes during a request: cache may update, but no freed result card or sheet is touched (Tasks 4–6).
5. Cloudflare challenges CI: official-level registration must report failure instead of silently shipping boards for unknown hashes (Task 7).

## Correctness clarifications

These preserve the approved feature intent where the draft formula leaves an edge undefined:

- Existing numerical ranks are competition ranks: `1 + count(points > yours)`. Equal points share rank; timestamp/player id only order their rows. Preserve this distinction.
- A local best newer/higher than `you.points` uses an estimate for that local best, even if the server has an older score. Display the older exact best separately, not as the new run's rank.
- Quantiles cannot determine tie sizes exactly. Treat duplicate quantile runs conservatively using their full percentile interval; label uncertainty rather than divide by zero. Clamp numeric estimated rank to `1..count+1`. The draft's `max(21, ...)` applies only when there are at least 20 entries and the score is strictly below the twentieth score.
- Queue entries reference immutable outbox-owned replay snapshots, not `Progress`'s mutable best-demo path. Ownership and revision are captured at enqueue time.
- Cache public rows/distribution by hash, but scope the private `you` field to player id. Anonymous/offline cache access never adopts another account's exact row.

## File map

- `server/src/scores.ts`: board limit, population and quantiles in the current batch.
- `scripts/rank_estimate.gd`: pure estimation and display-state selection.
- `scripts/community_scores.gd`: durable score outbox and its replay snapshots.
- `scripts/community.gd`: board fetch/cache, scheduler integration, account erasure, score notifications.
- `scenes/leaderboard.gd`: shared top-20 sheet and reusable preview rows.
- `scenes/level.gd`, `scenes/hud.gd`: enqueue new bests and show result standing.
- `scenes/community_level_details.gd`, `scenes/main.gd`: details preview and campaign cached badges.
- `.github/workflows/build.yml`, `server/scripts/register-official.sh`: reliable campaign registration.

---

### Task 1: Board response and quantiles

**Files:** Modify `server/src/scores.ts`; test `server/test/worker/scores.test.ts`.

**Produces:** `{level, rows, you, count: number, quantiles: number[]}`; ascending nearest-rank quantiles at 0,5,…,100%. For sorted length `n`, index `max(0, ceil(k*n/20)-1)` for k=0..20. Empty population gives `[]`.

- [ ] Write tests: empty board → count 0/[]; one player → 21 equal values; 100 unique values → endpoints/min/max and nearest-rank internal values; ties preserve competition ranks; bans excluded; default 20 and explicit limit 100; malformed, zero and >100 limits return 400 after normal auth precedence.
- [ ] Run `cd server && npx vitest run test/worker/scores.test.ts`; observe the missing-field/default-limit failures.
- [ ] Implement aggregate query in the existing `getBoard` batch. Do not fetch all score rows into Worker memory. Keep current authorization and level visibility behavior.
- [ ] Run the focused file and `npm run typecheck`; preserve the one-round-trip endpoint assertion.
- [ ] Commit and push `feat(server): expose board population and score quantiles`.

### Task 2: Rank estimation

**Files:** Create `scripts/rank_estimate.gd`, `tests/test_rank_estimate.gd`.

**Produces:** `class_name RankEstimate extends RefCounted`; static `estimate(points: int, count: int, quantiles: Array, top20_lowest: Variant = null) -> Dictionary` returning `{text: String, badge: String, approximate: bool}`. No-player text is `No ranked runs yet`; potential top entries say `Estimate: would be in the top 20`; other text uses `Estimate: about top P% · ~r of N` with N=count+1. Invalid distributions return empty text/badge (unavailable, not a zero score).

- [ ] Write assertions for zero/one population, endpoints, interpolation, repeated quantiles, all equal, fewer than 20 entries, malformed/nonmonotone arrays and nonfinite values; verify percentile 1..100 and rank never exceeds N.
- [ ] Run `TEST_FILTER=test_rank_estimate GODOT=godot tests/run.sh`; observe RED.
- [ ] Implement interpolation and the correctness clarifications above. Use the same formatter later in every surface.
- [ ] Run that file; PASS without script errors.
- [ ] Commit and push `feat(scores): estimate local standing from score quantiles`.

### Task 3: Durable score posting

**Files:** Create `scripts/community_scores.gd`, `tests/test_community_scores.gd`; modify `scripts/community.gd`, `tests/test_community_sync.gd` and account-erasure tests.

**Produces:** `Community.queue_score(level_id: String, run: Demo) -> String` (empty on accepted enqueue, otherwise error); `Community.score_state(sha256: String) -> Dictionary`; signal `score_result(account: String, sha256: String, revision: int, result: Dictionary)`.

**Internal boundary:** `CommunityScores` owns atomic metadata persistence, replay snapshot files, per-owner/hash revisions, acknowledgement and erasure. It does no HTTP. Community owns nonce/integrity/network operations and adopts results only for the correct owner/generation/revision.

- [ ] Write tests: enqueue survives restart; a higher best replaces an entry; old acknowledgement cannot delete replacement; two owners cannot overwrite each other's replay; success deletes only the acknowledged snapshot; disconnect/5xx/408/429 retains; 400/404 drops with reason; 401 follows existing single re-sign-in rule; account deletion removes metadata/files and late callbacks cannot recreate them.
- [ ] Add tests for integrity refusal: retained, attempted at most once per launch; no score attempt blocks play/vote synchronization forever; exactly one integrity request at a time; fresh nonce/binding on retry. Known identity required; no silent sign-in merely from an offline campaign win.
- [ ] Observe focused RED using `TEST_FILTER=test_community_scores` and sync tests.
- [ ] Implement score flushing within the existing scheduler. Guard platform availability and identity, use `CommunityWire.bound_nonce(nonce,[demo_bytes])`, POST raw demo bytes to `/scores`. Persist before returning enqueue success. Failure to save queue must be visible on the result card, never falsely show queued.
- [ ] Run the affected files once after implementation, then full game suite. Treat strong-integrity refusal separately from transient connection errors; retain the run without a 30-second permanent-denial loop.
- [ ] Commit and push `feat(scores): queue and synchronize account-owned best runs`.

### Task 4: Board client and shared sheet

**Files:** Modify `scripts/community.gd`, create `scenes/leaderboard.gd`, add `tests/test_leaderboard.gd` and client tests.

**Produces:** `Community.board(sha256: String, force := false) -> Dictionary`; `Community.cached_board(sha256: String) -> Dictionary`; signal `board_updated(sha256: String)`; `Leaderboard.open(parent: Node, sha256: String, title: String, local_points := -1) -> Overlay`; `Leaderboard.preview(parent: Control, board: Dictionary, local_points: int) -> void` (top five + own standing).

- [ ] Write tests: valid fetch caches hash and owner; offline uses cached public data with offline marker; account switch clears private `you`; malformed/unsorted quantiles ignored; no desktop requests; concurrent identical reads coalesce; within-hour non-forced reads reuse cache; force refresh bypasses age.
- [ ] Write sheet tests: at most 20 rows with rank/name/points/time, separate highlighted own row, exact rank vs newer-local estimate, loading/error/empty states, keyboard/back focus, close during a held request.
- [ ] Run focused tests to observe RED.
- [ ] Implement an opaque existing `Overlay`, reusing `Style` and `RankEstimate`. Fetch `limit=20`; call score sync on explicit board opening without waiting for it before displaying cached data. A failed refresh never presents stale exact rank as current: mark offline/cached.
- [ ] Run focused tests; render a rich, empty and offline sheet at 1280×720. Redirect Settings/Progress/Community storage before any fixture writes; delete screenshot scripts.
- [ ] Commit and push `feat(boards): fetch, cache and display per-level standings`.

### Task 5: Results and run eligibility

**Files:** Modify `scenes/level.gd`, `scenes/hud.gd`; test `tests/test_flow.gd`, `tests/test_community_scores.gd`, `tests/test_leaderboard.gd`.

**Consumes:** queue_score, score_state, score_result, Leaderboard.open, Community.board.

- [ ] Write tests: only a signed-in Play user's new-best campaign/community win enqueues; training, Test, Publish proof, replay and losses do not. A recording that failed to save never queues a stale prior replay.
- [ ] Test result transitions Posting → exact; offline/pending → estimate; server has an older lower score → newer local best still estimated; scene exits while result arrives → no freed-node access.
- [ ] Observe RED; implement enqueue from `Level.finish` after the winning demo is finalized, without waiting before showing results. Add HUD `board_requested` signal and `set_standing(text: String)` method; show Board only for eligible online-feature builds/levels. Top-five preview and Board action use Task 4.
- [ ] Verify focused tests and result-card screenshots with ad footer reserved.
- [ ] Commit and push `feat(results): post personal bests and show leaderboard standing`.

### Task 6: Community and campaign entry points

**Files:** Modify `scenes/community_level_details.gd`, `scenes/main.gd`; test `tests/test_community_feedback_ui.gd`, `tests/test_flow.gd`, `tests/test_leaderboard.gd`.

- [ ] Write tests: community details contains top-five preview, own row and Full board; feedback and board requests can finish in either order; closing during either is safe; result-origin details still scrolls to You.
- [ ] Write campaign tests: cached exact/estimated badge beside best; no cache → no badge; opening official list refreshes completed levels only, once per hash/hour; training and desktop do not fetch; returning from board preserves campaign selection.
- [ ] Observe focused RED; implement with Task 4 methods. Derive official hash from `LevelFormat.sha256` on the bundled file; never mix standings across file revisions.
- [ ] Run focused tests and full game suite; inspect details/campaign screenshots at 1280×720.
- [ ] Commit and push `feat(menus): show boards in level details and campaign selection`.

### Task 7: Official registration and release readiness

**Files:** Modify `.github/workflows/build.yml`, create `server/scripts/register-official.sh`, add registration tests to server tests; modify `PRIVACY.md`, `README.md`, `server/README.md`.

- [ ] Write registration tests with a stub Wrangler boundary: missing deploy token visibly skips; canonical bytes produce name/hash/release upserts; repeat execution preserves old hashes; bad releases/names/counts fail before network; database ids resolve by name; configured-token failures are nonzero and credentials never appear in arguments/logs.
- [ ] Implement `server/scripts/register-official.sh` with strict release/name/count validation and SQL allowlisting. Reuse authenticated Wrangler D1 execution and the existing deployment credential/scopes, not public `/admin/official`. The owner-approved change supersedes the original fake-curl/WAF-skip proposal: ordinary Bot Fight Mode cannot be skipped by a normal WAF rule.
- [ ] Replace the public curl step and `continue-on-error` with a trusted `master` registration job depending on both `apk` (release creation) and `deploy-server` (database migrations/deployment). Scope credential environment to the step; missing-token skip matches deployment, configured-token failure fails the job.
- [ ] Parent, after review: register the already published current release from its trusted checkout and verify every bundled campaign hash in `official_levels` using a read-only query. Do not write production D1 during implementation; do not alter zone security or add a public host.
- [ ] Document score posting/queues, exact vs estimated ranks, account deletion and cached freshness. Add account-owned automatic new-best campaign/community uploads, sign-in boundaries and public score-distribution aggregates to `PRIVACY.md` and its website body, preserving website metadata and relative Terms link. Commit/push the website branch separately; parent handles PR/publication and live verification before rollout.
- [ ] Run `bash -n`, focused server registration tests plus existing admin registration semantics, and server typecheck once after changes. Commit/push both assigned branches; parent handles full game suite, screenshots, independent review, PRs and deployment.

## Self-review and handoff

Coverage: server/quantiles (1), estimator (2), durable retry/ownership/erasure (3), board cache and shared UI (4), results/posting eligibility (5), details/campaign (6), registration/privacy/release (7). The five Review Focus items have explicit tests in their owning tasks.

Execution order is 1→2→3→4→5→6→7. Shared files have one implementer at a time. Per-task reviewers inspect the actual diff and test evidence; final review covers cross-task integration. Trusted D1 registration supersedes the WAF-change proposal; deployment and live policy/hash verification remain parent-owned rollout actions.
