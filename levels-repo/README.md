# Zero-GX community levels

The levels players share for [Zero-GX](https://github.com/BRAITG/zero-gx). The repository holds only data:

- `levels/<lvl_id>/v<N>.json`: each published version of a level, never edited afterwards.
- `levels/<lvl_id>/meta.json`: the author and, optionally, the level it is based on.
- `proof/<lvl_id>/v<N>.demo.gz`: a recorded run that completes version N of the level.
- `index.json`: the list of levels the game browses.
- `hidden.txt`: levels hidden from the game, one `lvl_id` per line.

## Submissions

Players do not push here. The community server opens a pull request as a bot for each upload, adding the level
file, its proof run and, for a new level, `meta.json`.

## The check

Every pull request runs `.github/workflows/check.yml`, which uses the checker from the game repository. It fails
unless the pull request:

- only adds files, for exactly one level, with the next version number (`v1` for a new level);
- adds `meta.json` if and only if the level is new;
- adds a level file that is a valid level of at most 64 KiB;
- adds a proof run that is a valid demo of at most 512 KiB and completes that exact level file.

A pull request that only changes `hidden.txt` is also accepted. Mixing it with level files fails.

## Review

Pull requests are reviewed by the `@BRAITG/moderators` team (see `CODEOWNERS`). A pull request is merged only when
the check has passed and the level is acceptable; the check does not judge content. A failing or missing check must
never be merged.

The workflow runs from the pull request's own merge commit, so a pull request can edit or delete `check.yml` to skip
the check. The checker fails any change under `.github/` and the submission bot never touches it, so moderators
must reject any pull request that does. The ruleset on the default branch must require the `check` status.

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
