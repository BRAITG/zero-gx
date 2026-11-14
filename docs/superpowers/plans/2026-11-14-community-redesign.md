# Community and My Levels Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the skill-adjusted Rated difficulty, the redesigned Community browser, details sheet and My levels screen described in the spec.

**Architecture:** A pure TypeScript fit (`server/src/core/rating.ts`) runs in the existing 10-minute cron and rebuilds one derived D1 table, `version_stats`. `GET /levels`, `GET /levels/:id/feedback` and `GET /me/submissions` read it, keeping every existing field. The Godot screens are rebuilt in code on the existing `Style`, `Overlay` and `main.gd` row patterns, with two new small controls: a difficulty chip and a clear curve.

**Tech Stack:** Godot 4.7.2 GDScript (tests: `tests/run.sh`), Cloudflare Workers + D1 TypeScript (tests: `cd server && npm test`, `npm run typecheck`).

**Spec:** `docs/superpowers/specs/2026-11-13-community-redesign-design.md`. Read it whole before any task; this plan does not repeat its formulas.

## Global Constraints

- No new dependencies in the game or the server. No new analytics services.
- Every existing API field keeps its meaning; `sort=top` stays an alias of `popular`. Older app builds must keep working.
- Online features stay Google Play Android only; desktop and non-Community builds make no requests.
- Per-player skills are never stored or exposed. `DELETE /me` needs no change.
- Constants live in `server/src/core/rating.ts`: `BUDGET = 10`, `CAP = 30`, bands `[0.8, 0.5, 0.2]`, `MIN_FIT_STARTERS = 10`, `MIN_REFERENCE = 20`, `REFERENCE_LEVELS = 3`, `REFERENCE_DAYS = 180`, `HOLD_POINTS = 0.02`, `MAX_PASSES = 200`, `TOLERANCE = 0.001`, `STEP_CLIP = 1`, priors `θ ~ N(0, 1.5²)`, `β ~ N(2.6, 2.5²)`, `Z90 = 1.645`.
- Chip text always names its source: "Rated Hard", "Rated Normal–Hard", "Reviewed Hard", "Voted Hard". Colours: Easy green, Normal blue, Hard orange, Expert red; text always shown.
- UI must work with touch, keyboard and gamepad focus (`Style.focus_first`, sibling buttons, `Overlay` back handling).
- Commits: Conventional Commits, one per task minimum; push the branch after each task.

## Review Focus

1. **A version with zero clears and many starters** must still produce a finite fit and an Expert or Estimating label, never NaN. Test in Task 1.
2. **A catalogue with only one level or no reference players** must publish Estimating everywhere and still refresh raw statistics. Test in Task 2.
3. **A banned or deleted player** must vanish from `version_stats` at the next cron run, including the curve and counts. Test in Task 2.
4. **An older app calling `/levels?sort=top` without `difficulty`** gets the same rows and fields as before, plus the new ones. Test in Task 3.
5. **A long title, a deleted author and a level with no chip** must render without overflow or an empty gap in the row. Test in Task 6.

---

### Task 1: The rating model (`core/rating.ts`)

**Files:**
- Create: `server/src/core/rating.ts`
- Test: `server/test/rating.test.ts`

**Interfaces:**
- Produces:
  - `type Label = Difficulty` (from `./difficulty`).
  - `interface History { player: string; level: string; sha256: string; attempts: number; cleared: boolean; lastMs: number }`
  - `interface VersionRating { sha256: string; starters: number; clears: number; notCleared20: number; curve: number[] /* 30 shares */; beta: number | null; ratingSd: number | null; p10Low: number | null; p10High: number | null; rated: Label | null; ratedHigh: Label | null; audience: number | null }`
  - `function rate(histories: History[], previous: Map<string, { rated: Label | null; ratedHigh: Label | null }>, nowMs: number): { versions: VersionRating[]; fitted: boolean }`
  - `function fit(histories: History[]): { theta: Map<string, number>; beta: Map<string, number>; converged: boolean }` (exported for tests)
  - `function bandOf(p10: number): Label`

- [ ] **Step 1: Write the failing tests** in `server/test/rating.test.ts`, each with numeric reference values:
  - `clips one Newton step to ±1`
  - `converges on a near-trivial level plus one 300-failure account that plays a second level`
  - `marks fitted=false and every version Estimating after MAX_PASSES without convergence` (force with `MAX_PASSES` override parameter or a pathological input)
  - `V equals the dense inverse of the full joint Hessian` on a 6-player, 3-version catalogue (to 1e-9)
  - `censors histories over 30 attempts as 30 misses`: 60 established players clear three levels at once and the target at attempt 1,000 → `rated === "expert"`, `p10High < 0.025`
  - `fixture (a)`: L1–L3 rate `normal`; L4–L5 `rated === null`
  - `owner's caveat`: alone → all null; inside 24 reference players with 6 established starters → null; with 10 → `easy`; never `hard` or `expert` for any newcomer count in [15, 30, 100] × failures [5, 10, 30]
  - `zero clears with 40 starters` → finite numbers, `rated` in `{expert, null}`
  - `curve and counts` against a hand-computed case with early quitters and one grinder (`curve[29]` below `clears/starters` when a clear came after 30)
  - `stability holds a label only while gates pass and the interval overlaps it within 2 points`
  - `coverage`: 500 simulated catalogues, 90% interval of `θ_ref − β` covers truth in 85–95% (seeded RNG, mark as slow if > 5 s)

- [ ] **Step 2: Run** `cd server && npx vitest run test/rating.test.ts`. Expected: FAIL, module not found.

- [ ] **Step 3: Implement `rating.ts`** exactly per the spec's "The Rated model" section: drop one-level players from the fit (levels, not versions), cap/censor at 30, cold start (θ=0, β=2.6), alternating clipped Newton passes, Schur-complement variance with the pinned signs (`H_βθ` entries `−a·p(1−p)`), reference set from `lastMs`, gates, bands, hysteresis. Dense `S` inverse by Gauss–Jordan; add `// shortcut: dense inverse of S; switch to a sparse solver past ~1,500 versions`. Non-PD `S` or `V ≤ 0` → `fitted: false`. Curves and counts use every non-fit starter too. `audience`: skills of left-out starters re-estimated with β fixed.

- [ ] **Step 4: Run** the same command. Expected: PASS. Then `npm run typecheck`: no errors.

- [ ] **Step 5: Commit** `feat(server): add skill-adjusted rating model`.

### Task 2: Schema and cron step

**Files:**
- Create: `server/migrations/0009_version_stats.sql`
- Modify: `server/src/plays.ts` (`SUMMARY` sets `last_ms`), `server/src/community.ts` (`runCron` adds `step("ratings", …)`)
- Test: `server/test/worker/community.test.ts`, `server/test/worker/migrations.test.ts`

**Interfaces:**
- Consumes: `rate()` from Task 1.
- Produces: table `version_stats(sha256 TEXT PRIMARY KEY REFERENCES versions, starters, clears, not_cleared_20, curve TEXT, beta, rating_sd, p10_low, p10_high, rated, rated_high, audience, computed_ms)`; column `play_summaries.last_ms INTEGER`; `export async function recomputeRatings(env: Env): Promise<void>`.

- [ ] **Step 1: Write failing worker tests**: `recomputeRatings fills version_stats for visible versions`; `a banned player disappears from counts and curve at the next run`; `a deleted player disappears at the next run`; `no reference players → every rated null, counts still fresh`; `migration backfills last_ms as max received_ms per player and version`.
- [ ] **Step 2: Run** `npx vitest run test/worker/community.test.ts test/worker/migrations.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement** the migration (add column, backfill, create table), `SUMMARY` setting `last_ms` to the batch's `received` time, and `recomputeRatings`: one query of summaries of non-banned players on approved versions of visible levels, `rate()`, previous labels from `version_stats`, then one `env.DB.batch` that deletes and reinserts `version_stats`. When `fitted` is false, still write counts and curves with null rating fields and `console.error`.
- [ ] **Step 4: Run** the tests and `npm test`. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(server): rebuild version stats and ratings in the cron`.

### Task 3: API fields

**Files:**
- Modify: `server/src/community.ts` (`getLevels`), `server/src/feedback.ts` (`getFeedback`), `server/src/submissions.ts` (`getMySubmissions`)
- Test: `server/test/worker/community.test.ts`, `feedback.test.ts`, `submissions.test.ts`

**Interfaces:**
- Produces (JSON):
  - `GET /levels?sort=popular|new|top&page=N[&difficulty=easy|normal|hard|expert]` rows add `rated`, `rated_high`, `starters` (null/0 when no `version_stats` row). The filter matches when the row's chip label (Rated or range, else Reviewed, else Voted upper median with ≥5 voters) includes the difficulty, applied in SQL before `LIMIT`.
  - `GET /levels/:id/feedback` adds `rated`, `rated_high`, `p10_low`, `p10_high`, `curve` (array), `not_cleared_20`, `audience`, `starters`, `votes: {easy, normal, hard, expert}`.
  - `GET /me/submissions` approved rows add `sha256`, `rated`, `rated_high`, `reviewed_difficulty`, `starters`, `likes`.

- [ ] **Step 1: Write failing tests**: `sort=top equals sort=popular and keeps every old field`; `difficulty=hard filters before paging, ranges match both bands, Voted needs 5 voters`; `400 for an unknown difficulty`; `feedback and list report the same rated and starters`; `approved submissions carry the approved sha256 and stats`.
- [ ] **Step 2: Run** the three test files. Expected: FAIL.
- [ ] **Step 3: Implement** with `LEFT JOIN version_stats`; Voted fallback computed in SQL from `difficulty_votes` the way `communityLabels` does, or by moving the upper-median into a SQL `CASE` (keep `upperMedianDifficulty` as the single rule; add a test that both agree).
- [ ] **Step 4: Run** `npm test && npm run typecheck`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): expose ratings, filters and author stats`.

### Task 4: Validation messages name body kinds

**Files:**
- Modify: `scripts/level_format.gd` (lines 146–211, 474), `server/src/core/level.ts` (lines 119–227), `tools/make_fixtures.gd` if a substring changes, `fixtures/expected.json` (regenerated)
- Test: `tests/test_level_format.gd`, `server/test/level.test.ts`

**Interfaces:**
- Produces: messages use `"<kind> <n>"` with 1-based numbering per kind, e.g. `"the ship starts inside planet 1"`, `"star 2: a star's total pull must be 150 to 5000"`. Body numbering: the n-th body of that kind in file order. Identical text in GDScript and TypeScript.

- [ ] **Step 1: Write failing tests** in both suites: `a ship inside the second planet reports "planet 2"`; `a star out of range reports "star 1: a star's…"`.
- [ ] **Step 2: Run** `TEST_FILTER=test_level_format.gd GODOT=godot tests/run.sh` and `npx vitest run test/level.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement** one helper per language, `body_name(bodies, i)` / `bodyName(bodies, i)`, used by every body message.
- [ ] **Step 4: Regenerate fixtures** `godot --headless --path . -s tools/make_fixtures.gd`, then run both full suites. Expected: PASS, `git diff fixtures/` shows only message changes.
- [ ] **Step 5: Commit** `fix(levels): name bodies by kind in validation messages`.

### Task 5: Client data and shared controls

**Files:**
- Modify: `scripts/community.gd` (`list`, `statuses`)
- Create: `scenes/difficulty_chip.gd` (`class_name DifficultyChip extends PanelContainer`), `scenes/clear_curve.gd` (`class_name ClearCurve extends Control`)
- Test: `tests/test_community.gd`, `tests/test_community_widgets.gd` (new)

**Interfaces:**
- Produces:
  - `Community.list(sort: String, page: int, difficulty := "") -> Dictionary` — cache file `list_<sort>_<difficulty or all>_<page>.json`; `sort` is `"popular"` or `"new"`.
  - `Community.statuses()` keeps its shape and adds, for approved rows, `sha256`, `rated`, `rated_high`, `reviewed_difficulty`, `starters`, `likes`.
  - `DifficultyChip.of(row: Dictionary) -> DifficultyChip` (null-safe: returns null when no source), `DifficultyChip.text_of(row: Dictionary) -> String` ("Rated Normal–Hard", "Reviewed Hard", "Voted Hard", "").
  - `ClearCurve.new(curve: Array) ` draws shares 1..30 with `draw_polyline` and a dashed 50% line; `custom_minimum_size = Vector2(480, 160)`.

- [ ] **Step 1: Write failing tests**: `list caches per filter and serves the right cache offline`; `text_of picks Rated, then Reviewed, then Voted with 5+ voters, else empty`; `ClearCurve ignores malformed entries` (non-numbers → 0, length capped at 30).
- [ ] **Step 2: Run** `TEST_FILTER=test_community GODOT=godot tests/run.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.** Chip colours from Global Constraints; filled `StyleBoxFlat` for Rated, border-only for the fallbacks; label 18 px.
- [ ] **Step 4: Run** the full game suite. Expected: PASS.
- [ ] **Step 5: Commit** `feat(community): add difficulty chip, clear curve and filtered lists`.

### Task 6: Community browser

**Files:**
- Modify: `scenes/community_screen.gd`
- Test: `tests/test_community_screens.gd`

**Interfaces:**
- Consumes: `Community.list`, `DifficultyChip`, `CommunityLevelDetails.open`, `Progress.medal`, `Community.play_progress`.

- [ ] **Step 1: Update and add tests** (delete ones pinning the old text line): `rows show title, "by <author>", chip, hearts and "<n> players"`; `row button opens details, Play is a sibling button`; `Popular/New and filter chips request the right sort and difficulty`; `empty filter shows "No Hard levels yet" and Show all`; `refresh keeps rows until the page arrives`; `offline banner over cached rows`; `long title and no chip render without overflow (title ellipsis, no empty chip gap)`; `gear opens Community settings`.
- [ ] **Step 2: Run** `TEST_FILTER=test_community_screens GODOT=godot tests/run.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** per spec "Community browser": row 100 px high, 8 px gaps, thumbnail 128×72, title 24 px, byline 18 px dim, meta line, own status right-aligned; header Back · title · Popular|New segmented · gear; filter row; three placeholder rows on first load.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Render** a throwaway screenshot script (pattern: earlier `/tmp/cr` renders) at 1280×720 with `Monetization` footer shown; view it; delete the script.
- [ ] **Step 6: Commit** `feat(community): redesign the level browser`.

### Task 7: Details sheet

**Files:**
- Modify: `scenes/community_level_details.gd`, `scenes/overlay.gd` (opaque backdrop option)
- Test: `tests/test_community_screens.gd`, `tests/test_community_feedback_ui.gd`

**Interfaces:**
- Consumes: feedback fields from Task 3, `DifficultyChip`, `ClearCurve`.
- Produces: `Overlay.open(parent, title, allow_monetization := false, opaque := false)`.

- [ ] **Step 1: Update and add tests** (keep every pending/refusal/account-switch test; replace assertions on removed text): `hero shows thumbnail, byline with version, chip and Play`; `Rated sentence shows p10 interval as "35–55%"`; `Estimating · N players` below gates; `disagreement line at two steps`; `vote distribution shows four counts and total`; `vote buttons appear only when eligible; tapping the selected one removes the vote`; `Like keeps its own progress line`; `curve and Cleared % hidden below 10 starters`; `"N cleared after more than 30 tries" caption`; `audience line only when |audience| ≥ 0.5`; `Rate level opens scrolled to You`.
- [ ] **Step 2: Run** the two files. Expected: FAIL.
- [ ] **Step 3: Implement** the four sections in spec order. Keep the existing state machine (`_choose`, `_vote_result`, `_settle`, `SyncIndicator`) untouched; only `_build`, `_render`, `_show_facts`, `_hint_text` and the vote control change. Remove `difficulty_option` usage here (Publish still uses it until Task 8).
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Render** sparse and rich sheets; view; delete the script.
- [ ] **Step 6: Commit** `feat(community): redesign the level details sheet`.

### Task 8: My levels and Publish

**Files:**
- Modify: `scenes/my_levels_screen.gd`
- Test: `tests/test_community_screens.gd`, `tests/test_my_levels.gd`

**Interfaces:**
- Consumes: `Community.statuses()` (Task 5), `MyLevels`, `LevelFormat.validate` (Task 4 messages).

- [ ] **Step 1: Update and add tests**: `status line per spec table` for each of the seven states, including `edited since` (local hash ≠ approved `sha256`); `desktop shows only the first three statuses and no Publish`; `offline Published line drops chip and numbers`; `tapping a row opens its sheet: Edit, Play, Watch (with demo), Publish, Export, Delete last`; `Delete still confirms`; `Publish sheet shows steps 1–3, names the level, Submit disabled until a difficulty is chosen, nothing uploads before Submit`.
- [ ] **Step 2: Run** `TEST_FILTER=test_my_levels GODOT=godot tests/run.sh` and the community screens file. Expected: FAIL.
- [ ] **Step 3: Implement** per spec "My levels" using the `main.gd` row pattern; one Publish sheet replacing `_publish` + `_confirm_publish`, reusing `_validate_publish`, `_submit` and the proof flight calls.
- [ ] **Step 4: Run** the full suite. Expected: PASS.
- [ ] **Step 5: Render** My levels and Publish; view; delete the script.
- [ ] **Step 6: Commit** `feat(my-levels): status rows, level sheet and publish steps`.

### Task 9: Copy, privacy and docs

**Files:**
- Modify: `scenes/community_screen.gd` (`DELETE_WARNING` text and its test constant in `tests/test_community_screens.gd`), `PRIVACY.md`, `README.md`, `docs/superpowers/specs/2026-10-22-community-feedback-design.md` (one "Superseded in part by 2026-11-13-community-redesign-design.md" line under its title)

- [ ] **Step 1:** Deletion sentence: "This removes your scores, likes, reports, play history, difficulty ratings and your name from Zero-GX's servers. Levels you shared stay, shown as by Deleted player."
- [ ] **Step 2:** `PRIVACY.md`: under the play-history table add "Your play history is also used to estimate each level's difficulty with a model of player skill. The skill estimates are temporary and are neither stored nor shown." In deletion text, state per-level figures are recalculated within 10 minutes.
- [ ] **Step 3:** `README.md`: update the Community and My levels paragraphs to the new screens and Rated difficulty.
- [ ] **Step 4: Run** both full suites. Expected: PASS.
- [ ] **Step 5: Commit** `docs: privacy, README and deletion copy for ratings`, push, open the PR, wait for CI, merge once green.

The braitg.dev copy of the privacy policy must be updated before the Play build ships; that repository is outside this plan.
