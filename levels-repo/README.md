# Zero-GX community levels

The levels players share for [Zero-GX](https://github.com/BRAITG/zero-gx). The repository holds only data:

- `levels/<lvl_id>/v<N>.json`: each published version of a level, never edited afterwards.
- `levels/<lvl_id>/meta.json`: the author and, optionally, the level it is based on.
- `proof/<lvl_id>/v<N>.demo.gz`: a recorded run that completes version N of the level.
- `index.json`: the list of levels the game browses.
- `hidden.txt`: levels hidden from the game, one `lvl_id` per line.

## Submissions

Players do not push here. The community server opens a pull request as a bot for each upload, adding the level
file, its proof run and, for a new level, `meta.json`. The description may name the author's suggested difficulty; it is a hint for moderators, never the rating.

## The check

Every pull request runs `.github/workflows/check.yml`, which uses the checker from the game repository. It fails
unless the pull request:

- only adds files, for exactly one level, with the next version number (`v1` for a new level);
- adds `meta.json` if and only if the level is new;
- adds a level file that is a valid level of at most 64 KiB;
- adds a proof run that is a valid demo of at most 512 KiB and completes that exact level file.
- for a level, carries exactly one moderator label: `difficulty:easy`, `difficulty:normal`, `difficulty:hard` or `difficulty:expert`.

A pull request that only changes `hidden.txt` is also accepted, with or without a label. Mixing it with level files fails.

## Review

Player submissions are reviewed by the `@BRAITG/moderators` team (see `CODEOWNERS`). A submission is merged only when
the check has passed and the level is acceptable; the check does not judge content. A failing or missing submission
check must never be bypassed. Merge only level pull requests opened by the bot. Never reopen a rejected submission
after its author has resubmitted: the branch now carries the new submission.

Moderators rate each version by adding exactly one `difficulty:<label>` label to the pull request before merging (`difficulty:easy`, `difficulty:normal`, `difficulty:hard` or `difficulty:expert`). The check runs again when labels change. The merge stores that label as the version's reviewed difficulty; the author's suggestion is never used. A merge without exactly one such label, which only a bypass of the check allows, publishes the version as Not rated. Versions published before this rule are Not rated too.

The workflow runs from the pull request's own merge commit, so a pull request can edit or delete `check.yml` to skip
the check. The checker fails any change under `.github/` and the submission bot never touches it, so moderators
must reject any player submission that does. The ruleset on the default branch must require the `check` status.

### Repository maintenance

Workflow and documentation maintenance is not a player submission and cannot pass the data-only file allowlist. Use a separate pull request, independent workflow/CLI/security review, `actionlint`, and a real valid-proof checker smoke test. A repository admin may then use the existing **For pull requests only** bypass to merge that maintenance PR. Do not disable the ruleset, expand the submission allowlist, or use this exception for player levels or proofs.


## Hiding a level

Add its `lvl_id` to `hidden.txt` in a pull request that changes nothing else. The server stops listing the level.

## Licence

Level and proof files are contributed by their authors under CC BY-SA 4.0; see `LICENSE`.

## Deletion requests

An author or a rights holder can ask for a level to be removed. A moderator:

1. Adds the level to `hidden.txt` (the server rebuilds `index.json` from it).
2. Rewrites history with `git filter-repo` to drop `levels/<lvl_id>/` and `proof/<lvl_id>/`.
3. Force-pushes the rewritten history. The ruleset blocks force pushes, so the repository admin temporarily adds themselves to its bypass list with **Always allow** (or disables the ruleset), pushes, and restores it.
4. Asks GitHub Support to purge cached views and pull request diffs, which a force-push alone does not remove.
