import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { expireDemos, getIndex, postReport, runCron, sweepDemos } from "../../src/community";
import type { Env } from "../../src/env";
import { signSession } from "../../src/session";
import worker from "../../src/worker";

const pem = (label: string, der: ArrayBuffer) => `-----BEGIN ${label}-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END ${label}-----`;
const keyPair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const APP_KEY = pem("PRIVATE KEY", await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));
const testEnv: Env = { ...env, ALLOW_TEST_VERIFIER: "1", GITHUB_APP_ID: "12345", GITHUB_INSTALLATION_ID: "678", GITHUB_APP_KEY: APP_KEY, GITHUB_WEBHOOK_SECRET: "s" };
const REPO = "/repos/BRAITG/zero-gx-levels";

const hash = (s: string) => s.padEnd(64, "0");
const rows = async <T>(sql: string, ...values: unknown[]) => (await env.DB.prepare(sql).bind(...values).all<T>()).results;
const tokenOf = (id: string) => signSession(testEnv, id);

async function call(player: string | null, method: string, path: string, body?: unknown) {
  const headers: Record<string, string> = player ? { Authorization: `Bearer ${await tokenOf(player)}` } : {};
  return worker.fetch(new Request(`https://example.com${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }), testEnv);
}

async function seedPlayer(id: string, name = id, banned = 0) {
  await env.DB.prepare("INSERT INTO players (id, name, banned, created) VALUES (?, ?, ?, 1)").bind(id, name, banned).run();
}

/** A level whose version v was approved at `approved[v - 1]`; the last one is the latest. */
async function seedLevel(id: string, owner: string, approved: number[], extra: { title?: string; hidden?: number } = {}) {
  await env.DB.prepare("INSERT INTO levels (id, owner, latest, hidden, title, created) VALUES (?, ?, ?, ?, ?, 1)").bind(id, owner, approved.length, extra.hidden ?? 0, extra.title ?? id).run();
  for (const [i, time] of approved.entries()) await env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES (?, ?, ?, ?)").bind(id, i + 1, hash(`${id}-v${i + 1}`), time).run();
}

async function seedScore(level: string, version: number, player: string, points: number, demo = `demos/${level}/${player}/${version}.demo.gz`) {
  await env.DB.prepare("INSERT INTO scores VALUES (?, ?, ?, 1, 1, 1, ?, 1)").bind(hash(`${level}-v${version}`), player, points, demo).run();
}

interface Issue {
  title: string;
  body: string;
  labels?: string[];
}

interface Item {
  level_id: string;
  likes: number;
  players: number;
}

class Github {
  calls: { method: string; path: string }[] = [];
  issues: Issue[] = [];
  /** The status labelled issue creation answers with instead of succeeding (422 for an unknown label); 0 = none. */
  labelError = 0;
  down = false;
  head = "head0";
  fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    const body: Issue = init?.body ? JSON.parse(String(init.body)) : undefined;
    this.calls.push({ method, path: url.pathname });
    if (this.down) return Response.json({}, { status: 500 });
    if (url.pathname.startsWith("/app/")) return Response.json({ token: "inst-token", expires_at: new Date(Date.now() + 3600_000).toISOString() }, { status: 201 });
    if (method === "GET" && url.pathname === `${REPO}/git/ref/heads/main`) return Response.json({ object: { sha: this.head } });
    if (method === "POST" && url.pathname === `${REPO}/issues`) {
      if (this.labelError && body.labels) return Response.json({}, { status: this.labelError });
      this.issues.push(body);
      return Response.json({ number: this.issues.length }, { status: 201 });
    }
    return Response.json({}, { status: 404 });
  }) as typeof fetch;
  /** Calls other than the token exchange. */
  ops = () => this.calls.filter((c) => !c.path.startsWith("/app/")).map((c) => `${c.method} ${c.path.replace(REPO, "")}`);
}

beforeEach(async () => {
  await env.DB.batch(["play_attempts", "play_summaries", "difficulty_votes", "players", "levels", "versions", "scores", "likes", "reports", "rate", "nonces", "hidden_levels", "player_ranking", "sweep"].map((table) => env.DB.prepare(`DELETE FROM ${table}`)));
  const { objects } = await env.DEMOS.list();
  if (objects.length) await env.DEMOS.delete(objects.map((o) => o.key));
});

afterEach(() => vi.restoreAllMocks());

describe("likes", () => {
  beforeEach(async () => {
    await seedPlayer("p_a");
    await seedPlayer("p_b");
    await seedLevel("lvl_aaaaaaaaaa", "p_a", [10, 20]);
  });

  it("refuses a like without a score, then accepts one after a score on any version, idempotently", async () => {
    const refused = await call("p_b", "POST", "/levels/lvl_aaaaaaaaaa/like");
    expect(refused.status).toBe(403);
    expect(await rows("SELECT * FROM likes")).toEqual([]);

    await seedScore("lvl_aaaaaaaaaa", 1, "p_b", 100); // an older version counts
    expect(await (await call("p_b", "POST", "/levels/lvl_aaaaaaaaaa/like")).json()).toEqual({ likes: 1 });
    expect(await (await call("p_b", "POST", "/levels/lvl_aaaaaaaaaa/like")).json()).toEqual({ likes: 1 });
    await seedScore("lvl_aaaaaaaaaa", 2, "p_a", 100);
    expect(await (await call("p_a", "POST", "/levels/lvl_aaaaaaaaaa/like")).json()).toEqual({ likes: 2 });
    expect(await (await call("p_b", "DELETE", "/levels/lvl_aaaaaaaaaa/like")).json()).toEqual({ likes: 1 });
    expect(await (await call("p_b", "DELETE", "/levels/lvl_aaaaaaaaaa/like")).json()).toEqual({ likes: 1 });
  });

  it("answers 404 for hidden and unknown levels, 401 without a session", async () => {
    await seedLevel("lvl_bbbbbbbbbb", "p_a", [10], { hidden: 1 });
    await seedLevel("lvl_cccccccccc", "p_a", [10]);
    await env.DB.prepare("INSERT INTO hidden_levels VALUES ('lvl_cccccccccc')").run();
    await seedScore("lvl_bbbbbbbbbb", 1, "p_b", 100);
    expect((await call("p_b", "POST", "/levels/lvl_bbbbbbbbbb/like")).status).toBe(404);
    expect((await call("p_b", "POST", "/levels/lvl_cccccccccc/like")).status).toBe(404);
    expect((await call("p_b", "POST", "/levels/lvl_zzzzzzzzzz/like")).status).toBe(404);
    expect((await call("p_b", "DELETE", "/levels/not-a-level/like")).status).toBe(404);
    expect((await call(null, "POST", "/levels/lvl_aaaaaaaaaa/like")).status).toBe(401);
  });
});

describe("GET /levels", () => {
  const list = async (query = "") => (await call("p_a", "GET", `/levels${query}`)).json() as Promise<Item[]>;

  beforeEach(async () => {
    for (const id of ["p_a", "p_b", "p_c"]) await seedPlayer(id, `Name ${id}`);
    await seedLevel("lvl_aaaaaaaaaa", "p_a", [300]);
    await seedLevel("lvl_bbbbbbbbbb", "p_b", [100, 200], { title: "Two versions" });
    await seedLevel("lvl_cccccccccc", "p_c", [400]);
    await seedLevel("lvl_dddddddddd", "p_a", [500], { hidden: 1 });
    await env.DB.prepare("INSERT INTO levels (id, owner, latest, created) VALUES ('lvl_eeeeeeeeee', 'p_a', 0, 1)").run(); // nothing approved yet
    await seedScore("lvl_dddddddddd", 1, "p_a", 1);
  });

  it("orders top by likes, then players, then id, and lists the shape of each item", async () => {
    await seedScore("lvl_aaaaaaaaaa", 1, "p_a", 1);
    await seedScore("lvl_bbbbbbbbbb", 1, "p_a", 1); // an older version still counts as a player
    await seedScore("lvl_bbbbbbbbbb", 2, "p_b", 1);
    await seedScore("lvl_cccccccccc", 1, "p_a", 1);
    await env.DB.prepare("INSERT INTO likes VALUES ('p_a', 'lvl_cccccccccc'), ('p_b', 'lvl_cccccccccc'), ('p_a', 'lvl_aaaaaaaaaa'), ('p_a', 'lvl_dddddddddd')").run();
    const items = await list();
    expect(items.map((i) => i.level_id)).toEqual(["lvl_cccccccccc", "lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb"]);
    expect(items[2]).toEqual({ level_id: "lvl_bbbbbbbbbb", title: "Two versions", author: "Name p_b", latest: 2, sha256: hash("lvl_bbbbbbbbbb-v2"), likes: 0, players: 2, reviewed_difficulty: null, sketch: null, community_difficulty: { value: null, votes: 0 }, par: null });
    expect(items[0]).toMatchObject({ likes: 2, players: 1 });
    expect(await list("?sort=top&page=0")).toEqual(items);
  });

  it("gives the latest version's stored sketch parsed, or null when it has none or is malformed", async () => {
    await env.DB.prepare(`UPDATE versions SET sketch = '{"bounds":[0,0,1,1]}' WHERE level = 'lvl_bbbbbbbbbb' AND version = 2`).run();
    await env.DB.prepare(`UPDATE versions SET sketch = 'not json' WHERE level = 'lvl_aaaaaaaaaa'`).run();
    const items = await list();
    expect(items.find((i) => i.level_id === "lvl_bbbbbbbbbb")).toMatchObject({ sketch: { bounds: [0, 0, 1, 1] } });
    expect(items.find((i) => i.level_id === "lvl_aaaaaaaaaa")).toMatchObject({ sketch: null });
    expect(items.find((i) => i.level_id === "lvl_cccccccccc")).toMatchObject({ sketch: null });
  });

  it("gives the latest version's stored par, or null when it has none", async () => {
    await env.DB.prepare(`UPDATE versions SET par = 900 WHERE level = 'lvl_bbbbbbbbbb' AND version = 2`).run();
    const items = await list();
    expect(items.find((i) => i.level_id === "lvl_bbbbbbbbbb")).toMatchObject({ par: 900 });
    expect(items.find((i) => i.level_id === "lvl_aaaaaaaaaa")).toMatchObject({ par: null });
  });

  it("gives null for a stored sketch that parses to something other than an object", async () => {
    await env.DB.prepare(`UPDATE versions SET sketch = '[]' WHERE level = 'lvl_aaaaaaaaaa'`).run();
    await env.DB.prepare(`UPDATE versions SET sketch = '5' WHERE level = 'lvl_bbbbbbbbbb' AND version = 2`).run();
    await env.DB.prepare(`UPDATE versions SET sketch = 'null' WHERE level = 'lvl_cccccccccc'`).run();
    for (const item of await list()) expect(item).toMatchObject({ sketch: null });
  });

  it("orders new by the approval time of the latest version, and pages from 0", async () => {
    expect((await list("?sort=new")).map((i) => i.level_id)).toEqual(["lvl_cccccccccc", "lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb"]);
    expect(await list("?sort=new&page=1")).toEqual([]);
    for (let i = 0; i < 50; i++) await seedLevel(`lvl_x${String(i).padStart(9, "0")}`, "p_a", [1000 + i]);
    expect(await list("?sort=new&page=0")).toHaveLength(50);
    expect((await list("?sort=new&page=1")).map((i) => i.level_id)).toEqual(["lvl_cccccccccc", "lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb"]);
  });

  it("rejects an unknown sort or a malformed page", async () => {
    for (const query of ["?sort=best", "?page=-1", "?page=x", "?page=1.5", "?page=99999999"]) expect((await call("p_a", "GET", `/levels${query}`)).status).toBe(400);
    expect((await call(null, "GET", "/levels")).status).toBe(401);
  });
});

describe("player ranking", () => {
  const failing = () => new Github().fetchFn;
  const get = async (player: string) => (await call(player, "GET", "/players")).json() as Promise<{ rows: unknown[]; you: unknown }>;

  it("ranks players by the sum of their points on each level's latest version, with shared ranks for ties", async () => {
    for (const id of ["p_a", "p_b", "p_c", "p_d"]) await seedPlayer(id, `Name ${id}`);
    await seedPlayer("p_x", "Banned", 1);
    await seedLevel("lvl_aaaaaaaaaa", "p_a", [10, 20]);
    await seedLevel("lvl_bbbbbbbbbb", "p_a", [10]);
    await seedLevel("lvl_cccccccccc", "p_a", [10], { hidden: 1 });
    await seedScore("lvl_aaaaaaaaaa", 1, "p_a", 9000); // superseded version: ignored
    await seedScore("lvl_aaaaaaaaaa", 2, "p_a", 100);
    await seedScore("lvl_bbbbbbbbbb", 1, "p_a", 50);
    await seedScore("lvl_aaaaaaaaaa", 2, "p_b", 100);
    await seedScore("lvl_bbbbbbbbbb", 1, "p_c", 150);
    await seedScore("lvl_aaaaaaaaaa", 2, "p_x", 5000); // banned: excluded
    await seedScore("lvl_cccccccccc", 1, "p_d", 5000); // hidden level: ignored
    await runCron(testEnv, failing());

    const { rows: ranking, you } = await get("p_d");
    expect(ranking).toEqual([
      { rank: 1, player: { id: "p_a", name: "Name p_a" }, points: 150 },
      { rank: 1, player: { id: "p_c", name: "Name p_c" }, points: 150 },
      { rank: 3, player: { id: "p_b", name: "Name p_b" }, points: 100 },
    ]);
    expect(you).toBeNull();
    expect((await get("p_b")).you).toEqual({ rank: 3, player: { id: "p_b", name: "Name p_b" }, points: 100 });
  });

  it("hides a player banned after the last cron run", async () => {
    await seedPlayer("p_a");
    await seedLevel("lvl_aaaaaaaaaa", "p_a", [10]);
    await seedScore("lvl_aaaaaaaaaa", 1, "p_a", 100);
    await runCron(testEnv, failing());
    await env.DB.prepare("UPDATE players SET banned = 1").run();
    await seedPlayer("p_b");
    expect((await get("p_b")).rows).toEqual([]);
  });
});

describe("POST /levels/:level/report", () => {
  const report = (gh: Github, player: string, level: string, body: unknown = { reason: "Unplayable." }) =>
    tokenOf(player).then((token) => postReport(new Request("https://example.com/r", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) }), testEnv, { level }, gh.fetchFn).catch((e) => Response.json({ error: e.message }, { status: e.status })));

  beforeEach(async () => {
    await seedPlayer("p_a", "Alice");
    await seedLevel("lvl_aaaaaaaaaa", "p_a", [10, 20]);
  });

  it("opens an issue with the quoted reason, the latest version and the opaque player id, and refuses a second report", async () => {
    const gh = new Github();
    const response = await report(gh, "p_a", "lvl_aaaaaaaaaa", { reason: "Line one\n@someone is rude" });
    expect(response.status).toBe(201);
    expect(gh.issues).toHaveLength(1);
    const [issue] = gh.issues;
    expect(issue.title).toBe("Report: lvl_aaaaaaaaaa");
    expect(issue.labels).toEqual(["report"]);
    expect(issue.body).toContain("> Line one\n> @\u200bsomeone is rude");
    expect(issue.body).toContain("latest version 2");
    expect(issue.body).toContain("p_a");
    expect(issue.body).not.toContain("Alice");

    const again = await report(gh, "p_a", "lvl_aaaaaaaaaa");
    expect(again.status).toBe(409);
    expect(gh.issues).toHaveLength(1);
  });

  it("opens the issue without the label when GitHub refuses it", async () => {
    const gh = new Github();
    gh.labelError = 422;
    expect((await report(gh, "p_a", "lvl_aaaaaaaaaa")).status).toBe(201);
    expect(gh.issues).toHaveLength(1);
    expect(gh.issues[0].labels).toBeUndefined();
  });

  it("does not retry without the label on a server error", async () => {
    const gh = new Github();
    gh.labelError = 500;
    expect((await report(gh, "p_a", "lvl_aaaaaaaaaa")).status).toBe(502);
    expect(gh.ops()).toEqual(["POST /issues"]);
    expect(gh.issues).toEqual([]);
  });

  it("keeps a lone carriage return inside the blockquote", async () => {
    const gh = new Github();
    expect((await report(gh, "p_a", "lvl_aaaaaaaaaa", { reason: "one\rtwo\r\nthree" })).status).toBe(201);
    expect(gh.issues[0]!.body).toContain("> one\n> two\n> three\n");
  });

  it("lets the player try again when GitHub is down", async () => {
    const gh = new Github();
    gh.down = true;
    expect((await report(gh, "p_a", "lvl_aaaaaaaaaa")).status).toBe(502);
    expect(await rows("SELECT * FROM reports")).toEqual([]);
    gh.down = false;
    expect((await report(gh, "p_a", "lvl_aaaaaaaaaa")).status).toBe(201);
  });

  it("validates the reason and the level", async () => {
    const gh = new Github();
    for (const body of [{}, { reason: "" }, { reason: "   " }, { reason: 7 }, { reason: "x".repeat(501) }]) expect((await report(gh, "p_a", "lvl_aaaaaaaaaa", body)).status).toBe(400);
    expect((await report(gh, "p_a", "lvl_zzzzzzzzzz")).status).toBe(404);
    expect((await report(gh, "p_a", "lvl_aaaaaaaaaa", { reason: "x".repeat(500) })).status).toBe(201);
    const big = await call("p_a", "POST", "/levels/lvl_aaaaaaaaaa/report", { reason: "x".repeat(5000) });
    expect(big.status).toBe(413);
  });

  it("allows 10 reports per player per day", async () => {
    const gh = new Github();
    for (let i = 0; i < 11; i++) await seedLevel(`lvl_r${String(i).padStart(9, "0")}`, "p_a", [10]);
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) statuses.push((await report(gh, "p_a", `lvl_r${String(i).padStart(9, "0")}`)).status);
    expect(statuses).toEqual([...Array(10).fill(201), 429]);
    expect(gh.issues).toHaveLength(10);
  });
});

describe("GET /index", () => {
  const index = (gh: { fetchFn: typeof fetch }) => tokenOf("p_a").then((token) => getIndex(new Request("https://example.com/index", { headers: { Authorization: `Bearer ${token}` } }), testEnv, {}, gh.fetchFn).catch((e) => Response.json({ error: e.message }, { status: e.status })));

  it("answers the head commit of main and caches it for a minute", async () => {
    await seedPlayer("p_a");
    const down = new Github();
    down.down = true;
    expect((await index(down)).status).toBe(502);

    const gh = new Github();
    expect(await (await index(gh)).json()).toEqual({ commit: "head0" });
    gh.head = "head1";
    expect(await (await index(gh)).json()).toEqual({ commit: "head0" });
    expect(gh.ops()).toEqual(["GET /git/ref/heads/main"]);
  });
});

describe("cron", () => {
  it("deletes only unreferenced demos older than an hour", async () => {
    const kept = "demos/lvl/p_a/kept.demo.gz";
    await env.DB.prepare("INSERT INTO scores VALUES ('s', 'p_a', 1, 1, 1, 1, ?, 1)").bind(kept).run();
    await env.DEMOS.put(kept, new Uint8Array([1]));
    await env.DEMOS.put("demos/lvl/p_a/orphan.demo.gz", new Uint8Array([1]));
    await env.DEMOS.put("levels/cached.json", new Uint8Array([1]));
    const gh = new Github();
    gh.down = true;
    const keys = async () => (await env.DEMOS.list()).objects.map((o) => o.key).sort();

    await runCron(testEnv, gh.fetchFn);
    expect(await keys()).toEqual(["demos/lvl/p_a/kept.demo.gz", "demos/lvl/p_a/orphan.demo.gz", "levels/cached.json"]);

    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 2 * 3600_000);
    await runCron(testEnv, gh.fetchFn);
    expect(await keys()).toEqual(["demos/lvl/p_a/kept.demo.gz", "levels/cached.json"]);
  });

  it("clears old rate windows and expired nonces, and goes on when GitHub fails", async () => {
    const now = Math.floor(Date.now() / 1000);
    const minute = Math.floor(now / 60);
    const day = Math.floor(now / 86400);
    await env.DB.prepare(
      `INSERT INTO rate (player, action, "window", count) VALUES
       ('p', 'score', ?, 1), ('p', 'score', ?, 1), ('p', 'submit', ?, 1), ('p', 'submit', ?, 1), ('p', 'report', ?, 1), ('p', 'report', ?, 1)`,
    )
      .bind(minute - 3, minute - 1, day - 3, day - 1, day - 3, day)
      .run();
    await env.DB.prepare("INSERT INTO nonces VALUES ('old', ?), ('fresh', ?)").bind(now - 1, now + 300).run();
    await seedPlayer("p_a");
    await seedLevel("lvl_aaaaaaaaaa", "p_a", [10]);
    await seedScore("lvl_aaaaaaaaaa", 1, "p_a", 7);
    const gh = new Github();
    gh.down = true;
    vi.spyOn(console, "error").mockImplementation(() => {});

    await runCron(testEnv, gh.fetchFn);
    expect(gh.calls.length).toBeGreaterThan(0); // the index rebuild was attempted
    expect(await rows("SELECT action, \"window\" FROM rate ORDER BY action, \"window\"")).toEqual([
      { action: "report", window: day },
      { action: "score", window: minute - 1 },
      { action: "submit", window: day - 1 },
    ]);
    expect(await rows("SELECT nonce FROM nonces")).toEqual([{ nonce: "fresh" }]);
    expect(await rows("SELECT player, points, rank FROM player_ranking")).toEqual([{ player: "p_a", points: 7, rank: 1 }]);
  });

  it("resumes the demo sweep where the previous run stopped, and wraps around when the listing ends", async () => {
    const keyOf = (i: number | string) => `demos/lvl/p_a/o${i}.demo.gz`;
    for (let i = 0; i < 7; i++) await env.DEMOS.put(keyOf(i), new Uint8Array([1]));
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 2 * 3600_000);
    const keys = async () => (await env.DEMOS.list()).objects.map((o) => o.key);

    await sweepDemos(testEnv, 1); // five pages of one object
    expect(await keys()).toEqual([keyOf(5), keyOf(6)]);
    expect(await rows("SELECT last_key FROM sweep")).toEqual([{ last_key: keyOf(4) }]);

    await sweepDemos(testEnv, 1);
    expect(await keys()).toEqual([]);
    expect(await rows("SELECT last_key FROM sweep")).toEqual([]);

    await env.DEMOS.put(keyOf("0a"), new Uint8Array([1])); // sorts before the old cursor: only a wrapped sweep sees it
    await sweepDemos(testEnv, 1);
    expect(await keys()).toEqual([]);
  });

  it("runs every step even when one throws", async () => {
    await env.DEMOS.put("demos/lvl/p_a/orphan.demo.gz", new Uint8Array([1]));
    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 2 * 3600_000);
    vi.spyOn(console, "error").mockImplementation(() => {});
    const broken = {
      ...testEnv,
      DB: new Proxy(env.DB, {
        get(target, prop) {
          if (prop !== "prepare") return Reflect.get(target, prop, target).bind(target);
          return (sql: string) => {
            if (sql.startsWith("DELETE FROM player_ranking")) throw new Error("D1 is down");
            return target.prepare(sql);
          };
        },
      }) as unknown as D1Database,
    };
    const gh = new Github();
    gh.down = true;
    await runCron(broken, gh.fetchFn);
    expect((await env.DEMOS.list()).objects).toEqual([]);
    expect(gh.calls.length).toBeGreaterThan(0);
  });
});

describe("demo expiry", () => {
  const DAY = 86400;
  const seconds = () => Math.floor(Date.now() / 1000);
  const demoOf = async (sha: string, player: string) => (await rows<{ demo: string }>("SELECT demo FROM scores WHERE sha256 = ? AND player = ?", sha, player))[0]!.demo;
  async function run(sha: string, player: string, points: number, postedDaysAgo: number) {
    const key = `demos/${sha}/${player}/k${points}${postedDaysAgo}.demo.gz`;
    await env.DB.prepare("INSERT INTO scores VALUES (?, ?, ?, 1, 1, 1, ?, ?)").bind(sha, player, points, key, seconds() - postedDaysAgo * DAY).run();
    await env.DEMOS.put(key, new Uint8Array([1]));
    return key;
  }

  it("keeps each level's top 10 and expires the rest after 14 days", async () => {
    const a = hash("a1");
    const b = hash("b2");
    const keys: Record<string, string> = {};
    for (let i = 1; i <= 13; i++) {
      await seedPlayer(`p_${String(i).padStart(16, "0")}`);
    }
    const p = (i: number) => `p_${String(i).padStart(16, "0")}`;
    // Level a: ranks 1-9 at 2000-1200, two runs tied for 10th at 1000, then 900 and 800. All 20 days old except p13.
    for (let i = 1; i <= 9; i++) keys[p(i)] = await run(a, p(i), 2100 - i * 100, 20);
    keys[p(10)] = await run(a, p(10), 1000, 20);
    keys[p(11)] = await run(a, p(11), 1000, 20);
    keys[p(12)] = await run(a, p(12), 900, 20);
    keys[p(13)] = await run(a, p(13), 800, 3);
    // Level b: a separate board; p12 is first there and keeps that demo.
    const bKey = await run(b, p(12), 500, 20);

    expect(await expireDemos(env)).toBe(1);
    for (let i = 1; i <= 11; i++) expect(await demoOf(a, p(i)), `rank ${i}`).toBe(keys[p(i)]);
    expect(await demoOf(a, p(12))).toBe(""); // 12th place, 20 days old
    expect(await env.DEMOS.head(keys[p(12)]!)).toBeNull();
    expect(await demoOf(a, p(13))).toBe(keys[p(13)]); // 13th place but only 3 days old
    expect(await demoOf(b, p(12))).toBe(bKey);

    vi.spyOn(Date, "now").mockReturnValue(Date.now() + 12 * DAY * 1000);
    expect(await expireDemos(env)).toBe(1);
    expect(await demoOf(a, p(13))).toBe("");
    expect(await rows("SELECT * FROM scores WHERE sha256 = ?", a)).toHaveLength(13); // scores themselves stay
  });

  it("expires a banned player's old demo and ranks around banned players", async () => {
    const sha = hash("c3");
    await seedPlayer("p_banned0000000000", "Cheat", 1);
    const banned = await run(sha, "p_banned0000000000", 99999, 20);
    const honest: string[] = [];
    for (let i = 1; i <= 10; i++) {
      const id = `p_honest${String(i).padStart(10, "0")}`;
      await seedPlayer(id);
      honest.push(await run(sha, id, 1000 - i, 20));
    }
    expect(await expireDemos(env)).toBe(1);
    expect(await env.DEMOS.head(banned)).toBeNull();
    for (const key of honest) expect(await env.DEMOS.head(key)).not.toBeNull(); // the banned run does not push the 10th out
  });

  it("shows an expired demo as none on the board", async () => {
    await seedPlayer("p_viewer0000000000");
    await env.DB.prepare("INSERT INTO official_levels VALUES (?, 'level_01', 'r1')").bind(hash("d4")).run();
    await env.DB.prepare("INSERT INTO scores VALUES (?, 'p_viewer0000000000', 5, 1, 1, 1, '', 1)").bind(hash("d4")).run();
    const response = await call("p_viewer0000000000", "GET", `/boards/${hash("d4")}`);
    expect(((await response.json()) as { rows: { demo: string | null }[] }).rows[0]!.demo).toBeNull();
  });
});
