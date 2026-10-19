# Zero-GX community server

A Cloudflare Worker (TypeScript) with a D1 database and an R2 bucket. It signs players in, takes level submissions and opens pull requests for them in the levels repository (`BRAITG/zero-gx-levels`), records the review outcome, checks and ranks score demos, and publishes the level index. The design is in [`docs/superpowers/specs/2026-10-16-community-design.md`](../docs/superpowers/specs/2026-10-16-community-design.md).

Auth, in the table below:

- **session**: `Authorization: Bearer <session token>` from `POST /session`; banned players get 403.
- **integrity**: a fresh Play Integrity token in `X-Integrity` and the one-time server nonce (from `GET /nonce`) in `X-Nonce`. The app requests the token with a nonce bound to the request's payload: base64url without padding of SHA-256(server nonce as UTF-8 ‖ SHA-256(part 1) ‖ SHA-256(part 2) ‖ …), where the parts are the demo bytes for `POST /scores`, and the level bytes then the demo bytes for `POST /submissions` (`boundNonce` in `src/session.ts`). Google signs that nonce, so a changed or swapped body fails. `POST /scores` requires the `MEETS_STRONG_INTEGRITY` device verdict (hardware-backed: rooted phones and emulators cannot rank); `POST /session` and `POST /submissions` require `MEETS_DEVICE_INTEGRITY`.
- **admin**: `Authorization: Bearer <ADMIN_TOKEN>`.
- **webhook**: GitHub's `X-Hub-Signature-256` HMAC over the body, keyed with `GITHUB_WEBHOOK_SECRET`.

| Route | Auth | What it does |
|---|---|---|
| `GET /nonce` | none | A one-time nonce, valid 5 minutes. |
| `POST /session` | none (nonce, auth code, integrity token in the body) | Signs a player in with a Play Games auth code; returns a 7-day session token. |
| `POST /scores` | session + integrity | Re-checks the posted demo against its level, scores it, keeps the player's best. |
| `GET /boards/:sha256` | session | The top 100 for one level hash plus the caller's own row. |
| `GET /demos/:sha256/:player/:file` | session | A stored score demo. |
| `POST /submissions` | session + integrity | Validates a level and its demo, opens or updates the pull request. |
| `GET /me/submissions` | session | The caller's submissions with status and review comment. |
| `POST /levels/:level/like`, `DELETE /levels/:level/like` | session | Likes or unlikes a level (a like needs a score on it). |
| `POST /levels/:level/report` | session | Files a report as a GitHub issue in the levels repository. |
| `GET /levels` | session | Visible community levels, `sort=top` or `new`, paged. |
| `GET /players` | session | The player ranking. |
| `GET /index` | session | The commit of the levels repository the game should read `index.json` from. |
| `POST /admin/official` | admin | Registers the SHA-256 hashes of a release's official levels. |
| `POST /github` | webhook | Records pull request outcomes and `hidden.txt` changes. |

A cron trigger runs every 10 minutes: it recomputes the player ranking, deletes expired nonces and old rate counters, sweeps orphaned demos from R2 and rebuilds `index.json`.

Known limit: the demo recorder samples every second physics tick, so a run whose only thrust is a single unsampled tick records a clock event with no firing frame and is rejected by the clock rule.

## Deployment

You need a Cloudflare account with a payment method and the Workers **Paid** plan (US$5/month). The Free plan allows 10 ms of CPU per request, and also limits cron triggers to 10 ms of CPU. Checking a 10-minute demo is estimated at 40 to 100 ms (about 1 to 2 ms per 300 to 600 frames, measured in Node, not on Workers), so score posts and submissions would fail on Free. For deploys from CI, create a Cloudflare API token (template "Edit Cloudflare Workers", plus D1 and R2 edit) and give it to `wrangler` as `CLOUDFLARE_API_TOKEN`.

### Automated deploy (the normal way)

The `deploy-server` job in `.github/workflows/build.yml` runs `scripts/deploy.sh` after the server tests pass on every push to `master`. The script is idempotent: it creates the D1 database `zero-gx` and the R2 bucket `zero-gx-demos` if they are missing, writes the database id into `wrangler.toml` on the runner, applies migrations, deploys, and uploads every secret that is set (one new version). The job does nothing until the repository has the secret `CLOUDFLARE_API_TOKEN`.

Repository secrets of `BRAITG/zero-gx` the job reads (GitHub forbids secret names starting with `GITHUB_`, hence the `LEVELS_` names):

| Repository secret | Worker secret |
|---|---|
| `CLOUDFLARE_API_TOKEN` | — (the deploy credential; template "Edit Cloudflare Workers" plus Account → D1 Edit and Workers R2 Storage Edit) |
| `CLOUDFLARE_ACCOUNT_ID` | — (only needed when the token can reach several accounts) |
| `SESSION_KEY`, `ADMIN_TOKEN` | same names |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `PLAY_SERVICE_ACCOUNT` | same names |
| `LEVELS_APP_ID`, `LEVELS_APP_KEY`, `LEVELS_APP_INSTALLATION_ID`, `LEVELS_WEBHOOK_SECRET` | `GITHUB_APP_ID`, `GITHUB_APP_KEY`, `GITHUB_INSTALLATION_ID`, `GITHUB_WEBHOOK_SECRET` |

After the first deploy, set the repository variable `COMMUNITY_API` to the Worker's URL (no trailing slash) so releases register official level hashes.

### Manual deploy

All commands run in `server/`.

1. `npm ci`, then `npx wrangler login`.
2. `npx wrangler d1 create zero-gx`. Put the printed `database_id` into `wrangler.toml` (it holds a placeholder).
3. `npx wrangler r2 bucket create zero-gx-demos`.
4. `npx wrangler d1 migrations apply zero-gx --remote`.
5. `npx wrangler deploy`. Deploy the Worker before the GitHub App, which needs its URL. Note the `https://zero-gx.<subdomain>.workers.dev` URL; the game and the GitHub App use it.
6. Set every secret with `npx wrangler secret put NAME`, which prompts for the value. For multi-line values (the PEM, the JSON key) read it from a file instead: `npx wrangler secret put GITHUB_APP_KEY < app-pkcs8.pem`.

| Secret | Value |
|---|---|
| `SESSION_KEY` | A random string of at least 32 bytes, e.g. `openssl rand -base64 48`. Changing it signs everyone out. |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | The OAuth web client of the Play Games project (see Google setup). |
| `PLAY_SERVICE_ACCOUNT` | The whole JSON key of the Google service account that may call the Play Integrity API. |
| `GITHUB_APP_ID` | The numeric App ID of the GitHub App. |
| `GITHUB_APP_KEY` | The App's private key as **PKCS#8** PEM. GitHub issues PKCS#1; convert it: `openssl pkcs8 -topk8 -nocrypt -in app.pem -out app-pkcs8.pem`. |
| `GITHUB_INSTALLATION_ID` | The installation id of the App on `zero-gx-levels` (the number in the installation's URL). |
| `GITHUB_WEBHOOK_SECRET` | The secret you give GitHub for the webhook. |
| `ADMIN_TOKEN` | A random token; the release workflow uses it for `POST /admin/official`. |

Non-secret variables are in `wrangler.toml` under `[vars]`:

- `LEVELS_REPO`: `BRAITG/zero-gx-levels`; the webhook ignores every other repository.
- `ALLOW_TEST_VERIFIER`: keep `"0"`; never set it to `"1"` in production. With `"1"` the server accepts the codes `test:<id>:<name>` and tokens `ok:<nonce>` / `strong:<nonce>`, and anyone can sign in as anyone and post any score.

### Rate limiting

`GET /nonce` is unauthenticated and writes to D1, and `POST /session` calls Google, so per-player limits cannot cover them. The Worker limits both per client IP with a Workers Rate Limiting binding, `AUTH_LIMITER` in `wrangler.toml` (30 requests per 60 seconds, answered with 429). `namespace_id` is any number that is unique in the Cloudflare account; change it only if another Worker already uses `1001`. When the binding is absent (tests, plain local runs) the check is skipped. The limiter is per Cloudflare location and approximate.

Alternative: a Cloudflare WAF rate-limiting rule on `/nonce` and `/session` (for example 30 requests per minute per IP, action Block). WAF rules are zone-scoped and do not apply to `workers.dev`, so this needs the Worker on a custom domain of your zone; then set `workers_dev = false` in `wrangler.toml` so the unprotected `workers.dev` URL is switched off.

### Google setup

To complete when the Play Console account exists.

1. In Play Console, create the app `com.braitg.zerogx` and enable Play Games Services; link the Google Cloud project that Play Games creates.
2. In that project, create an OAuth client of type **Web application**. Its client id and secret are `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`. The game asks Play Games for a server auth code for this client.
3. Enable the Play Integrity API in the same project and link the project to the app in Play Console (App integrity).
4. Create a service account, download its JSON key and store it as `PLAY_SERVICE_ACCOUNT`. The server uses it to decode integrity tokens.

### GitHub setup

1. Create the public repository `BRAITG/zero-gx-levels` from `levels-repo/`: copy its files (including `.github/`) into a new directory, `git init -b main`, commit, add the remote and push. Its check workflow runs the checker from `BRAITG/zero-gx@master`, so it fails until `server/` is merged to `master` there.
2. Create the team `moderators` in the BRAITG organization and add the moderators (`CODEOWNERS` names `@BRAITG/moderators`). The team needs write access to the repository. With code-owner review required, a lone moderator cannot approve their own pull requests: add a second moderator, or have a repository admin merge: admins bypass the ruleset only because step 4 puts the Repository admin role on its bypass list.
3. Create a GitHub App owned by BRAITG:
   - Repository permissions: Contents read and write, Pull requests read and write, Issues read and write, Metadata read.
   - Webhook URL `<worker URL>/github`, secret = `GITHUB_WEBHOOK_SECRET`; subscribe to `pull_request` and `push`.
   - Generate a private key (give its PKCS#8 form to `GITHUB_APP_KEY`), note the App ID.
   - Install it on `zero-gx-levels` only; the number in the installation's URL is `GITHUB_INSTALLATION_ID`.
4. Protect `main` with a **ruleset** (Settings, Rules, Rulesets), not classic branch protection: require a pull request, require review from Code Owners, require the `check` status, block force pushes, and set the bypass list to the GitHub App with **Always allow** (it commits `index.json` directly) and the **Repository admin** role with **For pull requests only** (an admin can then merge a pull request that lacks the second review, which bootstraps the first moderators; pull-request-only is enough because admins never push to `main` directly, except for the deletion rewrite described in the levels repository's README, for which they temporarily switch to Always allow). Classic branch protection cannot do this: its bypass of pull-request rules does not lift required status checks, so the App's direct `index.json` commit, which has no `check` run, would be rejected (GH006).
5. In `BRAITG/zero-gx`, add the repository secret `ADMIN_TOKEN` (same value as the Worker's) and the repository variable `COMMUNITY_API` (the Worker URL, no trailing slash). The Build workflow then registers the official level hashes after each published release; without them official boards do not exist.
6. In the App's Advanced tab, a ping delivery should show a 200.

## Operations

Run these in `server/`.

**Ban a player.** Takes effect on their next request (the session check reads the flag); the ranking drops them at the next cron run.

```sh
npx wrangler d1 execute zero-gx --remote --command "UPDATE players SET banned = 1 WHERE id = 'p_xxxxxxxxxxxxxxxx'"
```

Set it back to `0` to unban. Player ids are not in `GET /levels`; find them in board responses, in `levels/<lvl_id>/meta.json` (the author), in report issues (`Reporter:`) or as `levels.owner` in D1. Names are not unique. A banned player disappears from level boards, and stops counting in their ranks, at once; the player ranking hides them at once too and recomputes at the next cron run.

**Hide a level.** Open a pull request in the levels repository that adds its `lvl_id` to `hidden.txt` and changes nothing else. When it is merged the webhook (a `push` touching `hidden.txt`) refreshes D1 and rebuilds the index. Hiding hides the whole level: its earlier approved versions also disappear from the index, the boards and the player ranking, and the boards stop accepting scores.

**A merge that was not recorded.** The webhook records a merged submission in one transaction. If the merged file's hash equals an already published version, the unique constraint on `versions.sha256` rolls everything back: the submission stays `open`, GitHub shows a failed (500) delivery, and the level cannot take another submission. Find these:

```sh
npx wrangler d1 execute zero-gx --remote --command "SELECT id, level, version, pull_request FROM submissions WHERE status = 'open' AND pull_request IS NOT NULL"
```

Compare with the merged pull requests (`gh pr list --repo BRAITG/zero-gx-levels --state merged`). For a merged one, find the file's hash and the version that already has it. This needs a local clone: `git clone https://github.com/BRAITG/zero-gx-levels` and `git pull` for the latest. Use `sha256sum` instead of `shasum -a 256` on Linux.

```sh
git show origin/main:levels/<lvl_id>/v<N>.json | shasum -a 256
npx wrangler d1 execute zero-gx --remote --command "SELECT level, version FROM versions WHERE sha256 = '<hash>'"
```

The file is already published under that other version, so close the submission and hide that submission's level:

```sh
npx wrangler d1 execute zero-gx --remote --command "UPDATE submissions SET status = 'rejected', decided = CAST(strftime('%s','now') AS INTEGER), comment = 'Duplicate of an already published level.' WHERE id = <submission id>"
```

Then add that level's `lvl_id` to `hidden.txt` in a pull request (the file `v<N>.json` stays in the repository; a further version of that level would collide with it, so the author should upload a new level). Any other failed delivery, for example when GitHub was unreachable, is fixed by redelivering it: the App's Advanced tab, Recent deliveries, Redeliver. A repeated delivery changes nothing that was already recorded.

**Rebuild the index.** The cron does it every 10 minutes and the webhook does after every merge and every `hidden.txt` change, so an index commit that failed repairs itself within 10 minutes. To force it, redeliver a `pull_request` (closed, merged) delivery from the App's page.

**First sign-in race.** Two first sign-ins of the same new account at the same time make one of them fail with 500. The app retries; nothing needs fixing.

**Nonces.** A nonce is consumed as soon as it is checked, by `POST /session` and also by `POST /scores` and `POST /submissions` (their integrity check), even if the request then fails. After any failed request of these three the app must fetch a new nonce.

**Logs.** `npx wrangler tail` streams the Worker's logs; cron step failures appear as `cron: <step> failed`.

## Local development

```sh
npm ci
npm test                        # vitest: core logic in Node, routes with local D1 and R2
npm run typecheck
```

To run the Worker locally, create `.dev.vars` (git-ignored, never deployed):

```
ALLOW_TEST_VERIFIER=1
SESSION_KEY=any-long-random-string
ADMIN_TOKEN=dev
```

then `npx wrangler d1 migrations apply zero-gx --local` and `npx wrangler dev`. Sign in with the auth code `test:<id>:<name>` and the integrity token `ok:<nonce>` (device integrity) or `strong:<nonce>` (strong integrity), where `<nonce>` is the server nonce for `/session` and the bound nonce for `/scores` and `/submissions`. Calls that need GitHub (submissions, reports, the index) additionally need real `GITHUB_*` values in `.dev.vars` and a test copy of the levels repository in `LEVELS_REPO`.

`npm run cli -- check-pr <repo-root> <base-ref> <head-ref>` is the pull-request checker that the levels repository's workflow runs.
