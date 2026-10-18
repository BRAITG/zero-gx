# Community Levels and Rankings Design (sub-projects 3 and 4 of community levels)

Date: 2026-10-16
Status: Approved in conversation; awaiting written-spec review

## Purpose

Players publish the levels they build, download and play other players' levels, and compete on rankings for both the official and the community levels. Publishing goes through review, like a pull request, so the catalogue does not fill with spam. Everything stays free software and costs nothing to run at the start.

## Decisions

| Topic | Decision |
|---|---|
| Identity | Every community feature (browse, download, play, submit, scores, likes) needs a Google Play Games sign-in. Player traffic also carries a Play Integrity token. |
| Licensing | `LICENSE` gains an AGPL section 7 additional permission to link with the Google Play services libraries. The game stays AGPL-3.0-or-later. |
| Level storage and review | A public GitHub repository, `BRAITG/zero-gx-levels`. A submission is a pull request opened by a bot, checked by GitHub Actions, and approved by a human moderator merging it. GitHub's web and desktop clients are the moderation tools. |
| Everything else | A Cloudflare Worker (API, sign-in, rate limits, the bot), D1 (players, submissions' status, scores, likes, rankings) and R2 (score demos). |
| Level identity | Players see `lvl_` plus 10 random characters, assigned at a level's first submission, plus a version number (`lvl_k3x9q2m7ab/v3`), or an official level's name. Internally every level version is identified by the SHA-256 of its file's exact bytes: boards, demos and downloads use that hash. Approved versions are files that are never changed. |
| Level files | Plain JSON in a stable layout (sorted keys, 2-space indent, trailing newline), both in the levels repository and for the official levels in this repository. Player drafts on the phone stay `.json.gz`. |
| Proof of play | A *demo*: a recording of a run's state at 30 frames per second. A submission includes its author's finishing demo; every score includes its demo. |
| Rankings | One board per level hash (each official level revision and each community level version); a ranking of community levels by likes; a ranking of players by total community points. |
| Cost | Free tiers: GitHub (public repository, Actions, jsDelivr CDN), Cloudflare Workers, D1 and R2. R2 charges nothing for downloads. |

## Sub-projects and order

1. **Demos and JSON levels (app only).** Record runs, play them back, keep the last finished test run of each draft. Move official levels and tutorials from `.json.gz` to plain JSON.
2. **Android plumbing.** The licence permission, a Gradle-based Android build, the Play Games sign-in plugin (with a server auth code) and a small Play Integrity plugin.
3. **Server and levels repository.** The Worker, D1 and R2, the GitHub App, the repository's Actions and branch protection.
4. **Community in the app.** Community screens, submission from My levels, boards, the demo viewer.

Each gets its own implementation plan.

## Demos

A demo is a gzip-compressed binary file.

- **Header:** demo format version, `level_sha256` (the SHA-256 of the level file it was recorded on, 64 hex characters), the time step (1/30 s), the frame count, and the starting state of every moving object.
- **Each frame:** the ship as integers (position in px, rotation in milliradians, engine on/off, fuel and hull in tenths), then only the asteroids and planet shards that moved, as differences from the previous frame.
- **Events:** frame number and code for pickup taken, planet shattered, ship lost, goal reached.
- **Size:** about 10–30 KB for a one-minute run without asteroids, 100–200 KB with 30 asteroids (estimates).

Playback places every object where the frame says and interpolates between frames; no physics runs, so a demo looks the same on every device. One decoder in GDScript (playback, and a local copy of the checks for tests) and one in TypeScript (the Worker and the Actions validator).

### Demo checks

Run by the Worker on every score and by Actions on every submission, against the level file the demo names:

1. The SHA-256 of the level file being checked equals the demo's `level_sha256`.
2. Frame 0 is at the level's start; the last frame is inside the goal, with a goal-reached event.
3. Between frames the ship moves no more than the game's hard speed limit (`Ship.TUNNEL_LIMIT`, 1,200 px/s) allows, plus a margin.
4. The ship's path crosses no wall segment and never touches a red wall, a star or a black hole.
5. Fuel never rises except at a pickup event; the claimed points match fuel, hull and time under `Progress.points`, within a tolerance; the claimed time is the frame count over 30, within one frame.

These checks do not make a forged demo impossible; they make one expensive to fake. They take a few milliseconds per demo.

## Sign-in

1. The app requests a one-time nonce: `GET /nonce`.
2. It obtains a Play Games server auth code and a Play Integrity token bound to that nonce, and sends both to `POST /session`.
3. The Worker exchanges the code for the player's Play Games id, and requires the integrity verdict to show our package name, an app recognized by Play, a device meeting basic integrity, and our nonce.
4. The Worker returns its own signed session token, valid for 7 days. Every request carries it. Submissions and score posts also carry a fresh integrity token.

Identities live in an `accounts` table mapping a provider and its id (Play Games now; a Google account later, for desktop and web clients) to a player. The API is plain JSON and nothing in it is Android-specific beyond the integrity token, so desktop and web clients can be added without changing it.

## Submitting and reviewing

### Submission

1. In My levels, **Submit** is offered for a completed draft. The app keeps the demo of the last finished test run of each draft and sends it with the level as JSON. A new version of a published level names its level id; only its owner may add versions.
2. The Worker rejects the submission if the session or integrity check fails, the player is banned, the level is over 64 KB, the demo is over 512 KB, or the player is over their limits: 3 open submissions and 5 a day.
3. A level may have one open submission at a time. It takes the next version number (latest approved + 1). Submitting again while it is open updates the same pull request. A rejected number is reused, since it was never published.
4. The Worker's GitHub App opens a pull request adding `levels/<lvl_id>/v<N>.json`, `proof/<lvl_id>/v<N>.demo.gz` and, for a new level, `levels/<lvl_id>/meta.json` (an opaque author id and `based_on` when the level is a copy).

The repository never holds a player's name or Google identity; the author's display name is published only through the index, which the bot writes from D1.

### Automatic checks (GitHub Actions)

On every pull request:

- The pull request only **adds** files under one `levels/<lvl_id>/` and its `proof/` twin. Changing or deleting an existing file fails, except `index.json`, which only the bot may change.
- The level passes the level-format rules (the TypeScript port).
- The proof demo passes the demo checks against that level.

### Review

Branch protection on the default branch requires the checks to pass and an approving review from a member of the `moderators` team. A moderator merges to approve or closes with a comment to reject. A GitHub webhook tells the Worker, which records the outcome and the comment in D1 for the author's My levels view. On merge, an Action rebuilds `index.json` (see "Levels repository").

Pull requests, including rejected ones, are public. Rejected proof demos are not kept anywhere else.

### Moderation

- **Report:** any player can report an approved level; reports are listed for moderators as GitHub issues opened by the bot.
- **Hide:** a moderator removes a level from `index.json` with a commit. Its files remain in history; the app no longer lists it and its boards stop accepting scores.
- **Ban:** a flag on the player in D1. The Worker refuses their submissions, scores and likes.
- **Deletion requests:** level titles and hints are player-written text. A legal removal request is handled by rewriting the repository history and asking GitHub to purge cached views; the procedure is documented in the levels repository's README.

## Scores and rankings

### Posting a score

`POST /scores` carries the claimed points, fuel, hull and time, and the demo. The Worker finds the level file by the demo's `level_sha256` (community versions through `index.json`; official levels through the hashes of each release's level files, recorded when the release is published), runs the demo checks, and keeps the player's best score per level hash. A beaten score's demo is deleted from R2. Limit: 30 score posts per player per minute.

### Official levels

Official levels are `levels/level_NN.json` in this repository. A board belongs to one level hash, so changing an official level's content starts a new board automatically. The release workflow records each release's official level hashes in D1 (`official_levels`).

### Boards and rankings

| Ranking | Contents |
|---|---|
| Level board | The top 100 for one level hash: points with the fuel, hull and time parts, each with a ▶ to watch its demo, and the player's own row if they are below 100. |
| Community levels | Approved levels by likes, then by distinct players. One like per player per level, allowed only after finishing it. |
| Community players | Each player's total of best points on the latest approved version of every community level, recomputed by a cron trigger every 10 minutes. |

## Data

### D1

| Table | Columns |
|---|---|
| `players` | id, display name, banned, created |
| `accounts` | provider, provider id, player id |
| `levels` | level id, owner, based_on, latest approved version, hidden |
| `versions` | level id, version, level SHA-256 |
| `submissions` | level id, version, pull request number, status (open, approved, rejected), review comment, created, decided |
| `scores` | level SHA-256, player, points, fuel, hull, time, demo key, posted |
| `official_levels` | level SHA-256, level name (`level_01`), release |
| `likes` | player, level id |
| `player_ranking` | player, total points, rank, computed |

### R2

`demos/<random key>.demo.gz` for score demos, one per player per level version.

### Levels repository

```
index.json
levels/<lvl_id>/meta.json
levels/<lvl_id>/v1.json, v2.json, …
proof/<lvl_id>/v1.demo.gz, …
.github/workflows/check.yml, index.yml
```

`index.json` lists, for each level, its id, title, author's display name, and each approved version's number and SHA-256. The app downloads `index.json` and level files through jsDelivr pinned to a commit (`cdn.jsdelivr.net/gh/BRAITG/zero-gx-levels@<sha>/…`), and rejects a downloaded file whose SHA-256 differs from the index; the Worker's `GET /index` returns the current commit.

## App screens

- **Main menu:** a **Community** button next to My levels. It asks for Play Games sign-in once.
- **Community:** tabs **Top** (by likes) and **New**. Each row: title · vN, author, likes, the player's best. A level offers **Play**, its board, **Watch the top demo**, **Like**, **Edit a copy** and **Report**.
- **Board:** see above. The end panel of official and community levels adds a **Board** button.
- **Players:** the community player ranking, top 100 plus the player's own row.
- **My levels:** **Submit** on completed drafts, and each draft's status: Draft, Pending, Approved vN, or Rejected with the moderator's comment.
- **Demo viewer:** pause, 0.5×, 1× and 2× speed, a timeline scrubber; the camera follows the ship.

## Offline and errors

- Levels already played stay cached and playable offline.
- Scores and likes made offline queue locally with their demos and are sent when the app is online again.
- Every error is shown as a sentence. An automatic rejection names the rule that failed.
- An expired session signs in again silently and retries the request once.

## Testing

- **Godot:** recording a run and playing it back puts every object where it was; the demo of an autopilot run passes the GDScript copy of the checks.
- **Shared fixtures:** one folder of good and bad levels and demos used by the Godot tests, the Worker tests and the Actions validator, so the three implementations agree.
- **Worker:** `vitest` with Cloudflare's Workers test pool (local D1 and R2): sessions, limits, best-score keeping, the webhook, with Google and GitHub calls mocked.
- **End to end:** a local Worker against a test copy of the levels repository: submit, check, merge, download, post a score.

## Out of scope

- Desktop and web clients (the API and identity model allow them later).
- Cloud saves (sub-project 5).
- Comments on levels, following players, collections.
- Automatic difficulty rating.
