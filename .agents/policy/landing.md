# PR landing

Scope: reviewing and merging a pull request in this repository. Load when: opening a PR, applying review findings, or
merging.

- **Owner:** repository owner. **Last verified:** 2026-11-19.

## Floors (never weaken)

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
current head:

- **CodeRabbit:** comment `@coderabbitai review`.
- **Codex:** comment `@codex review`. If Codex replies that its usage limit is reached, skip it; that does not block
  landing.

Triage their findings like any other. A fix push that changes production logic starts a new round scoped to that push.

## Merge gate

Merge without asking the owner as soon as all of these hold on the current head:

1. The review round has stopped (its stop rule holds), with every finding's verdict recorded on the PR.
2. CodeRabbit has reviewed the PR, and its findings are fixed or carry a recorded verdict.
3. CI is green.

If CodeRabbit has not reviewed the PR, ask the owner before merging.

## CI

- The `Build` workflow runs on every pull request. Its jobs are `apk` (headless tests and the Android export) and
  `server`.
- An `apk` failure where Gradle could not fetch a dependency is an outage, not a finding. One example is Maven Central
  answering `429 Too Many Requests`. Re-run the failed job: `gh run rerun <run-id> --failed`.

## Local test runs

- Run the suite with `GODOT=<godot 4.7.2 binary> bash tests/run.sh`. Set `TEST_FILTER=<file>` to run one test file.
- As root, the 7 chmod-based tests in `test_community_history.gd` and `test_community_sync.gd` fail. They cannot make a
  folder read-only for root. That is expected.
- Concurrent runs share `user://` state, which makes them fail at random. Run one suite at a time, or give each run
  its own `XDG_DATA_HOME`.

## After merging

- Sync the primary checkout with `git pull --ff-only`.
- Remove the task's worktree with `git worktree remove`.
- Keep the branch.
- A `Fixes #N` line in the PR body closes the linked issue.
