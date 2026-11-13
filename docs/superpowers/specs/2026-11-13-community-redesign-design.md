# Community and My Levels Redesign

## Goal

Make the screens around community levels pleasant to look at and quick to read. A player should see at a glance how hard a level is, how popular it is, and how they have done on it. Replace today's pile of labels and raw counts with a difficulty rating derived from real player data, shown with its evidence. Give authors a My levels screen that is about their levels, not about buttons, and that shows how their published levels are doing.

This builds on `2026-10-22-community-feedback-design.md`, which defines likes, reviewed and player difficulty, attempt counting and play history; those rules stay unless this spec changes them. It also designs the skill-adjusted difficulty model that the owner agreed to on 2026-10-22 but deferred "until enough cross-level data exists". That model was never written down.

**Included:** the Community browser, the level details sheet, the My levels screen and its Publish flow, the derived difficulty rating, how statistics are computed and shown, and the server, API and schema changes they need.

**Excluded:** comments, text search, star ratings, a new popularity ranking, new analytics services or SDKs, changes to how attempts are counted or reported, and the official campaign screens.

## Decisions carried over from 2026-10-22

- Difficulty has separate sources that are never averaged together: **Reviewed** (one moderator label per version) and **player votes** (one per player and version, after a clear or 5 attempts). The owner asked for both.
- Play statistics count attempts only up to each player's first clear of a version.
- The owner's caveat: "a level many inexperienced players have problems with might be easy". A raw clear rate measures the audience as much as the level. The derived rating therefore adjusts for player skill.
- Online features stay Google Play Android only. Desktop builds keep My levels and the editor and never contact the server.

### What this spec supersedes in 2026-10-22

- Its exclusion of automatic, skill-adjusted difficulty labels (Goal and scope; Observed statistics, last paragraph). This spec adds one, with the gates below.
- Its rule that aggregates reflect an account deletion at once. Player-level data (play history, votes, likes) still goes at once; the derived per-version tables below are rebuilt at most 10 minutes later.
- Its statistics list. The details sheet shows the set below; the API keeps the old fields for older clients.

## Difficulty

### Three sources, one headline

| Source | What it is | Where it shows |
|---|---|---|
| **Rated** | Skill-adjusted rating derived from play data (below). | Row chip, details headline, filter. |
| **Reviewed** | Moderator's label on the approved version. | Row chip when there is no Rated label; always in details. |
| **Players** | Upper median of eligible players' votes, with 5 or more voters. | Row chip when there is neither Rated nor Reviewed; distribution always in details. |

The row chip shows one label and its source in its text: "Rated Hard" (filled), "Rated Normal–Hard" for a range, "Reviewed Hard" or "Players Hard" (outlined) for the fallbacks, and no chip when none exists. Rows never show "Not rated" or vote counts. The details sheet shows all three sources by name. When Rated and Reviewed differ by two or more steps, the details sheet says so in one line ("Players find it harder than the moderator rated it"); for a Rated range, the step count uses the range's nearer end.

The four labels keep the existing scale. Each has a colour (Easy green, Normal blue, Hard orange, Expert red), and the label text is always shown, so colour never carries meaning alone.

### The Rated model

**Question it answers:** how likely is a typical established community player to clear this version within 10 attempts? This does not depend on who happened to play this one level.

**Data:** one row per non-banned player and approved version of a visible level, from `play_summaries`: `a` = counted attempts (always at least 1), `c` = whether the player has cleared it. Older approved versions stay in the fit, so a new version does not lose the skill information they carry. These are the same first-clear histories the current statistics use. Nothing new is collected. In the fit only, `a` is capped at 30 (an uncleared history with more attempts counts as 30 misses; a clear after attempt 30 counts as a clear on attempt 30), so one grinding account cannot move a small level's rating far.

**Model:** each player `i` has a skill `θᵢ`, each version `j` a difficulty `βⱼ`. On any one counted attempt, the chance of a first clear is `p = σ(θᵢ − βⱼ)`, where `σ(x) = 1 / (1 + e^(−x))`. A history is a run of independent attempts:

- cleared on attempt `a`: likelihood `(1 − p)^(a − 1) · p`;
- not cleared after `a` attempts: likelihood `(1 − p)^a`. Abandoned and unfinished attempts count as misses, as they already count as attempts.

**Priors:** `θᵢ ~ Normal(0, 1.5²)` and `βⱼ ~ Normal(2.6, 2.5²)`. They make the fit identifiable. The skill prior keeps a player with one short history near 0, so a newcomer's single failure says little. The difficulty prior is centred where a player of skill 0 has a 50% chance to clear within 10 attempts (the Normal–Hard boundary), so an unplayed version leans to neither end, and it is wide enough to be overruled by a handful of players.

**Fitting** (`server/src/core/rating.ts`, pure TypeScript):

1. Start every `θ` at 0 and every `β` at 2.6 on every run. Nothing is warm-started or stored between runs.
2. Alternate passes: update every `θᵢ` with the `β`s fixed, then every `βⱼ` with the `θ`s fixed, each by one Newton step on its own one-dimensional log posterior, with the step clipped to ±1.
3. Stop when no value moved by more than 0.001 in a pass. If that has not happened after 200 passes, the run publishes nothing: the previous tables stay and the run logs the failure.

**Uncertainty:** the marginal variance of `βⱼ` accounts for the estimated skills of its players through the Schur complement of the joint Hessian, which is cheap because skills only couple through shared versions:

`Vⱼ = 1 / (Hⱼ − Σᵢ wᵢⱼ² / Hᵢ)`,

where `Hⱼ` and `Hᵢ` are the second derivatives of the negative log posterior in `βⱼ` and `θᵢ`, and `wᵢⱼ` is the cross derivative from player `i`'s history on version `j`. `sdⱼ = √Vⱼ`.

**Reference player:** the typical established player has skill `θ_ref`, the mean fitted skill of players with counted attempts on at least 3 different levels whose latest attempt is within the last 180 days. With fewer than 20 such players, there is no reference and every version is Estimating.

**Rating:** `P10ⱼ = 1 − (1 − σ(θ_ref − βⱼ))^10`, the chance that the reference player clears within 10 attempts. Its 90% interval comes from `βⱼ ± 1.645 · sdⱼ`.

| P10 | Label |
|---|---|
| 80% or more | Easy |
| 50% to under 80% | Normal |
| 20% to under 50% | Hard |
| Under 20% | Expert |

**Gates.** A version gets a Rated label only when all hold:

1. at least 10 distinct starters (the existing display floor);
2. at least 5 of those starters have counted attempts on at least one other **level** (another version of the same level does not count), so skill is estimated from more than this one level;
3. the 90% interval of `P10` lies within one band, or within two adjacent bands. Two adjacent bands show as a range ("Normal–Hard") and filter under both.

Otherwise the version is **Estimating**, and the row falls back to the Reviewed or Players chip.

The required acceptance case is the owner's caveat: an easy level that 15 newcomers (no other level played) fail repeatedly while 6 established players clear it at once must not get a Rated label harder than Normal; with the marginal interval above, it gets no label at all.

**Stability:** a published Rated label changes only when the new interval clears the old band's edge by 2 percentage points, so a version near a boundary does not flip every 10 minutes.

The bands, the 10-attempt budget, the 30-attempt cap, the reference window and the gates are product thresholds kept as named constants in `core/rating.ts`, to be retuned once real data exists.

**Known limits, stated once in the details sheet's help text:** the rating describes the Android Play audience, not desktop players. A player who quits early is counted only for the attempts they made, so a level that drives people away after one try can look easier than it is. Each new version starts Estimating; the previous version's label is not carried over.

### Player votes

Voting rules stay as they are. The details sheet shows the distribution as four labelled bars with counts, plus the voter total, and the upper-median label only at 5 or more voters. The vote control becomes four toggle buttons (Easy, Normal, Hard, Expert) instead of a dropdown, and appears only when the player is eligible for this version's vote; before that, one progress line takes its place ("Clear it or try 2 more times to vote"). Tapping the selected vote removes it, as **Remove my vote** does today. Like and vote eligibility stay independent: the Like toggle has its own progress line while locked, and experience on an earlier version can unlock Like while the vote stays locked.

## Statistics

The per-version statistics are reorganised around one picture and three numbers. All describe the players so far on this version, counted up to each player's first clear. They are plain observed shares; nothing is extrapolated.

- **Clear curve:** the share of starters who cleared on or before attempt `t`, for `t` from 1 to 30. Players who stopped without clearing stay in the denominator, as they do in the rating. Drawn by one small custom `Control` with `draw_polyline`, with a dashed line at 50%. Hidden below 10 starters.
- **Players:** distinct starters on this version.
- **Cleared:** distinct players who cleared. The percentage appears only at 10 or more starters.
- **Not cleared:** distinct players who have not cleared, and how many of them tried 20 or more times ("42 not cleared, 9 of them after 20+ tries"). This replaces the three "still unbeaten" counts.

When the Rated sentence and the curve tell different stories, one line explains why: "Players so far were stronger than typical" or "weaker than typical", from the mean fitted skill of this version's starters against `θ_ref`, shown only when that difference is at least 0.5.

Removed from the sheet: total attempts, attempts per first clear, median tries among finishers, and the three separate "still unbeaten" counts. The API keeps those fields for older clients.

## Popularity

Likes keep their rules and their order. The "Top" tab is renamed **Popular** and keeps today's ranking (likes, then distinct scoring players).

## Community browser

**Header:** Back, "Community", a segmented **Popular | New** control, and a gear button for Community settings (account deletion), replacing the full Settings button. Below it, filter chips **All · Easy · Normal · Hard · Expert**. A level matches a chip when its row chip (Rated, a Rated range, Reviewed or Players) includes that difficulty. Levels with no chip appear only under All.

**Rows** follow the official levels' row pattern (`main.gd` `_row`): the whole row is one button that opens details, and Play is a separate primary button at its right end. Each row shows:

- thumbnail (128×72);
- title (24 px) over "by Nova" (18 px, dim);
- one meta line: difficulty chip, ♥ 42, "64 players" (distinct starters on the latest version);
- the player's own status at the right, from data already on the device (`Progress` best score and medal, `Community.play_progress` attempts and clear): medal, "Cleared", "3 tries", or nothing if never played.

Version numbers move to the details sheet. Rows are 92 px high with 8 px between them. The banner ad's reserved footer varies with screen density (`MonetizationChrome`: 66 px at density 1, about 121 px on a 2400×1080 phone), so at least three full rows are visible on a typical phone and four at density 1; the list scrolls for the rest.

**States:** a first load shows three placeholder rows; a refresh keeps the existing rows until the new page arrives. Empty states: "No levels yet", "No Hard levels yet" with a **Show all** button, and an "Offline: showing saved levels" banner over cached rows. The offline cache keeps one file per sort, filter and page.

## Details sheet

The sheet's backdrop is fully opaque so the list does not show through. Order, top to bottom:

1. **Hero:** thumbnail (320×180) beside the title, "by Nova · version 3", the large difficulty chip with its source, "♥ 42 · 64 players", and the primary **Play**.
2. **Difficulty:** Rated with its sentence ("A typical player clears it within 10 tries 35–55% of the time"), or "Estimating · 7 players"; Reviewed; the vote distribution; the disagreement line when it applies.
3. **How players did:** the clear curve, the three numbers and the stronger/weaker line when it applies.
4. **You:** your tries and whether you cleared, your best score and medal, the Like toggle, and the vote buttons once eligible. Before eligibility, one progress line replaces each locked control. Pending sync, refusals and the sync indicator keep their current behaviour.

All of it reads from one feedback answer, which comes from the same derived tables as the list, so the row and the sheet always agree. The result screen's **Rate level** opens the same sheet scrolled to **You**.

## My levels

**Header:** Back, "My levels", **New level** (primary) and Import.

**Rows** use the same row pattern. Each row: thumbnail, full title (no 200 px truncation), and one status line:

| Status | When |
|---|---|
| Needs fixes: ship starts inside planet 1 | the draft fails validation; the first problem, in player terms |
| Not tested yet | valid, never cleared in a test flight |
| Ready to publish | cleared, no submission |
| In review | submitted, open |
| Rejected: (moderator's comment) | rejected |
| Published v2 · Hard · 64 players · ♥ 42 | approved; the latest approved version's chip label and stats |
| Published v2 · edited since | approved, and the local draft's hash differs from the approved version's hash |

Desktop builds and Android without the Community feature show only the first three statuses and never Publish, as today. Offline on Android, the published and review statuses come from the last known statuses (as `Community.statuses()` already does) and the Published line drops the chip and numbers it does not have.

Validation messages name body kinds ("planet 1", "star 2") instead of "body 0", in both `level_format.gd` and the server's `core/level.ts`.

**Tapping a row** opens the level's sheet: Edit (primary), Play, Watch (when a demo exists), Publish, Export, and Delete last in a danger colour, still behind its confirmation.

**Publish** becomes one sheet with numbered steps: 1. Prove it can be finished (✓ with the saved run, or Play to prove it), 2. Suggest a difficulty, 3. Submit for review. It names the level, keeps the existing proof and submission checks, and keeps the note that a moderator sets the reviewed difficulty. Nothing uploads before Submit.

## Server, API and schema

Migration 0009 adds one derived table, `version_stats`, rebuilt by the scheduled job:

`sha256` (primary key), `starters`, `clears`, `not_cleared_20` (starters without a clear after 20 or more attempts), `curve` (JSON array of 30 cleared shares), `beta`, `beta_sd`, `p10_low`, `p10_high`, `rated` (`easy`…`expert` or null), `rated_high` (upper label of a two-band range, or null), `audience` (mean fitted skill of the starters minus `θ_ref`, or null), `computed_ms`.

Per-player skills exist only in memory during a run. Nothing account-linked is stored, so `DELETE /me` needs no change.

**Scheduled job:** the existing 10-minute cron adds one step after the ranking: read the summaries of non-banned players on all approved versions of visible levels, run the fit and the curves (`core/rating.ts`), and replace `version_stats` in one batch, keeping each version's previous label where the stability rule holds it. The service runs on the Workers Paid plan (30 s of CPU per scheduled run by default); a scratch run of 50 passes over 133,000 rows took about 0.2 s in Node.

**`GET /levels`:** `sort=popular|new` (`top` stays an alias of `popular` for older clients), optional `difficulty=easy|normal|hard|expert`. Each row adds `rated`, `rated_high` and `starters`, and keeps every existing field with its current meaning (including `players`, distinct scoring players across versions, which still breaks ties in Popular).

**`GET /levels/:id/feedback`:** adds `rated`, `rated_high`, `p10_low`, `p10_high`, `curve`, `not_cleared_20`, `audience`, `starters` and `votes` (counts per label), all read from `version_stats` and the vote table. Keeps every existing field.

**Submission statuses:** approved entries add the approved `sha256`, and the latest approved version's `rated`, `rated_high`, `reviewed_difficulty`, `starters` and `likes`.

Privacy wording adds one sentence: play history is also used to estimate each level's difficulty with a model of player skill; the skill estimates are temporary and are neither stored nor shown. The in-app account deletion sentence ("This removes your scores, likes, reports and your name…") adds play history and difficulty votes, which it already deletes but does not mention.

## Testing

- `core/rating.ts`, against numeric reference values, not only orderings:
  - recovers known skills and difficulties from synthetic histories within stated tolerances;
  - a level played only by weak players rates easier than its raw clear rate suggests;
  - converges on the oscillating case (a near-trivial level plus one account with 300 failures) and publishes nothing when the pass limit is hit;
  - the Schur-complement interval reaches at least 80% coverage on simulated data;
  - gates hold back small, single-level and same-level-versions cohorts; the owner's caveat case (see Gates) gets no label; a two-band interval yields a range; the stability rule holds a label near a band edge.
- Curve and counts against hand-computed cases, including early quitters and one heavy grinder.
- Worker: the cron step excludes banned and deleted players; `/levels` filters and sorts; `sort=top` still works; the list and the feedback answer agree; existing fields keep their meaning.
- App: rows, chips and states for Rated, range, Reviewed, Players and no-chip levels; filter chips and the offline cache per filter; the details sheet order and eligibility states; My levels statuses, including "edited since", and the Publish steps; keyboard and gamepad focus; screenshots of each screen at 1280×720 with the banner ad shown, reviewed before merge.
