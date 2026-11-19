# PR landing

Scope: reviewing and merging a pull request in this repository. Load when: opening a PR, reviewing it, applying review
findings, or merging it.

- **Owner:** repository owner. **Last verified:** 2026-11-19.

## Floors (never weaken)

- **Documentation and dev-only changes skip all of this.** Commit them straight to `master` in the primary checkout and
  push. They need no PR, no worktree and no review round. This covers documentation, agent instructions and policy,
  and other files the game and the server never load. This repository rule overrides the general rule that every
  change needs a worktree.
- **Landing means merged.** A PR has landed when it is merged into `master`. A commit or an open PR has not landed.
- **Every PR gets the review round.** Run the `pr-review-round` skill when the PR opens and after every push that
  changes production logic. It has three passes: adversarial, code review and simplification. Its stop rule ends the
  rounds. The code-review-only shortcut applies only to a change with no code in it (documentation, configuration).
- **Every voice is triaged.** Each finding from a pass, a bot or a contributor gets a verdict:
  - **Fixed:** cite the commit. A behaviour change carries a test that failed before the fix.
  - **Rejected:** give the evidence.
  - **Deferred:** link the tracking issue.
- **Merge commits only.** Merge with `gh pr merge <N> --merge --match-head-commit <head SHA>`. Squash and rebase merges
  are not used here.

## Review bots

Both bots are installed on this repository. Request them once the review round has stopped and CI is green on the
current head. Request them again for each later push that changes production logic, once its round has stopped and its
CI is green:

- **CodeRabbit:** comment `@coderabbitai review`.
- **Codex:** comment `@codex review`. If Codex replies that its usage limit is reached, skip it; that does not block
  landing.

Triage their findings like any other. A fix push that changes production logic starts a new round scoped to that push.

## Merge gate

Merge without asking the owner as soon as all of these hold for the current head:

1. The review round has stopped (its stop rule holds), with every finding's verdict recorded on the PR.
2. CodeRabbit has reviewed the current head, or the last head that changed production logic. Its findings are fixed or
   carry a recorded verdict.
3. Codex has done the same, or has replied that its usage limit is reached.
4. CI is green.

Ask the owner before merging when CodeRabbit has not reviewed that head. That includes a reply saying CodeRabbit is
rate-limited or skipped the review: a reply is not a review.

## CI

- The `Build` workflow runs on every pull request. Its jobs are `apk` (headless tests and the Android export) and
  `server`.
- An `apk` failure where Gradle could not fetch a dependency is an outage, not a finding. One example is Maven Central
  answering `429 Too Many Requests`. Re-run the failed job: `gh run rerun <run-id> --failed`.

## Local test runs

- Run the suite with `GODOT=<godot 4.7.2 binary> bash tests/run.sh`.
- `TEST_FILTER` runs only the tests whose `file::name` contains its value. For example, `test_editor.gd` runs one file,
  and `test_level_doc.gd::test_undo_restores_the_closed_wall` runs one test.
- As root, the 7 chmod-based tests in `test_community_history.gd` and `test_community_sync.gd` fail. They cannot make a
  folder read-only for root. That is expected.
- Concurrent runs share `user://` state, which makes them fail at random. Run one suite at a time, or give each run
  its own `XDG_DATA_HOME`.

## After merging

- Clean up the branch and its worktree as your general worktree rules say.
- A `Fixes #N` line in the PR body closes the linked issue on merge. Check that it closed.
