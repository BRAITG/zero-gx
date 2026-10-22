# Community Feedback and Difficulty Design

## Goal and scope

Help players decide which community stages to try and help authors understand how challenging their stages are. Add stage-wide likes, version-specific reviewed and player difficulty, and observed play statistics. The play history measures learning up to the first clear, not subsequent score-chasing.

This extends `2026-10-20-community-app-design.md` and the community service in `2026-10-16-community-design.md`. The full sharing loop already works on a real Play-installed build. No new sign-in provider, hosting service or dependency is needed.

**Included:** Android Play app UI, Worker API and D1 migrations, GitHub moderation labels/checks, offline reporting, account-deletion coverage, privacy and Play Console disclosure updates.

**Excluded:** comments, per-stage Issues/Discussions, downvotes, new leaderboards, publishing desktop runs, and automatic skill-adjusted difficulty labels. Comments remain undecided. Cross-level play history can support a future skill-adjusted model, but this release must not claim to estimate player ability or classify difficulty from the raw success ratio.

## Product rules

| Feature | Rule |
|---|---|
| Like | One toggleable like per player and stable `lvl_` id, shared across versions. |
| Like eligibility | A clear on any version of that stage, or at least five counted attempts across its versions. Removing an existing like is always allowed. |
| Player difficulty | One editable/removable vote per player and version hash. |
| Difficulty-vote eligibility | A clear on that exact version, or at least five counted attempts on it. Experience on an earlier version does not qualify. Removing an existing vote is always allowed. |
| Difficulty scale | Easy, Normal, Hard, Expert, in that order. |
| Reviewed difficulty | Author suggests; moderator confirms through a GitHub PR label. It is independent of player votes. |
| Community difficulty | The upper median of eligible players' votes, with a vote count. An even-sized vote set uses the harder of its two middle labels rather than averaging ordinal labels. |
| Learning history | Count attempts only through each player's first clear of each version. Later practice and score-chasing are excluded. |
| Platforms | New collection and feedback are Android Play community features only. Windows/macOS/Linux and sideload builds remain offline-only; campaign, training, draft tests and demo playback are not tracked. |

Wire/storage difficulty values are `easy`, `normal`, `hard` and `expert`; the app displays the capitalized labels above.

A normal play of one's own published community stage follows the same rules as another player's play. Editor Test and Publish proof flights never qualify as community attempts or votes.

## Reviewed difficulty without changing proof hashes

1. The final **Submit for review** sheet adds a **Suggested difficulty** choice using the four labels. The author explicitly chooses a value; the suggestion is not a reviewed rating.
2. The suggestion travels as the optional multipart text field `suggested_difficulty`, separately from the level JSON. When present, bind its exact UTF-8 bytes after the level and demo bytes: `boundNonce(nonce, [level, demo, suggested_difficulty])`. Older clients without the field keep their existing two-part binding and remain supported.
3. The submission PR body shows the author's suggestion. The bot never applies an authoritative reviewed-difficulty label on the author's behalf.
4. Moderators select exactly one label: `difficulty:easy`, `difficulty:normal`, `difficulty:hard`, or `difficulty:expert`. The existing `check` pipeline requires exactly one before a new submission can merge and reruns when labels change. The level/demo checks and code-owner approval remain required.
5. The signed merge webhook reads the moderator's selection and stores it with the approved version. Reviewed difficulty is fixed for that approved version. It does not modify the level JSON, the demo or their hashes.
6. Existing versions have **Reviewed: Not rated** until a reviewed new version is published. Do not guess or backfill labels from titles, scores or author hints. Existing open PRs may need a moderator label when the check is enabled.

The four labels must be provisioned in `BRAITG/zero-gx-levels`. This does not require new GitHub App permissions: the bot already has Contents, Pull requests and Issues access. Label application is a moderator action, separate from the author's in-app suggestion.

## What is an attempt?

An attempt is a fresh run of a downloaded, published community version that enters live gameplay. Allocate and persist a random attempt id when gameplay begins, after any tour that pauses play, before recording the first active simulation tick.

- Opening Community, viewing details, downloading a file or showing a paused introduction is not an attempt.
- Restarting through **Retry** creates a new attempt only when the replacement run begins live gameplay. Pause/resume and application background/foreground do not create another attempt.
- Death and fuel exhaustion finish an attempt as **failed**. Returning to the menu after gameplay began finishes it as **abandoned**. Winning finishes it as **cleared**.
- Closing/crashing the app after a persisted start leaves an unfinished attempt. It still counts as a started attempt; it must not become a clear or disappear from the denominator.
- An extremely short real attempt can count: instant deaths can be a property of a broken or very hard stage. There is no new time-based eligibility setting in this slice.
- First clear includes the successful attempt itself. After the app knows that player has cleared that version, new replays generate no difficulty-history reports.

Difficulty history starts with this feature. Do not invent attempts from local best scores or assume an old local clear took one attempt. An existing server-verified score can grant voting eligibility, but is not used to fabricate a historical attempts denominator.

## Observed statistics

For each version, expose:

| Statistic | Meaning |
|---|---|
| Players started | Distinct players with a counted attempt. |
| Players cleared | Distinct starters who cleared at least once. |
| Player clear rate | Players cleared / players started. |
| Attempts per first clear | All counted pre-first-clear attempts, including players still unbeaten, divided by the number of first clears. With no clears, show **No clears yet**, not an infinite/zero difficulty value. |
| Median tries among finishers | Median counted attempts to first clear, explicitly labelled as measuring finishers only. |
| Still unbeaten after 5 / 10 / 20 attempts | Distinct players with at least that many counted attempts and no clear. One player grinding does not become many players. |

Always show the relevant player/vote counts. With fewer than ten distinct starters, show the raw counts and **Not enough play data** instead of presenting ratios as reliable difficulty estimates. With fewer than five difficulty voters, show **Not enough ratings** and the count instead of an aggregate label. These are display thresholds, not changes to individual voting eligibility.

These are observations about the current audience, not an objective skill-adjusted difficulty grade. Many beginners struggling does not automatically make a stage Expert. Keep **Reviewed**, **Community**, and play statistics separate.

## Reporting and offline behaviour

### Minimal report data

Persist compact attempt records in the app's private storage, scoped to the Zero-GX player id and version hash:

- Random attempt id, version hash and start time (integer UTC milliseconds).
- Optional terminal outcome and end time.
- Snapshot revision and synchronization state: revision 1 is a start, revision 2 adds a terminal outcome. The server derives the phase from the contents and rejects inconsistent revisions.

No device fingerprint, cursor path, raw inputs or failed-run demos are added to this system. Reports are app-attested gameplay events, not independently replay-verified score claims. They can unlock low-stakes feedback and contribute to statistics; they must never create leaderboard scores or approve a submitted level.

The server keeps one compact record per player/attempt id and a per-player/version summary. It derives counts from those records rather than accepting a client-supplied total. Index history by player, version and start time; read public aggregates from summaries rather than scanning every attempt for every list row.

### Idempotency and ordering

- Upload a snapshot of an attempt: start fields are immutable, and an unfinished record may acquire one terminal outcome. Repeating the same start or finish is a no-op; a reused id with different immutable fields or a conflicting terminal result is rejected.
- A stable attempt id survives timeouts and app restarts. Never generate a fresh id to retry the same report. A response lost after server success cannot increment the count twice.
- Persist starts before gameplay and terminal results before showing the result card. An outbox revision is cleared only after the server acknowledges that revision: an in-flight start acknowledgment must not erase a finish added meanwhile.
- For delayed/multiple-device reports, the first clear is the earliest reported clear end time. Count starts at or before that cutoff, including the winning attempt, and exclude starts after it. Recompute the summary if an older offline report changes the history. Do not use arrival order as the learning order.
- Client timestamps are ordering hints for gameplay statistics, never evidence for score freshness, session lifetime or nonce validation. Device clock skew can affect cross-device ordering; statistics remain observations, not competitive rankings. Store server receipt time as well.

### Synchronization

Batch at most 32 changed attempt records in a JSON body of at most 16 KiB. Routine background flushes are at least 30 seconds apart to avoid making a classic Play Integrity request on every rapid retry. Opening Community or attempting to vote may request a flush; it respects the same spacing and shows **Syncing play history…** rather than holding a vote request open. Serialize Integrity token requests with other community actions so two callers cannot consume each other's answers.

Use the existing session plus a fresh `MEETS_DEVICE_INTEGRITY` token whose bound nonce covers the exact JSON report bytes. Feedback eligibility does not require `MEETS_STRONG_INTEGRITY` or a ranked score. All network/plugin waits remain at most 30 seconds; reuse the existing one-time 401 re-sign-in policy with a new nonce on the retry.

Server limits for the new play-report endpoint are 30 batches per player per minute in addition to the existing authentication limiter. Validate ids, hashes, times, outcomes, sizes and ownership before storing anything. A version must belong to a published community stage. Hidden/unknown versions do not gain statistics; acknowledge those records as discarded with a reason so one stale record cannot block the whole outbox. Structurally invalid batches fail without applying partial changes.

Offline gameplay never waits for reporting. Keep the outbox on connection failure and sync it later. Like/rating changes made offline keep only the latest desired state per player/stage or player/version and display **Pending sync**. Synchronize the required play history before applying a new vote; do not show a locally counted attempt as server-confirmed eligibility. Removing one's own feedback does not require another play.

A permanent refusal of a queued vote removes that pending change, restores the server-confirmed state and shows the reason. Connection failures retain it. Do not repeatedly retry a rejected vote or leave an invalid change marked as pending forever.

### Account ownership

Store `player.id` from a successful server sign-in alongside the session. Existing installations without that field refresh sign-in on their next online Community visit before recording account-owned reports. Offline cached play remains available while identity is unknown, but no ownerless report is attached to whichever account signs in later.

Every outbox entry retains its owner id. If silent re-sign-in changes the player, do not upload the previous player's entries using the new token. The server compares the batch's claimed owner with the authenticated player; the body never grants authority. Queues belonging to another account are not applied to the current account. A deleted account's queued activity cannot recreate its history under a newly created account.

## Server interfaces and data

Keep the current error format `{ "error": "<sentence>" }` and existing likes routes.

| Interface | Behaviour |
|---|---|
| `POST /plays` | Session + bound device-integrity token. Body contains `player_id` and attempt snapshots. Returns acknowledged/discarded ids and their snapshot revisions; duplicates are acknowledged without incrementing counts. |
| `GET /levels/:id/feedback?sha256=<version hash>` | Session. Returns reviewed/player difficulty and counts, aggregate play statistics, and only the caller's eligibility, liked state, difficulty vote and play summary. The hash must belong to this visible stage. |
| `POST /levels/:id/like` | Existing session-protected endpoint; replace score-only eligibility with clear-or-five-attempt eligibility, retaining existing verified-score eligibility. Idempotent. |
| `DELETE /levels/:id/like` | Existing removal route; no play prerequisite. |
| `PUT /levels/:id/difficulty` | Session; `{sha256, difficulty}`. Server enforces version-specific eligibility and stores/replaces exactly one vote for this player/version. |
| `DELETE /levels/:id/difficulty?sha256=<version hash>` | Session; removes the caller's vote without a play prerequisite. |

Extend the D1 schema additively: nullable reviewed difficulty on versions; per-player attempt records/summaries; per-player/version difficulty votes. Extend the index/API with reviewed difficulty without changing any level file or format version. Existing clients may ignore the added fields.

Public statistics and voting aggregates exclude banned/deleted players. `DELETE /me` removes the player's attempt records, summaries, difficulty votes and pending local feedback alongside existing data; aggregates must reflect that deletion. Published levels and their moderator-reviewed metadata remain, as in the current policy.

## App surface

- The Community list keeps **Play** and the like count, adds compact reviewed/community difficulty information, and provides **Details** for the selected stage/version. Existing builds/platform gating remains.
- **Stage details** shows Play, the stage-wide Like toggle, Reviewed difficulty, Community difficulty with voter count, Rate difficulty, and the statistics above. Legacy reviewed difficulty is **Not rated**. Avoid an unreadable row of voting buttons in the list.
- Before eligibility, show **Clear this version or make 5 attempts to rate its difficulty** and the caller's progress. Stage-wide likes explain that a clear or five attempts on the stage qualifies. After a clear or the fifth attempt, make feedback discoverable on the result screen through **Rate level**; it opens the same details/rating controls rather than a second rating implementation.
- Difficulty votes can be changed or removed, and likes toggled. Do not overwrite a player's current selection with a stale response. Buttons show busy/pending state; errors remain sentences and never interrupt the flight.
- Back closes the top sheet, then returns to the previous screen; keyboard/pad focus follows existing `Overlay` and `Style` conventions. Offline details may show the last cached feedback marked as offline, not a live value.

## Privacy and rollout

Update `PRIVACY.md` and its published copy on braitg.dev before shipping collection. Disclose account-linked community play starts, attempts/outcomes and difficulty votes, their use for stage feedback/difficulty assessment, and that only aggregate statistics are public. Replace the blanket **no analytics** claim with precise wording: no advertising, tracking across services or third-party analytics SDK; community gameplay statistics are collected as described. Retain the promise that offline-only/desktop play does not send data.

Play-history records, summaries and votes remain for the account's lifetime or until account deletion, matching existing community retention. Update the Play Console Data safety guidance for app activity and the assessment purpose; do not assume the prior scores/likes-only answers cover this new collection unchanged.

Deploy migrations/backend before the new app. Provision moderator labels and update the levels repository's check workflow, then ship the Play build. New optional submission metadata and feedback response fields remain additive; no older app is forced to change its level/demo binding. Never weaken score/submission verification or TLS settings as part of this feature.

## Acceptance and verification

- **Eligibility:** clear or exactly five distinct attempts unlocks the proper vote; four does not. Same-stage other-version experience can qualify a like, never a new version's difficulty vote. Removing a vote works without playing again.
- **Counting:** deaths, fuel failures, abandonments and interrupted runs count; menus, paused tours, editor/proof flights and demo playback do not. Retry starts a new id, pause/resume does not, and post-first-clear replays cannot lower measured difficulty.
- **Offline/idempotency:** duplicate and lost-response retries, a start acknowledged while a finish is added, older offline reports, app restart and two-device histories do not double count or clear unsent data. Switching/deleting an account cannot reassign its outbox.
- **Ratings/review:** one mutable vote per player/version, upper median/count/low-sample display, no cross-version contamination; exactly one moderator label is needed for merge. Reviewed labels never modify level/demo hashes. Existing published versions remain usable as Not rated.
- **Privacy/security:** malformed or unauthenticated reports and ineligible votes fail, unknown/hidden versions do not poison the outbox, banned users cannot contribute public aggregates, deletion removes new data, and desktop performs no collection/network calls. No tokens, nonces or per-player history are exposed in public feedback.
- **UI smoke:** on a real Play-installed device, play/fail/retry a community version five times, rate it, toggle a like, clear it, replay without changing learning stats, then exercise offline synchronization. Review a new submission with a difficulty label and confirm the two ratings remain distinct in the catalogue. Existing game/server/levels-repo checks and all desktop exports remain green.
