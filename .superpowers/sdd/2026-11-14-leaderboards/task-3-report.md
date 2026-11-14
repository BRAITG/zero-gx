# Task 3 — Durable account-owned score posting

## Status and scope

Implemented only Task 3 on `feat/leaderboards` in the linked leaderboards worktree. No dependencies, score-calculation/server changes, board UI, enqueue eligibility callers, PR, build or release. Task 5 still decides when a finalized new best is eligible to enqueue.

Read Task 3 brief, plan Global Constraints/Correctness clarifications/Task 3, spec Posting runs, and existing history/sync/erasure/native integrity patterns. GDScript LSP reference lookup reported `No language server found for this action`; Codegraph is not indexed for this worktree (as supplied in the assignment).

## Changes

- `scripts/community_scores.gd`: HTTP-free durable outbox with strict metadata loading, atomic temp/flush/checked-rename writes, per-owner/hash monotonic revisions, checksummed immutable replay snapshots, replacement, revision-matched settlement, owner erasure, and cleanup of unreferenced snapshots.
- `scripts/community.gd`: exact public queue/state/signal interfaces; snapshot validation; existing scheduler, `_queued`, `_runnable`, `_flush`, reset/defaults and erasure integration; raw `/scores` uploads; nonce-bound integrity proofs; single existing 401 re-sign-in retry; owner/generation/revision guards.
- `tests/test_community_scores.gd`: six isolated persistence tests, including real deterministic write failures (occupied temporary filename), snapshot-write failure, corruption, restart, replacement, monotonic acknowledgments, owner isolation and erasure.
- `tests/test_community_sync.gd`: fifteen new end-to-end score tests against the existing fake transport/platform and real isolated disk state, including delayed old uploads, lost responses, write failures, identity switches, denied integrity/banned players, retry cadence, and deletion during in-flight HTTP plus metadata/unlink erasure failures.
- New Godot UID files accompany both new scripts.

## API shape

```gdscript
Community.queue_score(level_id: String, run: Demo) -> String
Community.score_state(sha256: String) -> Dictionary
signal score_result(account: String, sha256: String, revision: int, result: Dictionary)
```

`queue_score` returns `""` only after snapshot and metadata persistence succeed; otherwise a user-facing sentence. It requires Play availability and an already-known account, and refuses null/empty/truncated runs, missing/invalid/default hashes, a final event other than a goal at the final frame, and oversized/nondecodable encodings. It never accesses `Progress`'s mutable demo path. Snapshot bytes are copied from the finalized `Demo.encode()` at enqueue and checksummed before upload. The server remains authoritative for the full replay/level validation.

`score_state` returns `{}` when unavailable/unknown for the current account; otherwise `{account, sha256, revision, state, error}`, plus `status` after an attempt. States are `queued`, `posting`, `posted`, `dropped`. Successful answers preserve `rank`, `points`, `best`; denial adds `denied: true`. Signals name the uploaded revision even when a newer enqueue arrived meanwhile. Consumers must match both owner and revision. An older answer never replaces a newer revision's state. Posted/dropped results are memory-only; later board reads own durable confirmed standings.

Internal `CommunityScores`: `path`, `load_file`, `enqueue(owner, level, sha, bytes)`, `entry`, `entries`, `revision`, `snapshot`, `settle(owner, sha, revision)`, `erase_owner`, static `replay_dir(path)`. Score metadata is separate from play history at `history_path.get_basename() + "_scores.json"`; snapshots live in the adjacent `_replays/` directory. This derives from the established test redirect, so neither test file can touch real game data.

## Scheduling and failures

- Known-owner score enqueue may initiate **score-only** background synchronization independently of feedback activation (agreed with Main). Pending plays/votes remain untouched until their existing explicit feedback activation/action. Unknown-owner campaign wins cannot enqueue or trigger implicit sign-in. Explicit `sync_feedback` may identify an unknown player as before; known-owner reauthentication uses the existing owner-constrained `_authed` flow.
- When feedback is active, plays/votes run before scores. One score attempt per 30-second gap; an attempt in flight shares the existing flush lock. The platform's existing `CommunityAndroid.integrity` serialization is reused unchanged, with `CommunityWire.bound_nonce(nonce, [demo_bytes])`; each retry rebuilds nonce and proof, including 401 retry.
- Disconnect/5xx/408/429 and malformed success retain the run. Permanent 400/404 (and other permanent 4xx except 403) drop with the server's reason, never deleting local bests. Server 403 (integrity refusal or ban) and native `INTEGRITY_FAILED` retain but suppress score attempts for that owner until a new launch; denied runs stay pending but are not runnable and do not start a denial timer loop. Native silence remains transient.
- Metadata commits precede deletion of unreachable snapshots. Failed enqueue/settle/erase metadata writes preserve the previous queue and referenced bytes. If erasure metadata committed but unlink/listing failed, the account remains durably owed erasure and cannot show/queue/send its data; a later explicit community action retries cleanup. No rollback can resurrect erased metadata. Deletion of another owner's referenced snapshots never occurs.
- Late responses after account deletion/reset do not write state, emit score results, trigger sign-in, or recreate files; account switches neither send another owner's snapshot with the new token nor adopt the old owner's rank.

## Checks run once after implementation

Commands, from the linked worktree:

```sh
TEST_FILTER=test_community_scores GODOT=godot tests/run.sh
TEST_FILTER=test_community_sync GODOT=godot tests/run.sh
```

- Scores: **6 passed, 0 failed**, exit 0.
- Sync: **57 passed, 0 failed** (42 existing + 15 score tests), exit 0.
- No script errors logged. Both runs logged `WARNING: 2 ObjectDB instances were leaked at exit`; no follow-up broad investigation performed.
- Captured full output: `task-3-scores-check.log`, `task-3-sync-check.log` in this directory.
- Per the latest direct assignment, no mid-flight RED/check runs and no full suite, build, lint or formatter run. Parent owns final integration/full-suite verification.

## Integration notes and concerns

- Task 5 must enforce campaign/community new-best eligibility (not training, editor, playback or losses), enqueue only after recorder finalization, retain the enqueue error for the result card, and match score-result owner/revision before showing a rank. No retroactive best uploads were added.
- `/scores` reports `best: false` when an equal/higher score is already stored; its rank is the server's stored-best rank. Downstream board/result presentation must preserve that distinction rather than treating a higher existing remote best as verification of a lower local run.
- No real Play hardware/native integrity or live server/network requests were exercised. New overlap test proves shared Community flush work; existing native serialization code was reused, not reimplemented or modified.
