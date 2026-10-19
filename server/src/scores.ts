import { MAX_BYTES, decodeDemo } from "./core/demo";
import { checkDemo, scoreDemo } from "./core/check";
import { sha256Hex } from "./core/level";
import type { Env } from "./env";
import { HttpError, readBytes, readJson } from "./http";
import { requireIntegrity, requirePlayer } from "./session";
import { base64url, randomId } from "./util";

const SCORES_PER_MINUTE = 30;
const BOARD_SIZE = 100;
const SHA256 = /^[0-9a-f]{64}$/;
const DEMO_KEY = /^demos\/[0-9a-f]{64}\/p_[a-z0-9]{16}\/[A-Za-z0-9_-]{8,64}\.demo\.gz$/;

const notFound = () => new HttpError(404, "Not found.");

interface LevelRef {
  kind: "official" | "community";
  name: string;
  /** Where the level file lives; its sha256 is checked after the fetch. */
  url: string;
}

/** The official or visible community level with this hash, or null. */
async function findLevel(env: Env, sha256: string): Promise<LevelRef | null> {
  const official = await env.DB.prepare("SELECT name, release FROM official_levels WHERE sha256 = ?").bind(sha256).first<{ name: string; release: string }>();
  if (official) {
    return { kind: "official", name: official.name, url: `https://raw.githubusercontent.com/BRAITG/zero-gx/${official.release}/levels/${official.name}.json` };
  }
  const community = await env.DB.prepare(
    `SELECT v.level, v.version FROM versions v JOIN levels l ON l.id = v.level
     WHERE v.sha256 = ? AND l.hidden = 0 AND v.level NOT IN (SELECT level FROM hidden_levels)`,
  )
    .bind(sha256)
    .first<{ level: string; version: number }>();
  if (!community) return null;
  const name = `${community.level}/v${community.version}`;
  return { kind: "community", name, url: `https://raw.githubusercontent.com/${env.LEVELS_REPO}/main/levels/${community.level}/v${community.version}.json` };
}

/** The level file's bytes: from the R2 cache, else fetched, hash-checked and cached. */
async function levelBytes(env: Env, sha256: string, url: string, fetchFn: typeof fetch): Promise<Uint8Array> {
  const key = `levels/${sha256}.json`;
  const cached = await env.DEMOS.get(key);
  if (cached) return new Uint8Array(await cached.arrayBuffer());
  const response = await fetchFn(url).catch(() => null);
  if (!response?.ok) throw new HttpError(502, "The level file could not be fetched.");
  const bytes = new Uint8Array(await response.arrayBuffer());
  if ((await sha256Hex(bytes)) !== sha256) throw new HttpError(502, "The level file did not match its hash.");
  await env.DEMOS.put(key, bytes);
  return bytes;
}

/** Counts this post against the player's minute; 429 beyond SCORES_PER_MINUTE. */
async function limitRate(env: Env, player: string): Promise<void> {
  const window = Math.floor(Date.now() / 1000 / 60);
  const row = await env.DB.prepare(
    `INSERT INTO rate (player, action, "window", count) VALUES (?, 'score', ?, 1)
     ON CONFLICT (player, action, "window") DO UPDATE SET count = count + 1 RETURNING count`,
  )
    .bind(player, window)
    .first<{ count: number }>();
  if (row!.count > SCORES_PER_MINUTE) throw new HttpError(429, "Too many scores; try again in a minute.");
}

/** `fetchFn` is the injection point for tests. */
export async function postScore(request: Request, env: Env, _params: Record<string, string>, fetchFn: typeof fetch = fetch): Promise<Response> {
  const player = await requirePlayer(request, env);
  await limitRate(env, player.id);
  const body = await readBytes(request, MAX_BYTES);
  // Only a demo signed by a genuine app on a hardware-attested device can rank.
  await requireIntegrity(request, env, [body], "strong");
  const demo = await decodeDemo(body);
  if (!demo) throw new HttpError(400, "The demo could not be read.");
  const level = await findLevel(env, demo.levelSha256);
  if (!level) throw notFound();
  const levelJson = JSON.parse(new TextDecoder().decode(await levelBytes(env, demo.levelSha256, level.url, fetchFn)));
  const errors = checkDemo(levelJson, demo.levelSha256, demo);
  if (errors.length > 0) throw new HttpError(400, errors[0]!);
  const score = scoreDemo(levelJson, demo);

  // Upload first so a stored row never points at a missing demo.
  const key = `demos/${demo.levelSha256}/${player.id}/${randomId("", 24)}.demo.gz`;
  await env.DEMOS.put(key, body);
  const before = await env.DB.prepare("SELECT demo FROM scores WHERE sha256 = ? AND player = ?").bind(demo.levelSha256, player.id).first<{ demo: string }>();
  const written = await env.DB.prepare(
    `INSERT INTO scores (sha256, player, points, fuel, hull, seconds, demo, posted) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (sha256, player) DO UPDATE SET points = excluded.points, fuel = excluded.fuel, hull = excluded.hull,
       seconds = excluded.seconds, demo = excluded.demo, posted = excluded.posted
     WHERE excluded.points > scores.points RETURNING demo`,
  )
    .bind(demo.levelSha256, player.id, score.points, score.fuel, score.hull, score.seconds, key, Math.floor(Date.now() / 1000))
    .first<{ demo: string }>();
  // Delete by value: a row never returns to an old key, so it cannot point at a deleted demo.
  // Orphans from racing or failed posts are possible and left to a sweep.
  const beaten = written ? before?.demo : key;
  if (beaten) await env.DEMOS.delete(beaten);

  // Rank of the stored score, whether or not this post beat it.
  const rank = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM scores WHERE sha256 = ?1 AND player NOT IN (SELECT id FROM players WHERE banned = 1)
     AND points > (SELECT points FROM scores WHERE sha256 = ?1 AND player = ?2)`,
  )
    .bind(demo.levelSha256, player.id)
    .first<{ n: number }>();
  return Response.json({ points: score.points, rank: 1 + rank!.n, best: written !== null });
}

// Banned players are neither listed nor counted in a rank.
const BOARD_ROW = `SELECT (SELECT COUNT(*) FROM scores o
    WHERE o.sha256 = s.sha256 AND o.player NOT IN (SELECT id FROM players WHERE banned = 1) AND o.points > s.points) + 1 AS rank,
  s.player AS id, p.name, s.points, s.fuel, s.hull, s.seconds, s.demo
  FROM scores s JOIN players p ON p.id = s.player WHERE s.sha256 = ? AND p.banned = 0`;

interface BoardRow {
  rank: number;
  id: string;
  name: string;
  points: number;
  fuel: number;
  hull: number;
  seconds: number;
  demo: string;
}

const boardEntry = ({ id, name, ...rest }: BoardRow) => ({ rank: rest.rank, player: { id, name }, points: rest.points, fuel: rest.fuel, hull: rest.hull, seconds: rest.seconds, demo: rest.demo });

export async function getBoard(request: Request, env: Env, params: Record<string, string>): Promise<Response> {
  const player = await requirePlayer(request, env);
  const sha256 = params.sha256!;
  const level = SHA256.test(sha256) ? await findLevel(env, sha256) : null;
  if (!level) throw notFound();
  const [top, mine] = await env.DB.batch<BoardRow>([
    env.DB.prepare(`${BOARD_ROW} ORDER BY s.points DESC, s.posted ASC, s.player ASC LIMIT ${BOARD_SIZE}`).bind(sha256),
    env.DB.prepare(`${BOARD_ROW} AND s.player = ?`).bind(sha256, player.id),
  ]);
  return Response.json({ level: { kind: level.kind, name: level.name }, rows: top!.results.map(boardEntry), you: mine!.results[0] ? boardEntry(mine!.results[0]) : null });
}

export async function getDemo(request: Request, env: Env, params: Record<string, string>): Promise<Response> {
  await requirePlayer(request, env);
  const key = `demos/${params.sha256}/${params.player}/${params.file}`;
  const object = DEMO_KEY.test(key) ? await env.DEMOS.get(key) : null;
  if (!object) throw notFound();
  return new Response(object.body, { headers: { "Content-Type": "application/octet-stream" } });
}

/** HMACs both sides under a throwaway key: the comparison then runs on digests the caller cannot predict, so its timing reveals nothing. */
async function tokenMatches(given: string, expected: string): Promise<boolean> {
  const key = await crypto.subtle.importKey("raw", crypto.getRandomValues(new Uint8Array(32)), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = (text: string) => crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text));
  return base64url(new Uint8Array(await mac(given))) === base64url(new Uint8Array(await mac(expected)));
}

export async function postOfficial(request: Request, env: Env): Promise<Response> {
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  if (!env.ADMIN_TOKEN || !token || !(await tokenMatches(token, env.ADMIN_TOKEN))) throw new HttpError(401, "The admin token was not accepted.");
  const { release, levels } = await readJson(request, 65536);
  if (typeof release !== "string" || !/^[A-Za-z0-9._-]{1,64}$/.test(release)) throw new HttpError(400, "release must be 1 to 64 characters of letters, digits, dot, dash and underscore.");
  if (!Array.isArray(levels) || levels.length < 1 || levels.length > 200) throw new HttpError(400, "levels must hold 1 to 200 entries.");
  const upsert = env.DB.prepare(
    "INSERT INTO official_levels (sha256, name, release) VALUES (?, ?, ?) ON CONFLICT (sha256) DO UPDATE SET name = excluded.name, release = excluded.release",
  );
  const statements = levels.map((entry) => {
    const { name, sha256 } = (entry ?? {}) as Record<string, unknown>;
    if (typeof name !== "string" || !/^level_[0-9]{2}$/.test(name) || typeof sha256 !== "string" || !SHA256.test(sha256)) {
      throw new HttpError(400, "Each level needs a name like level_01 and a lowercase 64-digit hex sha256.");
    }
    return upsert.bind(sha256, name, release);
  });
  await env.DB.batch(statements);
  return Response.json({ registered: statements.length });
}
