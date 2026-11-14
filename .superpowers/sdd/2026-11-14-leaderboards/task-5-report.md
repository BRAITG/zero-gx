# Task 5 — Results and run eligibility

## Status and scope

Implemented in the linked leaderboards worktree on `feat/leaderboards`, without dependencies. Read Task 5 brief, plan Global Constraints/Correctness clarifications, spec Posting runs/results, and Task 4 report's API section. Codegraph has no index for this worktree; GDScript LSP reference lookup returned `No language server found for this action`.

Touched `scenes/level.gd`, `scenes/hud.gd`, the approved minimal shared `scenes/leaderboard.gd` extension, `tests/test_flow.gd`, and `tests/test_leaderboard.gd`. Score queue/network/security implementations are unchanged.

## Behavior

- `Level.finish` finalizes the recorder before scoring, saving or queuing. Only a signed-in known-owner Play campaign/community NEW BEST win queues its finalized in-memory `Demo`; training, editor Test/Publish, drafts, disabled replay previews, losses and non-bests do not. Desktop/non-Play results make no requests; unknown/signed-out results never sign in automatically.
- Best-demo persistence is independent: the durable outbox owns its own immutable snapshot. A valid finalized in-memory recording still queues if saving the Progress best-demo fails. An invalid/truncated new recording shows its error and never falls back to a previous Progress replay.
- The result card appears without awaiting network. It shows Posting, retained/offline pending plus estimate, durable-enqueue/drop errors, and exact stored-best rank after success. A POST's `rank`/`points`, including `best: false`, belong to the remote stored best: a different higher local best remains estimated and the exact remote score is labelled separately.
- Result callbacks match live level/hash, captured owner, revision, current score revision and result generation. Account switches immediately discard prior private status. A result closing during held score/board requests is safe. Successful posting serializes a forced board refresh after any older held board read; that old read cannot regress the POST standing.
- The shared top-five/own preview sits beside the unchanged animated score breakdown and medals, above a horizontal row of the existing actions plus Board. The frame reserves Monetization's footer and grows about its center when asynchronous content changes. Preview typography/spacing is compact; full-sheet typography is unchanged. Board opens the existing full sheet and restores focus on close.

## API for Task 6

```gdscript
static Leaderboard.standing(board: Dictionary, local_points: int) -> String
# Existing Leaderboard.open and preview signatures remain unchanged.

signal Hud.board_requested
Hud.set_standing(text: String) -> void
Hud.set_board(board: Dictionary, local_points: int) -> void
# Hud.show_result result dictionary adds optional can_board: bool (wins only).
```

`standing` is presentation-only and performs no network I/O. It uses the existing `RankEstimate` interpolation, known lower-own-score rank bound, current-owner validation and cached/offline suffix. Matching local/remote points return `Your ranked best · Rank #R [of N] [(cached)]`; different local points return the estimate (or `Estimate unavailable`). `local_points = -1` selects the exact remote-best label, or `Not played yet`. The `board`/`you`/`owner` shape is the Task 4 API. Consumers should not duplicate interpolation or treat estimated local points as a ranked row. `preview` uses this same formatter and still performs no reads.

## Covering checks

Final focused commands, all exited 0 with no script errors:

- `TEST_FILTER=test_flow GODOT=godot tests/run.sh` — **54 passed, 0 failed**.
- `TEST_FILTER=test_community_scores GODOT=godot tests/run.sh` — **6 passed, 0 failed**.
- `TEST_FILTER=test_leaderboard GODOT=godot tests/run.sh` — **13 passed, 0 failed**.

New flow coverage includes the eligibility matrix, recorder final event, best-demo write failure with durable own copy, invalid new recording versus prior replay, immediate held Posting, pending/error/exact states, `best:false` remote score separation, wrong owner/hash/revision and superseding same-hash revision, late held response after owner switch/close, post-upload refresh after a held board, Board focus restoration, and result/action/footer geometry. Shared formatter coverage checks exact/cached labels, the own-rank bound, missing distribution and foreign-owner rejection. Existing immutable queue tests were run unchanged.

Tests were written before implementation. A behavioral RED run was not taken because the assignment prohibited mid-flight checks. Initial covering runs exposed and corrected a test's inferred Variant boolean, two test fixture/expectation mistakes (an empty blocking directory was removable; a held first board has no known population), and real asynchronous result-panel horizontal growth outside its frame. The final logs above supersede those failed attempts. Normal Camera2D interpolation warnings and shutdown ObjectDB/resource-in-use warnings remain in logs (flow: 18 objects / 2 resources; queue and board checks: 2 objects each); no claim that these checks are warning-free.

All test/render Settings, Progress, MyLevels, Community session/history/download paths were redirected before writes. Result tests derive immutable score files from their isolated history path.

## PNG evidence

Real Godot 4.7.2 OpenGL/Metal renderer at **1280×720**, with fake transport/device bridge and the real Monetization footer/chrome, **66 logical pixels reserved**. Visually inspected all three final images: full top five and own panel, score/medals, six actions and Remove ads footer fit. Result panel: `(90, 6.5)`, size `(1100, 641)`, ending above the footer at y=654.

- `task-5-posting.png` — held upload, local estimate and separate old exact best.
- `task-5-exact.png` — matching uploaded best, exact rank and updated own preview.
- `task-5-offline.png` — retained pending, No connection, cached/offline labels and newer local-best estimate.
- `task-5-render-check.log` records renderer, PNG dimensions, actual total text and geometry. Temporary render script and scene were deleted.

## Concerns / intentionally not checked

No full game suite, server suite, APK/build, Android/native banner rendering, live Play Integrity or production endpoint checks were run. Those remain integration/release validation, not simulated proof. The preview has a bounded scroll host for unusually long/error-rich content; the inspected 1280×720 cases display the full top-five and own panel without clipping. No score arithmetic, verification, nonce binding, automatic sign-in policy, queue persistence or retry behavior was changed.
