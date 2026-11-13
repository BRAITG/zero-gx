# Community and My Levels Redesign

## Goal

Make the screens around community levels pleasant to look at and quick to read. A player should see at a glance how hard a level is, how popular it is, and how they have done on it. Replace today's pile of labels and raw counts with a difficulty rating derived from real player data, shown with its evidence. Give authors a My levels screen that is about their levels, not about buttons, and that shows how their published levels are doing.

This builds on `2026-10-22-community-feedback-design.md`, which defines likes, reviewed and player difficulty, attempt counting and play history; those rules stay unless this spec changes them. It also designs the skill-adjusted difficulty model that the owner agreed to on 2026-10-22 but deferred "until enough cross-level data exists". That model was never written down.

**Included:** the Community browser, the level details sheet, the My levels screen and its Publish flow, the derived difficulty rating, how statistics are computed and shown, and the server, API and schema changes they need.

**Excluded:** comments, text search, star ratings, new analytics services or SDKs, changes to how attempts are counted or reported, and the official campaign screens.

## Decisions carried over from 2026-10-22

- Difficulty has separate sources that are never averaged together: **Reviewed** (one moderator label per version) and **player votes** (one per player and version, after a clear or 5 attempts). The owner asked for both.
- Play statistics count attempts only up to each player's first clear of a version.
- The owner's caveat: "a level many inexperienced players have problems with might be easy". A raw clear rate measures the audience as much as the level. The derived rating therefore adjusts for player skill.
- Online features stay Google Play Android only. Desktop builds keep My levels and the editor and never contact the server.

## Difficulty

### Three sources, one headline

| Source | What it is | Where it shows |
|---|---|---|
| **Rated** | Skill-adjusted rating derived from play data (below). | Row chip, details headline, filter. |
| **Reviewed** | Moderator's label on the approved version. | Row chip only when there is no Rated label; always in details. |
| **Player votes** | Distribution of eligible players' votes. | Details only. |

The row chip shows one label and always says where it came from: a filled chip for Rated ("Hard"), an outlined chip tagged "Reviewed" when only a moderator label exists, and a plain "New" chip when there is neither. Rows never show "Not rated" or vote counts. The details sheet shows all three sources by name. When Rated and Reviewed differ by two or more steps, the details sheet says so in one line ("Players find it harder than the moderator rated it").

The four labels keep the existing scale and colours that never carry meaning alone (the label text is always shown): Easy green, Normal blue, Hard orange, Expert red.

### The Rated model

**Question it answers:** how likely is a typical community player to clear this version within 10 attempts? "Typical" means a player of average skill among the active community, so the rating does not depend on who happened to play this one level.

**Data:** one row per non-banned player and approved, visible version, from `play_summaries`: `a` = counted attempts (always at least 1), `c` = whether the player has cleared it. These are the same first-clear histories the current statistics use. Nothing new is collected.

**Model:** each player `i` has a skill `θᵢ`, each version `j` a difficulty `βⱼ`. On any one counted attempt, the chance of a first clear is `p = σ(θᵢ − βⱼ)`, where `σ(x) = 1 / (1 + e^(−x))`. A history is a run of independent attempts:

- cleared on attempt `a`: likelihood `(1 − p)^(a − 1) · p`;
- not cleared after `a` attempts: likelihood `(1 − p)^a`. Abandoned and unfinished attempts count as misses, as they already count as attempts.

**Priors:** `θᵢ ~ Normal(0, 1.5²)` and `βⱼ ~ Normal(0, 2²)`. The skill prior's mean of 0 defines the typical player and makes the model identifiable. A player with one short history stays near 0, so a newcomer's single failure says little.

**Fitting:** maximum a posteriori by alternating one-dimensional Newton steps: update every `θᵢ` with the `β`s fixed, then every `βⱼ` with the `θ`s fixed. Each update needs only the player's or version's own rows. Start from the values saved by the previous run, so a run of 5 alternating passes converges after a few runs and stays cheap. New players and versions start at 0.

**Uncertainty:** `sdⱼ = 1 / √Hⱼ`, where `Hⱼ` is the second derivative of the negative log posterior in `βⱼ` (skills held fixed). This understates the true uncertainty slightly, which the gates below compensate for.

**Rating:** `P10ⱼ = 1 − (1 − σ(−βⱼ))^10`, the chance that a player with `θ = 0` clears within 10 attempts. Its 90% interval comes from `βⱼ ± 1.645 · sdⱼ`.

| P10 | Label |
|---|---|
| 80% or more | Easy |
| 50% to under 80% | Normal |
| 20% to under 50% | Hard |
| Under 20% | Expert |

**Gates.** A version gets a Rated label only when all hold:

1. at least 10 distinct starters (the existing display floor);
2. at least 5 of those starters have counted attempts on at least one other version, so skill is estimated from more than this one level;
3. the 90% interval of `P10` lies within one band, or within two adjacent bands. Two adjacent bands show as a range ("Normal–Hard") and filter under both.

Otherwise the version is **Estimating**. Rows then fall back to the Reviewed chip or "New"; the details sheet says "Estimating · 7 players" and shows the raw statistics.

The bands and the 10-attempt budget are product thresholds kept as named constants in one place (`server/src/core/rating.ts`), to be retuned once real data exists.

**Known limits, stated once in the details sheet's help text:** the rating describes the Android Play audience, not desktop players. Players who quit early are counted as missing their remaining attempts only as far as they played, so a level that drives people away after one try can look easier than it is. Each new version starts Estimating; the previous version's label is not carried over.

### Player votes

Voting rules stay as they are. The details sheet shows the distribution as four labelled bars with counts, plus the voter total, and the upper-median label only at 5 or more voters. The vote control becomes four toggle buttons (Easy, Normal, Hard, Expert) instead of a dropdown, and appears only when the player is eligible; before that, a single progress line takes its place ("Clear it or try 2 more times to vote").

## Statistics

The per-version statistics are reorganised around one picture and three numbers. All of them describe the players so far on this version, counted up to each player's first clear.

- **Clear curve:** share of starters who have cleared by attempt `t`, for `t` = 1 to 30, from the Kaplan–Meier estimate over the same histories (players who have not cleared are censored at their attempt count rather than counted as failures). Drawn by one small custom `Control` with `draw_polyline`, with a dashed line at 50%. Hidden below 10 starters.
- **Players:** distinct starters.
- **Cleared:** distinct players who cleared, with the percentage.
- **Half clear within:** the Kaplan–Meier median ("6 tries", or "more than 30 tries" when the curve never reaches 50%). Hidden below 10 starters.

Removed from the sheet: total attempts, attempts per first clear, median tries among finishers, and the three "still unbeaten" counts. The curve shows all of that without letting one grinder dominate. The API keeps those fields for older clients.

## Popularity

Likes keep their rules. The "Top" tab becomes **Popular**, ranked by the 95% Wilson lower bound of likes divided by players eligible to like the stage (a clear or 5 attempts on any version). This stops early levels from staying on top only because they have had longer to collect hearts. Rows still show the heart count.

## Community browser

**Header:** Back, "Community", a segmented **Popular | New** control, and a gear button for Community settings (account deletion), replacing the full Settings button. Below it, filter chips **All · Easy · Normal · Hard · Expert**. A level matches a chip when its displayed label (Rated, a Rated range, or Reviewed) includes that difficulty. "New" levels appear only under All.

**Rows** follow the official levels' row pattern (`main.gd` `_row`): the whole row is one button that opens details; Play is a separate primary button at its right end. Each row shows:

- thumbnail (164×92);
- title (24 px) over "by Nova" (18 px, dim);
- one meta line: difficulty chip, ♥ 42, 64 players;
- the player's own status at the right: medal, "Cleared", "3 tries", or nothing if never played.

Version numbers move to the details sheet. Rows are about 110 px high so five fit on screen with the ad banner.

**States:** a first load shows three placeholder rows; a refresh keeps the existing rows until the new page arrives. Empty states: "No levels yet", "No Hard levels yet" with a **Show all** button, and an "Offline: showing saved levels" banner over cached rows.

## Details sheet

The sheet's backdrop is fully opaque so the list does not show through. Order, top to bottom:

1. **Hero:** thumbnail (320×180) beside the title, "by Nova · version 3", the large difficulty chip with its source, "♥ 42 · 64 players", and the primary **Play**.
2. **Difficulty:** Rated with its sentence ("A typical player clears it within 10 tries 35–55% of the time"), or "Estimating · 7 players"; Reviewed; the vote distribution; the disagreement line when it applies.
3. **How players did:** the clear curve and the three numbers.
4. **You:** your tries and whether you cleared, your best score and medal, the Like toggle, and the four vote buttons once eligible. Before eligibility, one progress line replaces the controls. Pending sync, refusals and the sync indicator keep their current behaviour.

The result screen's **Rate level** opens the same sheet scrolled to **You**.

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
| Published v2 · Hard · 64 players · ♥ 42 | approved; the latest approved version's Rated or Reviewed label and stats |
| Published v2 · edited since | approved, and the local draft differs from the approved version |

Validation messages name body kinds ("planet 1", "star 2") instead of "body 0", in both `level_format.gd` and the server's `core/level.ts`.

**Tapping a row** opens the level's sheet: Edit (primary), Play, Watch (when a demo exists), Publish, Export, and Delete last in a danger colour, still behind its confirmation.

**Publish** becomes one sheet with numbered steps: 1. Prove it can be finished (✓ with the saved run, or Play to prove it), 2. Suggest a difficulty, 3. Submit for review. It names the level, keeps the existing proof and submission checks, and keeps the note that a moderator sets the reviewed difficulty. Nothing uploads before Submit.

## Server, API and schema

Migration 0009 adds three tables, all derived and rebuilt by the scheduled job:

- `version_stats`: `sha256` (primary key), `starters`, `clears`, `km_median` (null when not reached), `curve` (JSON array of 30 cleared shares), `beta`, `beta_sd`, `rated` (`easy`…`expert` or null), `rated_high` (upper label of a two-band range, or null), `computed_ms`.
- `player_skill`: `player` (primary key), `theta`. Used only to warm-start the fit; never exposed.
- `level_stats`: `level` (primary key), `likes`, `eligible`, `like_score`.

**Scheduled job:** the existing 10-minute cron adds one step after the ranking: read the grouped summaries of non-banned players on visible versions, run the fit (`core/rating.ts`, pure and unit-tested), compute curves, medians and like scores, and replace the three tables in one batch. Bans and account deletions are reflected at the next run. shortcut: every run refits everything; switch to changed-versions-only when the job's time approaches the plan's CPU limit.

**`GET /levels`:** `sort=popular|new` (`top` stays an alias of `popular` for older clients), optional `difficulty=easy|normal|hard|expert`. Each row adds `rated`, `rated_high`, `players` and keeps `reviewed_difficulty`, `likes` and the existing fields.

**`GET /levels/:id/feedback`:** reads `version_stats` so the row and the sheet always agree. Adds `rated`, `rated_high`, `p10_low`, `p10_high`, `curve`, `km_median` and `votes` (counts per label). Keeps every existing field.

**`GET` submission statuses:** approved entries add the latest version's `rated`, `reviewed_difficulty`, `players` and `likes`.

No new collection: privacy wording needs one addition, that a skill estimate per player is computed from the existing play history and used only to rate levels, never shown.

## Testing

- `core/rating.ts`: fits synthetic histories with known skills and difficulties and recovers the order of levels; a level played only by weak players rates easier than its raw clear rate suggests; gates hold back labels on small or isolated samples; a two-band interval yields a range.
- Kaplan–Meier median and curve against hand-computed cases, including censored players and one heavy grinder.
- Worker: the cron step excludes banned and deleted players; `/levels` filters and sorts; old `sort=top` still works; feedback and list agree.
- App: rows, chips and states render for Rated, range, Reviewed-only and New levels; filter chips; the details sheet order and eligibility states; My levels statuses and the Publish steps; keyboard and gamepad focus; screenshots of each screen at 1280×720 reviewed before merge.
