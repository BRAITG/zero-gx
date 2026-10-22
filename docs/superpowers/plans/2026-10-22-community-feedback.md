# Community Feedback and Difficulty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Android Play users stage-wide likes, per-version reviewed/player difficulty, and duplicate-safe play statistics measured only through each player's first clear.

**Architecture:** D1 owns eligibility and public aggregates. A durable Godot history/outbox records real community attempts and synchronizes app-attested snapshots; the existing `Community` autoload remains the network entry point. Moderator labels set reviewed difficulty without changing gameplay files or proof hashes. Stage details and result-card actions expose feedback.

**Tech Stack:** Godot 4.7.2/GDScript, the existing Kotlin Integrity plugin and JDK 17, Workers/TypeScript, D1/SQLite, Vitest Workers pool, existing GitHub checks and Play deployment.

**Spec:** `docs/superpowers/specs/2026-10-22-community-feedback-design.md`

## Global Constraints

- Android Play only (`Community.available()`); no collection/network calls from desktop, sideload builds, campaign, training, editor/proof flights or demo playback.
- Likes: one per player/stage, eligible after a clear on any version or at least five counted attempts across its versions. Removing an existing like requires no play prerequisite.
- Difficulty: `easy`, `normal`, `hard`, `expert`; one editable/removable vote per player/version. Eligibility is a clear or five counted attempts on that exact version.
- Reviewed difficulty and community votes remain separate. Community uses the upper median; fewer than five voters means no aggregate label. Fewer than ten starters means no derived play ratios, only counts and the insufficient-data note.
- First-clear statistics count starts at or before the earliest reported clear end time, including the winning attempt. Post-clear practice does not contribute. Timestamps are ordering hints, never authentication/score freshness.
- Reports: at most 32 snapshots and 16 KiB per batch, 30 batches/player/minute. Session plus a fresh device-integrity token bound to the exact JSON bytes. Strong integrity and ranked scores are not prerequisites for feedback.
- Routine/on-demand play-report flushes are at least 30 seconds apart; return Pending sync rather than waiting for that interval inside a request. Network/plugin waits stay at most 30 seconds.
- Snapshot revision 1 has null outcome/end; revision 2 has one terminal outcome/end. Starts are immutable; duplicates do not increment counts. A start acknowledgment cannot clear a newer queued finish.
- Persist account-owned history/outbox separately from the session file. No ownerless reports, cross-account reassignment or resurrection after deletion. Collect no failed-run demos or raw inputs for this feature.
- Reviewed labels must not change level JSON, its format version, or demo/hash binding. Optional author suggestions bind a third part; absent suggestions retain the existing two-part submission protocol.
- No new dependencies, comments/Discussions, downvotes, automatic difficulty grading or leaderboard UI.
- All work uses worktrees, is pushed, and lands through PRs after CI. Never run tests/imports in `.worktrees/play` or inject OS input into a game the user may be playing.

## Review Focus

1. A start is acknowledged while its finish is written: retain revision 2; a lost response or duplicate retry counts once (Tasks 1, 5, 6).
2. A silent re-sign-in/account deletion happens during a flush: never post another owner's history or recreate erased state (Tasks 1, 5, 6).
3. An older offline clear arrives after newer attempts: recompute the cutoff and summary, not increment a counter (Tasks 1, 2, 5).
4. Drift/death occurs before first thrust, or Retry/Menu leaves a live run: count the actual run once, excluding tours/previews/replays (Task 7).
5. A moderator bypasses the check, or a webhook repeats: store no invented reviewed label and never change an approved version's hashes or frozen rating (Task 3).

## File and delivery map

| Area | Responsibility |
|---|---|
| `server/src/levels.ts` | The existing visibility guard moved out of `community.ts`, shared by new handlers; no generic query framework. |
| `server/src/plays.ts`, `0004_play_history.sql` | Snapshot validation/storage, guarded upserts, recomputed per-player/version summaries, eligibility. |
| `server/src/feedback.ts`, `core/difficulty.ts`, `0005_feedback.sql` | Feedback reads, difficulty votes, pure difficulty/label rules. Existing like routes stay compatible. |
| Existing submission/checker + levels workflow | Suggested difficulty, merge-time reviewed label and required check. |
| Existing Integrity plugin/client | Correlate and serialize native requests before background reporting exists. |
| `scripts/community_history.gd` | Durable local records, snapshot revisions, desired vote states and account-scoped caches. No HTTP or UI. |
| `scripts/community.gd` | Account identity, batching/sync, eligibility/error handling, feedback APIs and public version metadata cache. |
| `scenes/level.gd` | Real gameplay lifecycle; no new recorder. |
| `scenes/community_level_details.gd` | Reusable details/rating sheet for catalogue and result card. |

Tasks 1–3 form a backend commit prefix. Record its exact SHA after Task 3. Tasks 4–9 follow on the same feature branch, but the new client must not be released before that backend and the live moderator workflow. Implement/review the whole feature before staged delivery in Task 9; do not merge an unreviewed intermediate task merely to start rollout.

For subagent execution, RED/GREEN commands belong to the controller at handoff boundaries. Implementation agents skip mid-flight build/lint/tests/formatters. Each test step is delivered before its production-code step so the controller can observe RED; run the full relevant suite once after the task's code is ready. No permanent source-text/wiring/wording-only tests.

---

### Task 1: App-attested play history and eligibility

**Files**
- Create `server/migrations/0004_play_history.sql`, `server/src/levels.ts`, `server/src/plays.ts`, `server/test/worker/plays.test.ts`.
- Modify `server/src/worker.ts`, `community.ts` (reuse moved visibility guard and sweep the new per-minute rate rows), `session.ts` (`deleteMe`), `server/README.md` manual deletion SQL, and explicit test table cleanup lists.

**Interfaces**
- Consume `requirePlayer`, `readBytes`, `requireIntegrity(request, env, [bodyBytes], "device")`, existing rate-counter patterns and `env.DB.batch`.
- `levels.ts` produces the existing `VISIBLE` predicate and `visibleLevel(env: Env, id: string | undefined) -> Promise<{id: string; latest: number}>`; move the current implementation, migrate consumers, no re-export shim.
- `postPlays(request: Request, env: Env, params: Record<string,string>) -> Promise<Response>` at `POST /plays`.
- `playEligibility(env: Env, player: string, level: string, sha256?: string) -> Promise<{attempts: number; cleared: boolean; eligible: boolean}>`: omitted hash means stage-wide; supplied hash means that version. Retain existing verified-score eligibility without inventing attempt history.

**Fixed wire/data decisions**

`POST /plays` receives `{player_id, attempts: [...]}`. Each snapshot has exactly `id` (32 lowercase random hex characters), `sha256` (64 lowercase hex), `started_ms` (nonnegative safe integer), `revision`, `outcome`, `ended_ms`. Revision 1 requires both final fields null. Revision 2 requires `failed|abandoned|cleared`, and safe-integer `ended_ms >= started_ms`. Times are hints; never substitute them for the server's nonce/session clock.

Create `play_attempts` keyed `(player,id)`, with immutable hash/start, final fields/revision and server `received_ms`; index `(player,sha256,started_ms)`. Create `play_summaries` keyed `(player,sha256)` with counted `attempts` and nullable `first_clear_ms`. Foreign keys to `players` use cascade deletion; hashes reference published `versions.sha256`.

Reply `{acknowledged:[{id,revision}], discarded:[{id,revision,reason}], cleared:[sha256...]}`. Acknowledge the **incoming** compatible revision, not a newer stored revision. Stale revision 1 after revision 2 is acknowledged without reverting the terminal state. Per-record conflicts are discarded as `conflict`; unknown/hidden hashes as `unknown_version`/`hidden_version`. Structural errors (including a repeated id inside one batch) reject the entire batch before any history writes. Owner mismatch is 403 and writes nothing.

- [ ] **Step 1: Write failing route tests.** Define local `seedPlayer`, `seedVersion` and `plays(player, snapshots)` fixtures following existing signed-request helpers. `plays` fetches a nonce and uses `ok:` + `boundNonce(nonce,[JSON bytes])`; it calls the real Worker/D1, not a mocked store. Pin:
  - start → finish → duplicate finish → stale start: `expect(summary).toMatchObject({attempts:1, first_clear_ms:2000})`; stale acknowledgment revision is 1, stored revision stays 2.
  - terminal revision 2 before revision 1 produces the same summary; two concurrent identical reports still count once.
  - four failed attempts: `eligible === false`; fifth: `eligible === true`; a one-attempt clear qualifies immediately.
  - starts A=1000 failed, B=2000 clear at 2500, C=3000 failed: count 2. Delayed D=500 clear at 750 changes count to 1 and cutoff to 750.
  - unknown/hidden version discarded without poisoning a valid record; conflicting immutable/final fields leave the original intact and do not prevent an unrelated valid record being acknowledged.
  - size >16384, >32 records, wrong field types/revisions, duplicate ids, mismatched owner or body changed after nonce binding: 4xx, no history writes.
  - account deletion clears only that player's history. Hold the request body stream after authentication, delete the account, then release the body: no orphan attempt/summary can be inserted.
- [ ] **Step 2: Observe RED.** `cd server && npx vitest run test/worker/plays.test.ts`. New route tests fail on 404 rather than an unrelated setup error.
- [ ] **Step 3: Implement migration and handler.** Guard each upsert on immutable fields, compatible outcome, active owner and visible published version. Use guarded SQL upserts with RETURNING, not a pre-read followed by an unconditional write. Recompute touched summaries from raw attempts in the same D1 batch; do not increment a summary from client totals or `meta.changes`. Earliest clear is ordered by `(ended_ms,id)`; cutoff comparison is `started_ms <= first_clear_ms`. Re-read active ownership before answering if a concurrent deletion invalidated the batch. Add action `plays` to the cron's per-minute rate cleanup; keep existing auth limits unchanged.
- [ ] **Step 4: Verify GREEN.** `cd server && npm run typecheck && npm test`; expected exit 0. Run a local Worker request through the real handler and inspect the returned ack and D1 summary (test verifier local only); never enable it in production.
- [ ] **Step 5: Commit.** `feat(community): record idempotent play history through first clear`.

---

### Task 2: Feedback reads, likes and player difficulty

**Files**
- Create `server/migrations/0005_feedback.sql`, `server/src/core/difficulty.ts`, `server/src/feedback.ts`, `server/test/difficulty.test.ts`, `server/test/worker/feedback.test.ts`.
- Modify `worker.ts`, `community.ts` (`putLike`, `getLevels`), `session.ts`, deletion/runbook SQL and affected worker tests/cleanup lists.

**Interfaces**
- Consume Task 1 visibility, summaries and `playEligibility`.
- `Difficulty = "easy" | "normal" | "hard" | "expert"`; `isDifficulty(value: unknown): value is Difficulty`; `reviewedDifficulty(labels: readonly string[]): Difficulty | null` (exactly one recognized difficulty label); `upperMedianDifficulty(counts: Record<Difficulty,number>): Difficulty | null` (null below 5 voters).
- `getFeedback`, `putDifficulty`, `deleteDifficulty` are standard `(Request,Env,params) -> Promise<Response>` handlers for the spec's routes. Existing like responses remain `{likes}`.
- Feedback JSON:

```typescript
{
  level_id, sha256, reviewed_difficulty: Difficulty | null,
  community_difficulty: {value: Difficulty | null, votes: number},
  stats: {
    players_started, players_cleared, total_attempts,
    clear_rate: number | null, attempts_per_first_clear: number | null,
    median_tries: number | null, unbeaten_5, unbeaten_10, unbeaten_20
  },
  you: {liked, like_eligible, difficulty: Difficulty | null,
        difficulty_eligible, attempts, cleared}
}
```

All counts are numbers, booleans are booleans. Below 10 starters, all ratios and median are null. With at least 10 starters and no clears, `clear_rate` is 0 while `attempts_per_first_clear` and `median_tries` are null. Otherwise `clear_rate` is a fraction 0–1. Numeric median tries is the ordinary median (average two middle counts when even); difficulty median instead uses the harder middle label. No other player's identity/history is returned.

- [ ] **Step 1: Write failing tests.** In Node, pin invalid/zero/multiple moderator labels, 4 voters → null, and five/six-voter medians. In real D1 tests seed 10 player summaries: clearers with attempts `[1,3,5]`, non-clearers `[5,10,20,1,2,3,4]`. Assert:

```typescript
expect(reply.stats).toMatchObject({players_started:10, players_cleared:3,
  total_attempts:54, clear_rate:0.3, attempts_per_first_clear:18,
  median_tries:3, unbeaten_5:3, unbeaten_10:2, unbeaten_20:1});
```

  Also pin: 4 attempts cannot vote but 5 can; a clear qualifies; other-version history qualifies a stage like but not this version's difficulty; old verified scores qualify without fabricating stats; PUT replaces one vote, DELETE needs no new play. Five votes `[easy,normal,normal,hard,expert]` → normal; adding expert → hard. Ban/delete a contributor: immediately exclude them and reapply small-sample thresholds. Reject wrong level/hash pairing, invalid labels and hidden/unpublished targets. Concurrent deletion cannot leave a new vote/like orphan.
- [ ] **Step 2: Observe RED.** `cd server && npx vitest run test/difficulty.test.ts test/worker/feedback.test.ts`; absent handlers/new eligibility must fail.
- [ ] **Step 3: Implement.** Migration adds nullable checked `versions.reviewed_difficulty` and `difficulty_votes` keyed `(player,sha256)` with owner/version foreign keys. Reuse the fixed difficulty map (Record, not a static Set). Server enforces eligibility in writes; apply active-owner/visibility guards atomically. Aggregate summaries/vote counts in SQL, filtering banned/deleted players at query time. Return only the caller's state. Add reviewed difficulty, community difficulty/count to level-list rows without computing or leaking individual histories. Update existing exact-row tests, not weaker subset assertions that omit new fields. Add new rows to `DELETE /me` and manual deletion guidance.
- [ ] **Step 4: Verify GREEN.** `cd server && npm run typecheck && npm test`, exit 0. Exercise a local report → like → rating → feedback sequence against local D1; show eligibility and aggregates change.
- [ ] **Step 5: Commit.** `feat(community): expose likes and version difficulty feedback`.

---

### Task 3: Author suggestion and moderator-reviewed difficulty

**Files**
- Modify `server/src/submissions.ts`, `server/src/cli.ts`, `server/README.md`, `server/test/cli.test.ts`, `server/test/worker/submissions.test.ts`.
- Modify `levels-repo/.github/workflows/check.yml` and `levels-repo/README.md`.
- Prepare the matching workflow/README changes in a separate worktree/branch of **BRAITG/zero-gx-levels**; do not publish that workflow before this checker reaches zero-gx master.
- Create `fixtures/suggested_difficulty_nonce.json` and its server-side fixture test for the optional third bound part; client test comes in Task 6.

**Interfaces**
- Consume Task 2 `Difficulty`, `isDifficulty`, `reviewedDifficulty` and the nullable version column.
- Extend `checkPr(root:string, base:string, head:string, reviewLabels?: readonly string[]) -> Promise<Result>`. Undefined keeps local content-only checking; supplied labels require exactly one for a level submission. Hidden.txt-only maintenance is exempt.
- CLI accepts `check-pr <root> <base> <head> [--event <github-event-json>]`; with `--event`, validate/extract `pull_request.labels[].name` without shell interpolation or executing PR code. Invalid event input exits nonzero as a sentence.
- Optional multipart `suggested_difficulty`: **presence**, not truthiness, chooses three-part binding. Present empty/invalid strings fail. Absent remains `[level,demo]`; present is `[level,demo,field UTF-8]`.

- [ ] **Step 1: Write failing tests.** Existing `repo/newLevel/problems` CLI fixtures remain content-only. Add `checkPr(...,[])` and two difficulty labels → failure; exactly `difficulty:hard` plus unrelated labels → passes; hidden.txt-only PR passes without a difficulty label. Execute the CLI with an event file containing hostile quote/newline text: it must not execute it. Submission tests cover present/absent/empty suggestion, third-part tampering rejected by integrity, author hint in PR body, and no hint-derived authoritative label. Merge webhook tests assert version difficulty is saved once with the real merged file hash; repeated/reordered delivery cannot rewrite it. If an admin bypasses the check with zero/multiple labels, publish as **Not rated** (null), never invent a rating or poison webhook delivery. Existing versions stay null.
- [ ] **Step 2: Observe RED.** `cd server && npx vitest run test/cli.test.ts test/worker/submissions.test.ts`; the label and third-part assertions fail.
- [ ] **Step 3: Implement.** Use `form.has/get` directly for suggestion (the old `field` helper treats empty as absent). Put the hint in the PR body only; no new level/meta file key. Read labels from the signed merge payload, validate them through the pure helper and bind the reviewed value in the same guarded version insert as approval. Include the nullable value in index metadata. Workflow keeps the required job name `check`, read-only permissions, fixed tool checkout from zero-gx master, and quoted refs; add `labeled`/`unlabeled` to `opened`/`synchronize`/`reopened`, and pass `--event "$GITHUB_EVENT_PATH"`. Do not import the Node CLI into Worker modules.
- [ ] **Step 4: Verify GREEN.** `cd server && npm run typecheck && npm test`; validate YAML/actionlint where available. Run the actual CLI on a temporary valid submission repo with zero and one review labels and observe failure/pass without changing level or proof bytes.
- [ ] **Step 5: Commit and record the backend prefix SHA.** `feat(review): require moderator difficulty without changing proof hashes`. Do not merge/release it yet; Task 9 stages delivery after the full review.

---

### Task 4: Correlated, serialized and bounded Integrity calls

**Files**
- Modify `android/plugins/integrity/src/main/java/dev/braitg/zerogx/integrity/IntegrityPlugin.kt`, both committed AARs under `addons/zero_gx_integrity/bin/`, `scripts/community_android.gd`, `tests/test_community_android.gd` and existing fake singleton fixtures.

**Interfaces**
- Preserve public `CommunityPlatform.integrity(nonce:String) -> Dictionary` and its `{token}` / `{error}` result.
- Native cutover: `request(nonce:String, cloudProjectNumber:Long, requestId:Long)` emits one `integrity_result(requestId:Long, token:String, error:String)` signal. Remove old integrity_token/integrity_failed signals and migrate every caller/fake; no shim or vendor-plugin edits.
- One native Integrity request at a time on the long-lived Community host. Results with another request id cannot settle the current request; a timeout releases the queue and disconnects its listener.

- [ ] **Step 1: Write failing tests** with a fake native singleton under `tests/support/` that can hold/release results. Two callers with different nonces serialize, each receives its own result; timeout then a late old result cannot settle the next request. Error returns the existing short player sentence, never a raw token/key. Register listeners before invoking native/PGS methods; bound the initial PGS authentication wait as well as code/integrity waits to 30 s. Keep the existing sign-in single-flight behaviour and other Race tests.
- [ ] **Step 2: Observe RED.** `TEST_FILTER=test_community_android GODOT=godot tests/run.sh` fails on the new correlation/timeout behaviours.
- [ ] **Step 3: Implement native/client cutover** and update all signal fixtures. Keep classic nonce semantics, cloud project, device/app requirements and error redaction unchanged. Do not add retry loops or extend timeouts.
- [ ] **Step 4: Build and verify once.** JDK 17 is already installed: from `android/plugins/integrity`, run `JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ./gradlew assembleRelease assembleDebug`; copy both AARs using the existing build.gradle instructions. Run the full Godot suite, export the Android Play bundle and debug APK with JDK 17, and inspect classes/manifest as the existing CI does. On an emulator/device, exercise the real signal bridge (an expected Play error still proves the request id/error round-trip); report the device limit. No setup reinstall or SDK/version bumps.
- [ ] **Step 5: Commit.** `fix(android): correlate and serialize integrity requests for background sync`.

---

### Task 5: Durable account-owned history and vote outbox

**Files**
- Create `scripts/community_history.gd` (`class_name CommunityHistory extends RefCounted`) and `tests/test_community_history.gd`.
- Modify `tests/run_tests.gd` only to redirect/clean the new path and reset state when Task 6 installs it.

**Interfaces**
- No HTTP, timers, UI or autoload lookup in this module. `var path := "user://community_history.json"`; native Dictionary/Array/JSON values, versioned file format `zero-gx-community-history`, version 1.
- `load_file() -> Error`; `begin(owner:String, level:String, sha:String, started_ms:int) -> String` (32 random hex id, empty on failure/already known cleared); `finish(owner:String,id:String,outcome:String,ended_ms:int) -> Error`.
- `owner_for_attempt(id:String) -> String` returns its persisted owner, or empty if absent/deleted. Task 6 resolves finishes through this association, never the current session owner.
- `batch(owner:String) -> Array[Dictionary]` (latest pending snapshots, max 32); `acknowledge(owner:String, reply:Dictionary) -> Error`; `confirm_progress(owner:String,level:String,sha:String,you:Dictionary) -> Error`; `progress(owner:String,level:String,sha:String) -> Dictionary`.
- `queue_like(owner:String,level:String,value:bool) -> Error`; `queue_difficulty(owner:String,level:String,sha:String,value:String) -> Error` (empty removes); `pending_votes(owner:String) -> Array[Dictionary]`; `ack_vote(owner:String,key:String,revision:int) -> Error`; `erase_owner(owner:String) -> Error`.
- Persist owner/version metadata so stage-wide eligibility can be assessed locally without scanning all downloaded files. Queued votes have stable key and increasing revision; only the latest desired value is sent. Keep account-scoped cached feedback separate from public downloaded level metadata.

- [ ] **Step 1: Write failing file-backed tests.** Reload after start/finish preserves the same id and revision. Starting again after a locally known clear yields no new record. A batch captures revision 1, finish writes revision 2, then ack1 arrives: `batch(owner)[0]` still has the original id and revision 2. Ack2 clears pending state, not history. Lost-response resend uses the same id. Conflicting finish does not overwrite the first outcome. A stale vote acknowledgment cannot remove a newer desired state. Owner B sees none of A's queued data; erasing A leaves B intact; a late ack for erased A does not recreate A. Unfinished starts survive restart without becoming clears. Corrupt file and failed saves preserve existing bytes and disable counting rather than silently replacing history with empty data.
- [ ] **Step 2: Observe RED.** `TEST_FILTER=test_community_history GODOT=godot tests/run.sh` fails because the new behaviour is absent.
- [ ] **Step 3: Implement.** Persist before returning a new attempt id and before accepting a terminal change. Write a temporary file, flush/close/check errors and atomically rename before committing in-memory state; keep the old file/state on failure. Validate loaded JSON once. Never derive ownership from whichever account signs in later. Keep pending and acknowledged history distinct. Use one compact JSON state file initially, with a `shortcut:` comment that measured save stalls/history growth are the point to move to per-version files; do not add a storage dependency now. First-clear ordering matches Task 1. Existing local Progress bests are not history.
- [ ] **Step 4: Verify GREEN.** Full Godot suite passes. Throwaway script: begin → capture batch → finish → ack old batch → reload, and print the still-pending revision 2 from disk. Remove the script afterwards.
- [ ] **Step 5: Commit.** `feat(community): persist account-scoped play history and feedback outbox`.

---

### Task 6: Account-aware feedback network and synchronization

**Files**
- Modify `scripts/community.gd`, `community_transport.gd` (add PUT), `tests/run_tests.gd`, `tests/support/fake_platform.gd`, `fake_transport.gd`, `tests/test_community.gd`.
- Create `tests/test_community_sync.gd`.

**Interfaces**
- Consume Tasks 1–5; preserve current public functions and the one-401-retry policy.
- Add `Community.player_id() -> String`, persisted only from a validated `/session` player response. New `history_path` is independent of session_path and redirected in the test runner.
- Add `Community.activate_feedback() -> void` (explicit community entry this launch); `record_play_start(sha:String) -> String`; `record_play_finish(id:String,outcome:String) -> void`; `play_progress(sha:String) -> Dictionary` with local/confirmed attempts, clear state, pending-sync and `can_offer_rating` for UI only.
- Add coroutines `feedback(level:String,sha:String) -> Dictionary`, `sync_feedback() -> Dictionary` (`{error:String,pending:bool}`), `set_like(level:String,value:bool) -> Dictionary` and `set_difficulty(level:String,sha:String,value:String) -> Dictionary` with the same error/pending result.
- `feedback` returns Task 2's payload plus `offline`; when unavailable/no cache, `{error,offline}`. `pending_feedback(level:String,sha:String) -> Dictionary` exposes only this owner's queued like/difficulty selections. Public aggregates are never recomputed by the client.
- `level_info(sha:String) -> Dictionary` reads validated public `<sha>.meta.json` saved alongside downloads, including cache hits. It supplies stable level id/version to runtime result-card feedback, whose stage id contains only the hash.
- Extend `submit(id:String,suggested_difficulty := "") -> String` and `_submission` with Task 3's optional text field/third nonce part; normal UI supplies a choice, absent remains valid for old/direct callers.

- [ ] **Step 1: Write failing integration tests** using disk-backed history plus the existing fakes (extend per-request holding/account identity only as needed):
  - legacy valid token without stored player id refreshes sign-in at the next online Community entry; offline cached play still works and no ownerless report is created.
  - no request merely from booting the campaign/menu; `activate_feedback` starts eligibility for scheduling, not a new play by itself.
  - capture start revision 1 in a held upload, finish locally, release ack1: revision 2 remains for the next batch; server-success/lost-response retry sends the same id.
  - rapid retries coalesce into one batch, max 32 and 16384 bytes; early sync returns pending immediately instead of waiting 30 s; timers do not outlive test reset.
  - a 401 silently signs in once with a fresh nonce. If the player changed, old-owner bytes are never posted; account deletion during a held flush cannot recreate old history/cache.
  - start under A, switch to B, then finish A's scene: only A's existing record changes; it is never sent with B's token. Finishing an erased attempt is a no-op.
  - offline like/rating keeps latest desired state; plays sync before vote. 0/5xx/429 retain it (429 defers until a later flush, no immediate loop); a permanent 4xx refusal removes that change, restores confirmed state and shows the sentence. A stale response cannot replace a newer choice.
  - exact report bytes are the bytes bound by `CommunityWire.bound_nonce`; new three-part submission fixture matches the server, changed suggestion fails. No token goes to jsDelivr.
- [ ] **Step 2: Observe RED.** `TEST_FILTER=test_community_sync GODOT=godot tests/run.sh`.
- [ ] **Step 3: Implement.** Reuse `_authed`, `_nonce`, CommunityWire and Task 4 platform calls, not a second HTTP client. Preserve status codes internally to distinguish permanent refusal from connection/5xx/429 failures. At most one flush and one native integrity request at a time. Delay only future scheduling, never hold an HTTP connection for the cadence. Build reports fresh for a 401 retry and recheck immutable owner against the new session before nonce/signing/network. Accept acknowledgments only for the sent owner/revisions. Keep retryable state on disk failure or network error. Clear this account's history, votes and private feedback cache on deletion, but keep downloaded public levels. Never initialize/flush background reporting at startup before Community/Submit is explicitly entered this launch.
- [ ] **Step 4: Verify GREEN.** Full Godot suite; local Worker smoke with the test verifier drives client report → feedback → like → difficulty vote and shows expected database/public values. Desktop run makes no calls. Use a throwaway worktree/process, no user's live game window or `.worktrees/play`.
- [ ] **Step 5: Commit.** `feat(community): synchronize play history and feedback without cross-account leakage`.

---

### Task 7: Real community gameplay lifecycle

**Files**
- Modify `scenes/level.gd`, `scenes/main.gd`/`community_screen.gd` only for explicit feedback activation/legacy identity refresh, and create `tests/test_community_play_history.gd`.

**Interfaces**
- Consume Task 6 `record_play_start`, `record_play_finish`, `play_progress` and `level_info`.
- Add a per-Level stored attempt id and captured owner context (or let History retain that immutable association); never address an end by a mutable singleton's "current attempt".
- Produce `result.can_rate` for eligible community results and a `rate_requested` connection point used by Task 8. Do not change published proof/normal Test intent or return paths.

- [ ] **Step 1: Write failing lifecycle tests.** A community ship drifting/dying before first thrust still starts/finishes one attempt. Tour/paused intro creates none until live play; pause/resume/background does not create another. Retry abandons a live old attempt and starts one new id, whatever scene exit/ready order occurs. Menu/Android Back abandons once; win/death same-frame still has one terminal result. A clear is persisted before the result card; later practice is excluded; prior local best alone does not fabricate a historical first clear. Campaign/training/desktop/editor/Publish proof/DemoViewer and disabled previews create no report. Simulated restart with persisted unfinished start retains one counted start.
- [ ] **Step 2: Observe RED.** `TEST_FILTER=test_community_play_history GODOT=godot tests/run.sh`.
- [ ] **Step 3: Implement.** Start after the tour branch ends (`_end_tour`) or when the no-tour run becomes live; never use first thrust/flight_time as the sole start, since physics may already be running. If the tree is paused, defer to its first live tick. Persist finish before `hud.show_result`. Guard abandonment on exit/leave with a nonempty attempt id and `not _done`, handling both explicit Retry/Menu/Back and scene teardown without two finishes. Do not attempt a network call from `_exit_tree` or delay quitting; persistence is enough. Write failure never prevents offline gameplay and never grants unconfirmed server eligibility.
- [ ] **Step 4: Verify GREEN.** Full Godot suite. Run a local real game scene in a throwaway smoke process: start, retry, fail, clear, replay; inspect isolated history on disk and verify counts/ids, not just the HUD text. No synthetic OS input in Andre's game window.
- [ ] **Step 5: Commit.** `feat(community): count real attempts only through the first clear`.

---

### Task 8: Stage details, voting and author difficulty UI

**Files**
- Create `scenes/community_level_details.gd`, `tests/test_community_feedback_ui.gd`.
- Modify `community_screen.gd`, `hud.gd`, `level.gd`, `my_levels_screen.gd`, README and relevant consumer-visible tests.

**Interfaces**
- Consume Tasks 2/6 feedback shapes and pending state, Task 7 `result.can_rate`, existing `Overlay`/`Style.busy`/focus patterns.
- `CommunityLevelDetails.open(parent:Node,row:Dictionary,on_play := Callable()) -> Overlay` is the one reusable details/rating surface. An absent Play callback is used on an ended run; catalogue supplies its existing Play action.
- Hud adds `signal rate_requested` and a community-only **Rate level** result button; normal result buttons remain unchanged.

- [ ] **Step 1: Write failing UI tests.** List offers Details and compact difficulty/counts. Sheet shows independent Reviewed and Community values, 4-voter/9-starter insufficient states, proper no-clear/null values, and only this player's selections/progress. Four attempts leave voting unavailable; fifth or clear makes it discoverable, including a fifth failed result. Stage-wide experience cannot unlock another version's difficulty. Pending sync stays visibly pending, failure restores state, stale answers do not clobber a newer selection, account switch cannot show the prior owner's private feedback. Check Back/keyboard/pad focus and a sheet opened within the HUD's 0.4 s result-focus delay (the delayed result focus must not steal it). Publish confirmation requires an explicit Suggested difficulty; proof reuse/new runs still upload only after Submit for review, with the same level/demo bytes. All feedback remains absent on desktop.
- [ ] **Step 2: Observe RED.** `TEST_FILTER=test_community_feedback_ui GODOT=godot tests/run.sh`.
- [ ] **Step 3: Implement.** Use the house Overlay/cards, four labelled choices, Like toggle and sample counts. Keep row density readable; no row of four difficulty buttons in the list. Raw data and ratio labels match the spec, including finishers-only median and upper-median difficulty. Details/caches are keyed by version hash and account where appropriate. A syncing vote returns promptly with Pending sync. Result-card Rate opens this same sheet; preserve focus containment. Suggested difficulty is separate metadata, never an edit to draft JSON. Do not add comments, sorting settings or an automatic grade.
- [ ] **Step 4: Verify GREEN.** Full Godot suite. Render actual catalogue/details/result/publish sheets with isolated fake data at the game's 1280×720 viewport and scaled desktop window, then inspect images and exercise Back/selection/pending/error states. Verify on Android/emulator where available and report any physical-device gap; do not claim a Mac screenshot proves phone behaviour.
- [ ] **Step 5: Commit.** `feat(community): show stage feedback and reviewed difficulty`.

---

### Task 9: Privacy, staged delivery and live acceptance

**Files**
- Modify `PRIVACY.md`, `docs/release/google-play.md`, `server/README.md`, `levels-repo/README.md` and setup/review guidance whose actual paths changed.
- Same text in **BRAITG/braitg.github.io** `zero-gx/privacy.md`, preserving front matter, in its own worktree/PR.
- Live **BRAITG/zero-gx-levels** workflow/README from Task 3, in its own worktree/PR.

**Interfaces**
- Consume all prior tasks and the recorded backend-prefix SHA; every named acceptance item in the spec is required, not an optional phone-only substitute for automated tests.

- [ ] **Step 1: Update disclosures before collection ships.** Explain account-linked community starts, outcomes and difficulty votes; aggregate-only public statistics; no failed-input/demo collection for these reports; account-lifetime retention and deletion. Replace blanket no-analytics with precise no-third-party-analytics/cross-service-tracking wording. Data safety guidance adds these activities and the Analytics assessment purpose (including linked IDs where applicable), without inventing Google's SDK disclosures. Add new owned tables to manual erasure SQL. State known device-clock ordering limits.
- [ ] **Step 2: Whole-feature gate before any rollout.** Run `GODOT=godot tests/run.sh`, `cd server && npm run typecheck && npm test`, and `npm audit` against the committed lockfile (triage by reachability, no forced upgrades). Export Android and all desktop presets, inspect native plugin/permission/feature checks, and run local end-to-end feedback smoke. Request the fresh whole-feature review with both the app/server diff and prepared live-workflow diff; resolve blocking findings. These are executable release gates, not claims made by this plan.
- [ ] **Step 3: Deliver backend first.** Make a branch at the exact Task 3 prefix SHA and open a zero-gx PR, await CI, merge. Verify D1 migrations/server deploy before releasing new client code. Existing clients must still sign in, browse and submit without suggested difficulty. Never merge or reset the user's dirty main checkout.
- [ ] **Step 4: Deliver moderator checks.** Provision the four difficulty labels and merge the prepared levels-repo maintenance PR only after its zero-gx checker is on master. The existing level-submission validator rejects workflow/README edits; use the repository's documented **PR-only admin maintenance bypass** after independent workflow/CLI/security review if needed. Do not weaken the ruleset, expand the submission file allowlist or bypass checks on player submissions. If that admin operation requires Andre, name that exact step rather than claiming it passed the submission pipeline. Prove a real temporary submission PR fails without a label, passes with exactly one, and still checks proof bytes; close the temporary PR without publishing test content.
- [ ] **Step 5: Publish the privacy text, then client.** Merge/publish the site policy and verify the live URL carries the new text. Rebase the remaining client/docs commits on the merged backend, open the client PR, await CI and merge. Verify the master Play internal-testing upload. Every branch/worktree remains pushed until its PR is merged; remove only this plan's owned worktrees afterwards.
- [ ] **Step 6: Real Play-device proof (Andre).** On the Play-installed build, fail/retry a community version five times, rate difficulty and toggle Like; confirm public/player state on another session. Clear it, replay and verify learning stats stop. Exercise offline queue/restart/reconnect and a new labelled submission version; its Reviewed difficulty must differ independently from player votes and its level/demo hashes must be unchanged by the label. Confirm account deletion removes the new history/votes and that desktop has no collection. Record actual evidence and any unavailable device prerequisite; no fabricated completion.

**Completion:** likes, reviewed/player difficulty, real first-clear history, offline sync, deletion/privacy and the live moderator checks work together. Comments and automatic skill-adjusted difficulty remain excluded exactly as in the approved spec.
