import { type Difficulty, isDifficulty, upperMedianDifficulty } from "./core/difficulty";
import type { Env } from "./env";
import { HttpError, readJson } from "./http";
import { VISIBLE, visibleLevel } from "./levels";
import { playEligibility, SHA256, VERSION_ELIGIBLE } from "./plays";
import { requirePlayer } from "./session";

/** Starters a version needs before its ratios and median are shown; below it, only the counts. */
const MIN_STARTERS = 10;

export interface Community {
  value: Difficulty | null;
  votes: number;
}

type Tally = Record<Difficulty, number>;

const sha256Of = (value: unknown): string => {
  if (typeof value !== "string" || !SHA256.test(value)) throw new HttpError(400, "sha256 must be 64 lowercase hex characters.");
  return value;
};

const difficultyOf = (value: unknown): Difficulty => {
  if (!isDifficulty(value)) throw new HttpError(400, "difficulty must be easy, normal, hard or expert.");
  return value;
};

/** The version of `level` with this hash, else 404: another stage's version and unknown hashes both fail. */
async function versionOf(env: Env, level: string, sha256: string): Promise<{ reviewed_difficulty: Difficulty | null }> {
  const version = await env.DB.prepare("SELECT reviewed_difficulty FROM versions WHERE level = ? AND sha256 = ?").bind(level, sha256).first<{ reviewed_difficulty: Difficulty | null }>();
  if (!version) throw new HttpError(404, "Not found.");
  return version;
}

// Writes the vote only while the account is active, the version visible and the player eligible for it; a refused write returns no row.
const VOTE_UPSERT = `INSERT INTO difficulty_votes (player, sha256, difficulty)
  SELECT ?1, ?2, ?3
  WHERE EXISTS (SELECT 1 FROM players WHERE id = ?1 AND banned = 0)
    AND EXISTS (SELECT 1 FROM versions v JOIN levels l ON l.id = v.level WHERE v.sha256 = ?2 AND ${VISIBLE})
    AND ${VERSION_ELIGIBLE}
  ON CONFLICT (player, sha256) DO UPDATE SET difficulty = excluded.difficulty
  RETURNING difficulty`;

/** Each version's community label and voter count. Banned voters are left out at query time; deleted ones have no rows. */
export async function communityLabels(env: Env, sha256s: string[]): Promise<Map<string, Community>> {
  const { results } = await env.DB.prepare(
    `SELECT v.sha256, v.difficulty, COUNT(*) AS votes FROM difficulty_votes v JOIN players p ON p.id = v.player
     WHERE p.banned = 0 AND v.sha256 IN (SELECT value FROM json_each(?)) GROUP BY v.sha256, v.difficulty`,
  )
    .bind(JSON.stringify(sha256s))
    .all<{ sha256: string; difficulty: Difficulty; votes: number }>();
  const tallies = new Map<string, Tally>(sha256s.map((sha256): [string, Tally] => [sha256, { easy: 0, normal: 0, hard: 0, expert: 0 }]));
  for (const row of results) tallies.get(row.sha256)![row.difficulty] = row.votes;
  const labels = new Map<string, Community>();
  for (const [sha256, tally] of tallies) labels.set(sha256, { value: upperMedianDifficulty(tally), votes: Object.values(tally).reduce((sum, n) => sum + n, 0) });
  return labels;
}

// Starters are the non-banned players with counted attempts on the version; finishers are those who cleared it.
const STARTERS = `WITH starters AS (
    SELECT s.attempts, s.first_clear_ms FROM play_summaries s JOIN players p ON p.id = s.player WHERE s.sha256 = ?1 AND p.banned = 0
  ), finishers AS (SELECT attempts FROM starters WHERE first_clear_ms IS NOT NULL)`;

// The median is the ordinary one over finishers: the middle count, or the mean of the two middle counts. Unbeaten N:
// starters who never cleared and made at least N counted attempts.
const STATS = `${STARTERS}
  SELECT (SELECT COUNT(*) FROM starters) AS started,
    (SELECT COUNT(*) FROM finishers) AS cleared,
    (SELECT COALESCE(SUM(attempts), 0) FROM starters) AS total,
    (SELECT AVG(attempts) FROM (SELECT attempts FROM finishers ORDER BY attempts
      LIMIT 2 - (SELECT COUNT(*) FROM finishers) % 2 OFFSET (SELECT (COUNT(*) - 1) / 2 FROM finishers))) AS median,
    (SELECT COUNT(*) FROM starters WHERE first_clear_ms IS NULL AND attempts >= 5) AS unbeaten_5,
    (SELECT COUNT(*) FROM starters WHERE first_clear_ms IS NULL AND attempts >= 10) AS unbeaten_10,
    (SELECT COUNT(*) FROM starters WHERE first_clear_ms IS NULL AND attempts >= 20) AS unbeaten_20`;

interface StatRow {
  started: number;
  cleared: number;
  total: number;
  median: number | null;
  unbeaten_5: number;
  unbeaten_10: number;
  unbeaten_20: number;
}

async function statsOf(env: Env, sha256: string) {
  const row = (await env.DB.prepare(STATS).bind(sha256).first<StatRow>())!;
  const ratios = row.started >= MIN_STARTERS;
  return {
    players_started: row.started,
    players_cleared: row.cleared,
    total_attempts: row.total,
    clear_rate: ratios ? row.cleared / row.started : null,
    attempts_per_first_clear: ratios && row.cleared > 0 ? row.total / row.cleared : null,
    median_tries: ratios ? row.median : null,
    unbeaten_5: row.unbeaten_5,
    unbeaten_10: row.unbeaten_10,
    unbeaten_20: row.unbeaten_20,
  };
}

/** `GET /levels/:level/feedback?sha256=`: the version's labels and statistics, and only the caller's own state. */
export async function getFeedback(request: Request, env: Env, params: Record<string, string>): Promise<Response> {
  const player = await requirePlayer(request, env);
  const sha256 = sha256Of(new URL(request.url).searchParams.get("sha256"));
  const level = await visibleLevel(env, params.level);
  const version = await versionOf(env, level.id, sha256);
  const community = (await communityLabels(env, [sha256])).get(sha256)!;
  const stats = await statsOf(env, sha256);
  const mine = (await env.DB.prepare(
    `SELECT EXISTS (SELECT 1 FROM likes WHERE player = ?1 AND level = ?2) AS liked,
       (SELECT difficulty FROM difficulty_votes WHERE player = ?1 AND sha256 = ?3) AS difficulty`,
  )
    .bind(player.id, level.id, sha256)
    .first<{ liked: number; difficulty: Difficulty | null }>())!;
  const onVersion = await playEligibility(env, player.id, level.id, sha256);
  const onStage = await playEligibility(env, player.id, level.id);
  return Response.json({
    level_id: level.id,
    sha256,
    reviewed_difficulty: version.reviewed_difficulty,
    community_difficulty: community,
    stats,
    you: {
      liked: mine.liked === 1,
      like_eligible: onStage.eligible,
      difficulty: mine.difficulty,
      difficulty_eligible: onVersion.eligible,
      attempts: onVersion.attempts,
      cleared: onVersion.cleared,
    },
  });
}

/** `PUT /levels/:level/difficulty` with `{sha256, difficulty}`: sets the caller's one vote on that version. */
export async function putDifficulty(request: Request, env: Env, params: Record<string, string>): Promise<Response> {
  const player = await requirePlayer(request, env);
  const body = await readJson(request);
  const sha256 = sha256Of(body.sha256);
  const difficulty = difficultyOf(body.difficulty);
  const level = await visibleLevel(env, params.level);
  await versionOf(env, level.id, sha256);
  if (!(await playEligibility(env, player.id, level.id, sha256)).eligible) throw new HttpError(403, "Clear this version or make 5 attempts to rate its difficulty.");
  // The guarded write decides: an account erased or a level hidden since the checks above writes nothing.
  const [written] = await env.DB.batch<{ difficulty: Difficulty }>([env.DB.prepare(VOTE_UPSERT).bind(player.id, sha256, difficulty)]);
  await requirePlayer(request, env);
  if (written!.results.length === 0) throw new HttpError(404, "Not found.");
  return Response.json({ difficulty });
}

/** `DELETE /levels/:level/difficulty?sha256=`: removes the caller's vote. No play is needed, and removing none is fine. */
export async function deleteDifficulty(request: Request, env: Env, params: Record<string, string>): Promise<Response> {
  const player = await requirePlayer(request, env);
  const sha256 = sha256Of(new URL(request.url).searchParams.get("sha256"));
  const level = await visibleLevel(env, params.level);
  await versionOf(env, level.id, sha256);
  await env.DB.prepare("DELETE FROM difficulty_votes WHERE player = ? AND sha256 = ?").bind(player.id, sha256).run();
  return Response.json({ difficulty: null });
}
