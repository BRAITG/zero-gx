import type { Env } from "./env";
import { HttpError, parseJsonObject, readBytes } from "./http";
import { VISIBLE } from "./levels";
import { requireIntegrity, requirePlayer } from "./session";

const MAX_BYTES = 16384;
const MAX_RECORDS = 32;
const PLAYS_PER_MINUTE = 30;
/** Counted attempts that unlock a version's vote (or a stage's like) without a clear. */
const ELIGIBLE_ATTEMPTS = 5;
const ATTEMPT_ID = /^[0-9a-f]{32}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const SNAPSHOT_FIELDS = "ended_ms,id,outcome,revision,sha256,started_ms";

type Outcome = "failed" | "abandoned" | "cleared";

/** An attempt snapshot the app sent, validated. Times are the app's hints; the server keeps its own receipt time. */
interface Snapshot {
  id: string;
  sha256: string;
  started_ms: number;
  revision: 1 | 2;
  outcome: Outcome | null;
  ended_ms: number | null;
}

interface Discard {
  id: string;
  revision: number;
  reason: "conflict" | "unknown_version" | "hidden_version";
}

interface Eligibility {
  attempts: number;
  cleared: boolean;
  eligible: boolean;
}

const isTime = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
const isOutcome = (value: unknown): value is Outcome => value === "failed" || value === "abandoned" || value === "cleared";

/** One snapshot's fields and the rules of its revision: a start has no result, a finish has one. 400 otherwise. */
function parseSnapshot(value: unknown): Snapshot {
  const invalid = new HttpError(400, "Each attempt needs exactly id, sha256, started_ms, revision, outcome and ended_ms, with values the protocol allows.");
  if (value === null || typeof value !== "object" || Object.keys(value).sort().join() !== SNAPSHOT_FIELDS) throw invalid;
  const { id, sha256, started_ms, revision, outcome, ended_ms } = value as Record<string, unknown>;
  if (typeof id !== "string" || !ATTEMPT_ID.test(id)) throw invalid;
  if (typeof sha256 !== "string" || !SHA256.test(sha256)) throw invalid;
  if (!isTime(started_ms)) throw invalid;
  if (revision === 1) {
    if (outcome !== null || ended_ms !== null) throw invalid;
    return { id, sha256, started_ms, revision: 1, outcome: null, ended_ms: null };
  }
  if (revision !== 2 || !isOutcome(outcome) || !isTime(ended_ms) || ended_ms < started_ms) throw invalid;
  return { id, sha256, started_ms, revision: 2, outcome, ended_ms };
}

/** Structure first: any defect refuses the whole report before anything is written. */
function parseReport(bytes: Uint8Array): { player_id: string; records: Snapshot[] } {
  const { player_id, attempts } = parseJsonObject(bytes);
  if (typeof player_id !== "string") throw new HttpError(400, "player_id must be a string.");
  if (!Array.isArray(attempts) || attempts.length < 1 || attempts.length > MAX_RECORDS) throw new HttpError(400, `attempts must hold 1 to ${MAX_RECORDS} records.`);
  const records = attempts.map(parseSnapshot);
  if (new Set(records.map((record) => record.id)).size !== records.length) throw new HttpError(400, "An attempt id may appear only once in a report.");
  return { player_id, records };
}

/** Counts this report against the player's minute; 429 beyond PLAYS_PER_MINUTE. */
async function limitPlays(env: Env, player: string): Promise<void> {
  const window = Math.floor(Date.now() / 1000 / 60);
  const row = await env.DB.prepare(
    `INSERT INTO rate (player, action, "window", count) VALUES (?, 'plays', ?, 1)
     ON CONFLICT (player, action, "window") DO UPDATE SET count = count + 1 RETURNING count`,
  )
    .bind(player, window)
    .first<{ count: number }>();
  if (row!.count > PLAYS_PER_MINUTE) throw new HttpError(429, "Too many play reports; try again in a minute.");
}

// Writes a record only while it agrees with the stored one: the owner is active, the version visible, the immutable
// fields equal, and a stored finish unchanged. A stale start leaves the stored revision alone. No row back = refused.
const UPSERT = `INSERT INTO play_attempts (player, id, sha256, started_ms, revision, outcome, ended_ms, received_ms)
  SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8
  WHERE EXISTS (SELECT 1 FROM players WHERE id = ?1 AND banned = 0)
    AND EXISTS (SELECT 1 FROM versions v JOIN levels l ON l.id = v.level WHERE v.sha256 = ?3 AND ${VISIBLE})
  ON CONFLICT (player, id) DO UPDATE SET revision = MAX(play_attempts.revision, excluded.revision),
    outcome = COALESCE(play_attempts.outcome, excluded.outcome), ended_ms = COALESCE(play_attempts.ended_ms, excluded.ended_ms)
  WHERE play_attempts.sha256 = excluded.sha256 AND play_attempts.started_ms = excluded.started_ms
    AND (excluded.revision = 1 OR play_attempts.revision = 1 OR (play_attempts.outcome = excluded.outcome AND play_attempts.ended_ms = excluded.ended_ms))
  RETURNING id`;

// Recomputed from the raw attempts, never incremented: counting starts at the earliest clear's end (ties by id), and
// without a clear every attempt counts.
const SUMMARY = `WITH earliest AS (SELECT ended_ms FROM play_attempts WHERE player = ?1 AND sha256 = ?2 AND outcome = 'cleared' ORDER BY ended_ms, id LIMIT 1)
  INSERT INTO play_summaries (player, sha256, attempts, first_clear_ms)
  SELECT ?1, ?2,
    (SELECT COUNT(*) FROM play_attempts WHERE player = ?1 AND sha256 = ?2
      AND ((SELECT ended_ms FROM earliest) IS NULL OR started_ms <= (SELECT ended_ms FROM earliest))),
    (SELECT ended_ms FROM earliest)
  WHERE EXISTS (SELECT 1 FROM players WHERE id = ?1 AND banned = 0)
    AND EXISTS (SELECT 1 FROM play_attempts WHERE player = ?1 AND sha256 = ?2)
  ON CONFLICT (player, sha256) DO UPDATE SET attempts = excluded.attempts, first_clear_ms = excluded.first_clear_ms`;

/** Visibility of the published versions among `sha256s`: true when visible, false when hidden; unknown hashes are absent. */
async function visibilityOf(env: Env, sha256s: string[]): Promise<Map<string, boolean>> {
  const lookup = await env.DB.prepare(
    `SELECT v.sha256, (${VISIBLE}) AS visible FROM versions v JOIN levels l ON l.id = v.level WHERE v.sha256 IN (SELECT value FROM json_each(?))`,
  )
    .bind(JSON.stringify(sha256s))
    .all<{ sha256: string; visible: number }>();
  return new Map(lookup.results.map((row): [string, boolean] => [row.sha256, row.visible === 1]));
}

/**
 * `POST /plays`: records the caller's attempts and acknowledges each one. Ownership and structure are checked before
 * any write; the guarded writes and the summaries they touch commit in one batch.
 */
export async function postPlays(request: Request, env: Env, _params: Record<string, string>): Promise<Response> {
  const player = await requirePlayer(request, env);
  await limitPlays(env, player.id);
  const bytes = await readBytes(request, MAX_BYTES);
  await requireIntegrity(request, env, [bytes], "device");
  const { player_id, records } = parseReport(bytes);
  if (player_id !== player.id) throw new HttpError(403, "A report can only name the signed-in player.");

  const visibility = await visibilityOf(env, [...new Set(records.map((record) => record.sha256))]);

  const discarded: Discard[] = [];
  const writable: Snapshot[] = [];
  for (const record of records) {
    const visible = visibility.get(record.sha256);
    if (visible) writable.push(record);
    else discarded.push({ id: record.id, revision: record.revision, reason: visible === undefined ? "unknown_version" : "hidden_version" });
  }

  const acknowledged: { id: string; revision: number }[] = [];
  const cleared = new Set<string>();
  if (writable.length > 0) {
    const received = Date.now();
    const touched = [...new Set(writable.map((record) => record.sha256))];
    const results = await env.DB.batch<{ id: string }>([
      ...writable.map((record) =>
        env.DB.prepare(UPSERT).bind(player.id, record.id, record.sha256, record.started_ms, record.revision, record.outcome, record.ended_ms, received),
      ),
      ...touched.map((sha256) => env.DB.prepare(SUMMARY).bind(player.id, sha256)),
    ]);
    // Every write is refused once the account is gone; answer as a signed-out request would.
    await requirePlayer(request, env);
    const refused: Snapshot[] = [];
    writable.forEach((record, i) => {
      if (results[i]!.results.length === 0) {
        refused.push(record);
      } else {
        acknowledged.push({ id: record.id, revision: record.revision });
        if (record.outcome === "cleared") cleared.add(record.sha256);
      }
    });
    // Refused by a guard: hidden since the lookup, or conflicting with the stored record. The re-read tells which.
    const reread = refused.length > 0 ? await visibilityOf(env, refused.map((record) => record.sha256)) : new Map<string, boolean>();
    for (const record of refused) {
      const visible = reread.get(record.sha256);
      discarded.push({ id: record.id, revision: record.revision, reason: visible === undefined ? "unknown_version" : visible ? "conflict" : "hidden_version" });
    }
  }
  return Response.json({ acknowledged, discarded, cleared: [...cleared] });
}

/**
 * What the player's history unlocks on a level, or on one version of it when `sha256` is given: a clear, or
 * ELIGIBLE_ATTEMPTS counted attempts. A verified score counts as a clear (its demo reached the goal), so scores from
 * before play history keep their eligibility without any attempt rows.
 */
export async function playEligibility(env: Env, player: string, level: string, sha256?: string): Promise<Eligibility> {
  const row = await env.DB.prepare(
    `SELECT COALESCE(SUM(s.attempts), 0) AS attempts, MAX(s.first_clear_ms IS NOT NULL) AS cleared,
       EXISTS (SELECT 1 FROM scores c JOIN versions w ON w.sha256 = c.sha256
         WHERE w.level = ?2 AND c.player = ?1 AND (?3 IS NULL OR c.sha256 = ?3)) AS scored
     FROM versions v LEFT JOIN play_summaries s ON s.sha256 = v.sha256 AND s.player = ?1
     WHERE v.level = ?2 AND (?3 IS NULL OR v.sha256 = ?3)`,
  )
    .bind(player, level, sha256 ?? null)
    .first<{ attempts: number; cleared: number | null; scored: number }>();
  const attempts = row!.attempts;
  const cleared = row!.cleared === 1 || row!.scored === 1;
  return { attempts, cleared, eligible: cleared || attempts >= ELIGIBLE_ATTEMPTS };
}
