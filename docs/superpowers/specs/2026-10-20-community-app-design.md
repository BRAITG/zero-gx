# Community in the App, First Slice: Sign-in, Submit, Browse and Play

## Goal

Give Android players the first working community loop on the live server (`https://zerogx.braitg.dev`): sign in with Play Games, submit a finished level, and, once a moderator merges it, find it under Community and play it, including offline afterwards. This covers sub-project 2 of the community design (Android plumbing) and the first part of sub-project 4 (community in the app). The server, the levels repository and moderation already exist; see `docs/superpowers/specs/2026-10-16-community-design.md`, whose rulings R1 to R6 still apply.

## Decisions

| Topic | Decision |
|---|---|
| Play Games sign-in | The `godot-play-game-services` plugin (MIT, `godot-sdk-integrations/godot-play-game-services`), vendored into `addons/`. It signs the player in and returns a server auth code for the OAuth web client. |
| Client | A GDScript autoload, `Community`, owns every server call, the session token and the download cache. Screens call it; it never touches UI. |
| Play Integrity | Our own small Android plugin, `addons/zero_gx_integrity/`: one call that takes a nonce and returns a Play Integrity token from a classic request, because the server checks `requestDetails.nonce` (`server/src/verify.ts`). No Godot plugin for Play Integrity exists. |
| Platforms | Windows, macOS and Linux stay fully supported for everything except online features: the campaign, training, My levels, the editor, test flights, local demos and file import/export. Community, Submit, boards, scores, likes and Play Games exist only in the Play build of the Android app (`CommunityAndroid.available()`: the `community` export feature, both plugin singletons and the setup values); every other build hides those buttons, desktop builds never load the plugins (they are Android-only AARs), and none of them contacts the server. This rule also binds every later community slice. |
| In this slice | Sign-in, the Community screen (Top and New), downloading, caching and playing a community level, Submit from My levels, and submission status. |
| Not in this slice | Scores and boards, likes, reports, the player ranking, Edit a copy, the offline score queue and the demo viewer for community runs. They follow in the next slice. |

## Android plumbing

- **Sign-in plugin.** Vendor the plugin release that supports Godot 4.7 into `addons/GodotPlayGameServices/` and enable it. Its Android export settings carry the Play Games project id (the numeric "Project ID" from Play Console). The client requests a server auth code for the web client id `GOOGLE_CLIENT_ID` (a public value; it is stored in `project.godot` as `community/google_web_client_id`).
- **Export.** Both plugins are enabled in the `Android Play` preset and the sideload `Android` preset, but only `Android Play` sets the custom export feature `community`, which `CommunityAndroid.available()` requires together with both plugin singletons and the setup values (`community/google_web_client_id` and `community/cloud_project_number` in `project.godot`). A sideloaded debug APK is never recognised by Play Integrity (`UNRECOGNIZED_VERSION`), and the server requires `PLAY_RECOGNIZED` (`server/src/verify.ts`), so it could not sign in; it shows no Community and no Submit.
- **Play Games at launch.** The Play Games v2 SDK starts at every launch through its own init provider, which cannot be removed (the plugin's client needs it), and Google may then sign the player in to Play Games. That is Google's service under Google's privacy policy. Our server still receives nothing until the player opens Community; `PRIVACY.md` says so.
- **Licence.** `LICENSE-EXCEPTION` already permits linking with the Google Play libraries.
- **Integrity plugin.** A Godot 4 Android plugin (v2: an `EditorExportPlugin` that adds an AAR) with one method, `request(nonce: String)`. It makes a classic Play Integrity request (`IntegrityTokenRequest` with `setNonce` and the Google Cloud project number from `community/cloud_project_number` in `project.godot`) and emits `integrity_token(token: String)` or `integrity_failed(message: String)`. Nonces are URL-safe base64 without padding, as the API requires. Sources live in `android/plugins/integrity/` and build with the project's Gradle setup; the built AAR is committed under `addons/zero_gx_integrity/`.

## The `Community` client

All requests go to `community/api_url` in `project.godot` (default `https://zerogx.braitg.dev`).

**Sign-in**

1. `GET /nonce` returns a one-time nonce. It comes first, so that offline fails at once as "No connection", before Play Games is asked.
2. The Play Games plugin signs in and returns a server auth code; the integrity plugin returns a token for the nonce.
3. `POST /session` with the nonce, the auth code and the token returns a session token valid for 7 days, stored in `user://community.cfg` with its expiry.
4. Every later request sends the session token. A `401` clears the token that was sent (not a newer one that a sign-in saved meanwhile), signs in again silently once and retries the request once. The status refresh never signs in: its `401` only clears the local session.
5. One sign-in runs at a time; a caller that comes while one is under way waits for it and gets its result.
6. A nonce is used up when the server checks it, even when the request fails, so every call that needs one fetches a new one. A submission may take up to 120 s to answer; every other call 30 s.

**Bound nonces.** Submissions send an integrity token for the bound nonce `base64url(SHA-256(nonce as UTF-8 ‖ SHA-256(level bytes) ‖ SHA-256(demo bytes)))`, without padding, as `boundNonce` in `server/src/session.ts` computes it. A shared fixture, `fixtures/bound_nonce.json` (inputs and the expected result), is checked by both the Godot tests and the server tests, so the two implementations agree.

**Requests used in this slice**

| Request | Use |
|---|---|
| `GET /levels?sort=top\|new&page=N` | The Community lists: `level_id`, `title`, `author`, `latest`, `sha256`, `likes`, `players`. |
| `GET /index` | The levels repository commit to download from. |
| `POST /submissions` | Submit a draft (multipart `level`, `demo`, optional `level_id`), with `X-Nonce` and `X-Integrity`. Returns `level_id`, `version` and `pull_request`. |
| `GET /me/submissions` | Status of the player's submissions: `level_id`, `version`, `status`, `comment`, `title`. |

**Downloads and cache.** A level is downloaded from `https://cdn.jsdelivr.net/gh/BRAITG/zero-gx-levels@<commit>/levels/<level_id>/v<latest>.json`, where `<commit>` comes from `GET /index`. A file whose SHA-256 differs from the listed `sha256` is rejected and not cached. Accepted files are stored as `user://community/<sha256>.json` and are played from the cache from then on, also offline. The last fetched list pages are cached too, so Community shows them offline with a "You are offline" note.

## Screens

- **Main menu.** A **Community** button next to My levels, in the Play build only. The first tap signs in, with the button saying "Signing in…" and off meanwhile; if sign-in fails, the reason is shown and the menu stays. Offline, Community opens anyway and shows its cached pages, so downloaded levels stay playable after the session has run out.
- **Community.** Tabs **Top** and **New**, 50 rows a page (the server's page size) with a **More** button. Each row shows the title, `vN`, the author and the number of likes, plus **Play**. Play downloads the level if it is not cached yet, then opens it like any other level. The end panel's buttons are the usual ones, without a board.
- **My levels.** Completed drafts (finished in Test and unchanged since) get a **Submit** button, which says "Submitting…" and is off while it waits. Each draft that has been submitted shows its status: Pending, Approved vN, or Rejected with the moderator's comment, or "Submitted" while no status is known. A submitted draft that has not changed since offers no second Submit (its content hash is kept as `submitted_hash` next to `level_id`); editing it brings Submit back. The status is refreshed from `GET /me/submissions` when My levels opens and the player is signed in; otherwise the last known status shows. Play and More in Community say "Loading…", and Delete account "Deleting…", while they wait.

## Submitting

1. Submit is offered only for a completed draft with a stored finishing demo (`MyLevels.demo(id)` is not null).
2. The client sends the exact `LevelFormat.to_json` bytes of the draft as `level`, and the stored demo bytes as `demo`. The demo's `level_sha256` already matches these bytes, because the demo is kept only while the draft is unchanged.
3. The first submission of a draft has no `level_id`. The returned `level_id` is stored for the draft in `user://levels/index.cfg` (key `level_id` in the draft's section) and sent with every later submission, so the next approved version becomes `v2` of the same level.
4. The server enforces its limits (3 open submissions, 5 a day, 64 KB levels, 512 KB demos) and checks; its error text is shown to the player as it is.
5. Review stays on GitHub: a moderator merges or closes the pull request in `BRAITG/zero-gx-levels`. After a merge the level appears under New within about 10 minutes, when the bot rebuilds `index.json`.

## Errors

- Every failure is shown as one sentence: the server's message, or "No connection" when the device is offline. A Play Integrity failure reads "Play Integrity could not check this device."; its raw text goes to the log only.
- A failed sign-in keeps the player where they were and shows why (for example "Play Games sign-in was cancelled").
- A rejected download says the file did not match the level list and keeps nothing.

## Testing

- **Headless tests** drive `Community` through a replaceable HTTP layer and a replaceable plugin layer (fakes that answer like the server's test verifier: auth code `test:<id>:<name>`, token `ok:<nonce>`). They cover sign-in and the stored session, the single silent retry on `401`, one sign-in at a time, a fresh nonce after a failed call, the bound nonce against `fixtures/bound_nonce.json`, multipart submission contents, the stored `level_id` on a second submission, status mapping, the hash check on downloads, and playing from the cache with the network down, also when the session has expired.
- **Server test**: `fixtures/bound_nonce.json` is checked against `boundNonce`.
- **Device proof** (the author, on a phone with the Play internal-testing install of the CI bundle, since only a Play install is recognised by Play Integrity): sign in, submit a completed draft, merge its pull request, see the level under New, play it, then play it again with networking off.

## Setup outside the code

Play Games Services and the OAuth web client do not exist yet. `docs/release/play-games-setup.md` lists the Play Console and Google Cloud steps, the repository secrets to add (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`), and the values the code needs (the Play Games project id, the Cloud project number and the web client id). The client can be built and tested headlessly without them; sign-in on a device needs them.
