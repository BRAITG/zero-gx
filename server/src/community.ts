import type { Env } from "./env";
import { getHeadCommit, openIssue } from "./github";
import { HttpError, readJson } from "./http";
import { DELETED_AUTHOR, requirePlayer } from "./session";
import { rebuildIndex } from "./submissions";

const PAGE_SIZE = 50;
const RANKING_SIZE = 100;
const REPORTS_PER_DAY = 10;
const MAX_REASON = 500;
const INDEX_CACHE_MS = 60_000;
const LEVEL_ID = /^lvl_[a-z0-9]{10}$/;
/** Demos younger than this may belong to a post that has not stored its score row yet. */
const ORPHAN_AGE_MS = 60 * 60 * 1000;
const SWEEP_PAGE = 1000;
/** Each level keeps the demos of its top KEEP_DEMOS runs (ties at the cut included); every other demo is deleted DEMO_DAYS after its post. */
const KEEP_DEMOS = 10;
const DEMO_DAYS = 14;
const EXPIRE_BATCH = 500;
// Each run reads at most this many pages and saves where it stopped.
const SWEEP_PAGES = 5;
/** Rate windows are kept this many windows past the current one. */
const RATE_KEEP = 2;

const now = () => Math.floor(Date.now() / 1000);
const VISIBLE = "l.hidden = 0 AND l.id NOT IN (SELECT level FROM hidden_levels)";

interface LevelRow {
  id: string;
  latest: number;
}

/** A level that exists and is not hidden, else 404. */
async function visibleLevel(env: Env, id: string | undefined): Promise<LevelRow> {
  const level = LEVEL_ID.test(id ?? "") ? await env.DB.prepare(`SELECT l.id, l.latest FROM levels l WHERE l.id = ? AND ${VISIBLE}`).bind(id).first<LevelRow>() : null;
  if (!level) throw new HttpError(404, "Not found.");
  return level;
}

/** `POST` likes the level (only after a score on any of its versions), `DELETE` removes the like; both are idempotent and answer the new count. */
export async function putLike(request: Request, env: Env, params: Record<string, string>): Promise<Response> {
  const player = await requirePlayer(request, env);
  const level = await visibleLevel(env, params.level);
  const liking = request.method === "POST";
  if (liking) {
    const played = await env.DB.prepare("SELECT 1 AS yes FROM scores s JOIN versions v ON v.sha256 = s.sha256 WHERE v.level = ? AND s.player = ?").bind(level.id, player.id).first();
    if (!played) throw new HttpError(403, "Play the level before liking it.");
  }
  const change = liking ? "INSERT OR IGNORE INTO likes (player, level) VALUES (?, ?)" : "DELETE FROM likes WHERE player = ? AND level = ?";
  const [, count] = await env.DB.batch<{ likes: number }>([env.DB.prepare(change).bind(player.id, level.id), env.DB.prepare("SELECT COUNT(*) AS likes FROM likes WHERE level = ?").bind(level.id)]);
  return Response.json({ likes: count!.results[0]!.likes });
}

export async function getLevels(request: Request, env: Env): Promise<Response> {
  await requirePlayer(request, env);
  const query = new URL(request.url).searchParams;
  const sort = query.get("sort") ?? "top";
  const page = query.get("page") ?? "0";
  if (sort !== "top" && sort !== "new") throw new HttpError(400, "sort must be top or new.");
  if (!/^\d{1,6}$/.test(page)) throw new HttpError(400, "page must be a non-negative integer.");
  const order = sort === "top" ? "likes DESC, players DESC, l.id" : "v.approved DESC, l.id";
  const { results } = await env.DB.prepare(
    `SELECT l.id AS level_id, l.title, COALESCE(p.name, '${DELETED_AUTHOR}') AS author, l.latest, v.sha256,
       (SELECT COUNT(*) FROM likes k WHERE k.level = l.id) AS likes,
       (SELECT COUNT(DISTINCT s.player) FROM scores s JOIN versions w ON w.sha256 = s.sha256 WHERE w.level = l.id) AS players
     FROM levels l LEFT JOIN players p ON p.id = l.owner JOIN versions v ON v.level = l.id AND v.version = l.latest
     WHERE ${VISIBLE} ORDER BY ${order} LIMIT ${PAGE_SIZE} OFFSET ?`,
  )
    .bind(Number(page) * PAGE_SIZE)
    .all();
  return Response.json(results);
}

const RANK_ROW = `SELECT r.rank, r.player AS id, p.name, r.points FROM player_ranking r JOIN players p ON p.id = r.player WHERE p.banned = 0`;

interface RankRow {
  rank: number;
  id: string;
  name: string;
  points: number;
}

const rankEntry = ({ rank, id, name, points }: RankRow) => ({ rank, player: { id, name }, points });

export async function getPlayers(request: Request, env: Env): Promise<Response> {
  const player = await requirePlayer(request, env);
  const [top, mine] = await env.DB.batch<RankRow>([
    env.DB.prepare(`${RANK_ROW} ORDER BY r.rank, r.player LIMIT ${RANKING_SIZE}`),
    env.DB.prepare(`${RANK_ROW} AND r.player = ?`).bind(player.id),
  ]);
  return Response.json({ rows: top!.results.map(rankEntry), you: mine!.results[0] ? rankEntry(mine!.results[0]) : null });
}

/** Counts this report against the player's day; 429 beyond REPORTS_PER_DAY. */
async function limitReports(env: Env, player: string): Promise<void> {
  const row = await env.DB.prepare(
    `INSERT INTO rate (player, action, "window", count) VALUES (?, 'report', ?, 1)
     ON CONFLICT (player, action, "window") DO UPDATE SET count = count + 1 RETURNING count`,
  )
    .bind(player, Math.floor(now() / 86400))
    .first<{ count: number }>();
  if (row!.count > REPORTS_PER_DAY) throw new HttpError(429, "Too many reports today; try again tomorrow.");
}

/** Quotes the reason line by line (a lone CR also ends a line in Markdown); the zero-width space stops `@name` from notifying anyone. */
const quote = (reason: string) => reason.replace(/@/g, "@\u200b").split(/\r\n|\r|\n/).map((line) => `> ${line}`).join("\n");

/** `fetchFn` is the injection point for tests. */
export async function postReport(request: Request, env: Env, params: Record<string, string>, fetchFn: typeof fetch = fetch): Promise<Response> {
  const player = await requirePlayer(request, env);
  const level = await visibleLevel(env, params.level);
  const { reason } = await readJson(request);
  if (typeof reason !== "string" || reason.trim() === "" || reason.length > MAX_REASON) throw new HttpError(400, `reason must be 1 to ${MAX_REASON} characters.`);
  await limitReports(env, player.id);
  const stored = await env.DB.prepare("INSERT OR IGNORE INTO reports (player, level) VALUES (?, ?)").bind(player.id, level.id).run();
  if (stored.meta.changes === 0) throw new HttpError(409, "You have already reported this level.");
  try {
    await openIssue(env, fetchFn, { title: `Report: ${level.id}`, body: `${quote(reason)}\n\nLevel: ${level.id}, latest version ${level.latest}\nReporter: ${player.id}`, label: "report" });
  } catch (error) {
    // Not reported after all: let the player try again.
    await env.DB.prepare("DELETE FROM reports WHERE player = ? AND level = ?").bind(player.id, level.id).run();
    console.error(error);
    throw new HttpError(502, "The report could not be filed; try again later.");
  }
  return Response.json({ ok: true }, { status: 201 });
}

let headCache: { commit: string; expires: number } | undefined;

/** `fetchFn` is the injection point for tests. */
export async function getIndex(request: Request, env: Env, _params: Record<string, string>, fetchFn: typeof fetch = fetch): Promise<Response> {
  await requirePlayer(request, env);
  if (!headCache || headCache.expires <= Date.now()) {
    const commit = await getHeadCommit(env, fetchFn).catch((error) => {
      console.error(error);
      throw new HttpError(502, "The index commit could not be fetched.");
    });
    headCache = { commit, expires: Date.now() + INDEX_CACHE_MS };
  }
  return Response.json({ commit: headCache.commit });
}

/** Replaces `player_ranking`: per player the sum of their points on the latest version of every visible community level; ties share a rank. */
async function recomputeRanking(env: Env): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM player_ranking"),
    env.DB.prepare(
      `INSERT INTO player_ranking (player, points, rank, computed)
       SELECT player, points, RANK() OVER (ORDER BY points DESC), ?1 FROM (
         SELECT s.player, SUM(s.points) AS points FROM scores s
         JOIN versions v ON v.sha256 = s.sha256 JOIN levels l ON l.id = v.level AND l.latest = v.version
         JOIN players p ON p.id = s.player
         WHERE ${VISIBLE} AND p.banned = 0 GROUP BY s.player)`,
    ).bind(now()),
  ]);
}

/** Deletes R2 demos that no score row points to, skipping recent ones. Resumes after the key the previous run stopped at and wraps to the start once the listing ends. */
export async function sweepDemos(env: Env, pageSize = SWEEP_PAGE): Promise<void> {
  const saved = await env.DB.prepare("SELECT last_key FROM sweep WHERE id = 1").first<{ last_key: string }>();
  let startAfter = saved?.last_key;
  for (let page = 0; page < SWEEP_PAGES; page++) {
    const listing = await env.DEMOS.list({ prefix: "demos/", limit: pageSize, startAfter });
    const old = listing.objects.filter((object) => object.uploaded.getTime() < Date.now() - ORPHAN_AGE_MS).map((object) => object.key);
    if (old.length > 0) {
      const { results } = await env.DB.prepare("SELECT demo FROM scores WHERE demo IN (SELECT value FROM json_each(?))").bind(JSON.stringify(old)).all<{ demo: string }>();
      const used = new Set(results.map((row) => row.demo));
      const orphans = old.filter((key) => !used.has(key));
      if (orphans.length > 0) await env.DEMOS.delete(orphans);
    }
    startAfter = listing.objects.at(-1)?.key;
    if (!listing.truncated || !startAfter) {
      await env.DB.prepare("DELETE FROM sweep").run();
      return;
    }
  }
  await env.DB.prepare("INSERT INTO sweep (id, last_key) VALUES (1, ?1) ON CONFLICT (id) DO UPDATE SET last_key = ?1").bind(startAfter).run();
}

/**
 * Deletes the demos of runs outside their level's top KEEP_DEMOS that were posted more than DEMO_DAYS ago, and of
 * banned players' runs of that age. The score stays; its `demo` becomes '' (the column is NOT NULL), shown as no demo.
 * Rank is the board's: 1 + the number of visible runs with more points, so ties at the cut keep their demos.
 */
export async function expireDemos(env: Env): Promise<number> {
  const { results } = await env.DB.prepare(
    `SELECT s.sha256, s.player, s.demo FROM scores s JOIN players p ON p.id = s.player
     WHERE s.demo != '' AND s.posted < ?1 AND (p.banned = 1 OR (SELECT COUNT(*) FROM scores o
       WHERE o.sha256 = s.sha256 AND o.points > s.points AND o.player NOT IN (SELECT id FROM players WHERE banned = 1)) >= ?2)
     LIMIT ?3`,
  )
    .bind(now() - DEMO_DAYS * 86400, KEEP_DEMOS, EXPIRE_BATCH)
    .all<{ sha256: string; player: string; demo: string }>();
  if (results.length === 0) return 0;
  // Guarded by the old key: a run improved since the SELECT keeps its new demo.
  const updates = await env.DB.batch(results.map((row) => env.DB.prepare("UPDATE scores SET demo = '' WHERE sha256 = ? AND player = ? AND demo = ?").bind(row.sha256, row.player, row.demo)));
  const expired = results.filter((_, i) => updates[i]!.meta.changes === 1).map((row) => row.demo);
  if (expired.length > 0) await env.DEMOS.delete(expired);
  return expired.length;
}

/** One cron step: a failure is logged and the other steps still run. */
async function step(name: string, run: () => Promise<unknown>): Promise<void> {
  try {
    await run();
  } catch (error) {
    console.error(`cron: ${name} failed`, error);
  }
}

/** The 10-minute cron. `fetchFn` is the injection point for tests. */
export async function runCron(env: Env, fetchFn: typeof fetch = fetch): Promise<void> {
  const time = now();
  await step("ranking", () => recomputeRanking(env));
  await step("cleanup", () =>
    env.DB.batch([
      // Per-minute counters ('score') and per-day ones ('submit', 'report'); the action name says which unit the window is in.
      env.DB.prepare(`DELETE FROM rate WHERE (action = 'score' AND "window" < ?1) OR (action IN ('submit', 'report') AND "window" < ?2)`).bind(Math.floor(time / 60) - RATE_KEEP, Math.floor(time / 86400) - RATE_KEEP),
      env.DB.prepare("DELETE FROM nonces WHERE expires < ?").bind(time),
    ]),
  );
  await step("demo expiry", () => expireDemos(env));
  await step("demo sweep", () => sweepDemos(env));
  await step("index rebuild", () => rebuildIndex(env, fetchFn));
}
