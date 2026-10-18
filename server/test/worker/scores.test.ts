import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { sha256Hex } from "../../src/core/level";
import type { Env } from "../../src/env";
import { postScore } from "../../src/scores";
import worker from "../../src/worker";

const testEnv: Env = { ...env, ALLOW_TEST_VERIFIER: "1" };
const bytes = (b64: string) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const LEVEL_01 = bytes(env.LEVEL_01);
const DEMO_01 = bytes(env.DEMO_LEVEL_01);
const LEVEL_05 = bytes(env.LEVEL_05);
const DEMO_05 = bytes(env.DEMO_LEVEL_05);
const SHA_01 = await sha256Hex(LEVEL_01);
const SHA_05 = await sha256Hex(LEVEL_05);
const POINTS_01 = 2522; // fixtures/expected.json
const POINTS_05 = 1307;

const call = (path: string, init?: RequestInit) => worker.fetch(new Request(`https://example.com${path}`, init), testEnv);
const nonce = async () => ((await (await call("/nonce")).json()) as { nonce: string }).nonce;

async function signIn(id: string, name: string) {
  const n = await nonce();
  const response = await call("/session", { method: "POST", body: JSON.stringify({ authCode: `test:${id}:${name}`, integrityToken: `ok:${n}`, nonce: n }) });
  return ((await response.json()) as { token: string; player: { id: string } });
}

/** The URLs the fake network knows; anything else is a 404. `fetched` records what was asked for. */
function network(files: Record<string, Uint8Array<ArrayBuffer>>) {
  const fetched: string[] = [];
  const fetchFn = (async (input: RequestInfo | URL) => {
    fetched.push(String(input));
    const file = files[String(input)];
    return file ? new Response(file) : new Response("missing", { status: 404 });
  }) as typeof fetch;
  return { fetchFn, fetched };
}

const OFFICIAL_URL = "https://raw.githubusercontent.com/BRAITG/zero-gx/r1/levels/level_01.json";
const officialNetwork = () => network({ [OFFICIAL_URL]: LEVEL_01 });

async function post(token: string, body: BodyInit, fetchFn: typeof fetch, headers: Record<string, string> = {}) {
  const n = await nonce();
  const request = new Request("https://example.com/scores", {
    method: "POST",
    body,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/octet-stream", "X-Integrity": `ok:${n}`, "X-Nonce": n, ...headers },
  });
  return postScore(request, testEnv, {}, fetchFn).then(
    (r) => r,
    (e) => Response.json({ error: e.message }, { status: e.status }),
  );
}

const demoKeys = async (sha: string, player: string) => (await env.DEMOS.list({ prefix: `demos/${sha}/${player}/` })).objects.map((o) => o.key);
const scoreRows = async (sha: string) =>
  (await env.DB.prepare("SELECT * FROM scores WHERE sha256 = ?").bind(sha).all<{ player: string; points: number; demo: string }>()).results;

async function seedScore(sha: string, player: string, points: number): Promise<string> {
  const key = `demos/${sha}/${player}/seeded0000.demo.gz`;
  await env.DEMOS.put(key, new Uint8Array([1, 2, 3]));
  await env.DB.prepare("INSERT INTO scores VALUES (?, ?, ?, 1, 1, 1, ?, 1)").bind(sha, player, points, key).run();
  return key;
}

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM scores"),
    env.DB.prepare("DELETE FROM rate"),
    env.DB.prepare("DELETE FROM official_levels"),
    env.DB.prepare("DELETE FROM versions"),
    env.DB.prepare("DELETE FROM levels"),
    env.DB.prepare("DELETE FROM hidden_levels"),
    env.DB.prepare("INSERT INTO official_levels VALUES (?, 'level_01', 'r1')").bind(SHA_01),
  ]);
  const { objects } = await env.DEMOS.list();
  if (objects.length) await env.DEMOS.delete(objects.map((o) => o.key));
});

describe("POST /scores", () => {
  it("scores an official demo, stores it in R2 and caches the verified level", async () => {
    const { token, player } = await signIn("s-1", "Ada");
    const net = officialNetwork();
    const response = await post(token, DEMO_01, net.fetchFn);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ points: POINTS_01, rank: 1, best: true });
    const [row] = await scoreRows(SHA_01);
    expect(row).toMatchObject({ player: player.id, points: POINTS_01 });
    expect(row!.demo).toMatch(new RegExp(`^demos/${SHA_01}/${player.id}/[a-z0-9]{24}\\.demo\\.gz$`));
    expect(new Uint8Array(await (await env.DEMOS.get(row!.demo))!.arrayBuffer())).toEqual(DEMO_01);
    expect(await env.DEMOS.head(`levels/${SHA_01}.json`)).not.toBeNull();
  });

  it("serves a cached level from R2 without fetching", async () => {
    await env.DEMOS.put(`levels/${SHA_01}.json`, LEVEL_01);
    const { token } = await signIn("s-2", "Bo");
    const net = network({});
    expect((await post(token, DEMO_01, net.fetchFn)).status).toBe(200);
    expect(net.fetched).toEqual([]);
  });

  it("fetches a community level from the levels repository", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO levels (id, owner, latest, created) VALUES ('lvl_aaaaaaaaaa', 'p_x', 2, 1)"),
      env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES ('lvl_aaaaaaaaaa', 2, ?, 1)").bind(SHA_05),
    ]);
    const { token } = await signIn("s-3", "Cy");
    const net = network({ "https://raw.githubusercontent.com/BRAITG/zero-gx-levels/main/levels/lvl_aaaaaaaaaa/v2.json": LEVEL_05 });
    const response = await post(token, DEMO_05, net.fetchFn);
    expect(await response.json()).toEqual({ points: POINTS_05, rank: 1, best: true });
  });

  it("answers 502 when the fetched level does not match its hash, and caches nothing", async () => {
    const { token } = await signIn("s-4", "Di");
    const net = network({ [OFFICIAL_URL]: LEVEL_05 });
    const response = await post(token, DEMO_01, net.fetchFn);
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "The level file did not match its hash." });
    expect(await env.DEMOS.head(`levels/${SHA_01}.json`)).toBeNull();
  });

  it("replaces a worse score and deletes its demo", async () => {
    const { token, player } = await signIn("s-5", "Ed");
    const old = await seedScore(SHA_01, player.id, 100);
    const response = await post(token, DEMO_01, officialNetwork().fetchFn);
    expect(await response.json()).toEqual({ points: POINTS_01, rank: 1, best: true });
    const rows = await scoreRows(SHA_01);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.points).toBe(POINTS_01);
    expect(await demoKeys(SHA_01, player.id)).toEqual([rows[0]!.demo]);
    expect(await env.DEMOS.head(old)).toBeNull();
  });

  it("ranks a post that did not beat the stored score by the stored score, and deletes the new demo", async () => {
    const { token, player } = await signIn("s-6", "Flo");
    await seedScore(SHA_01, "p_other0000000003", 9500);
    const old = await seedScore(SHA_01, player.id, 9000);
    const response = await post(token, DEMO_01, officialNetwork().fetchFn);
    expect(await response.json()).toEqual({ points: POINTS_01, rank: 2, best: false });
    expect((await scoreRows(SHA_01)).find((r) => r.player === player.id)).toMatchObject({ points: 9000, demo: old });
    expect(await demoKeys(SHA_01, player.id)).toEqual([old]);
  });

  it("never leaves the row pointing at a deleted demo when a competing post lands between upload and write", async () => {
    const { token, player } = await signIn("s-6b", "Fay");
    const old = await seedScore(SHA_01, player.id, 100);
    let rival: Response | undefined;
    const hooked = {
      get: (k: string) => env.DEMOS.get(k),
      head: (k: string) => env.DEMOS.head(k),
      delete: (k: string | string[]) => env.DEMOS.delete(k),
      put: async (k: string, v: ArrayBuffer | Uint8Array) => {
        const stored = await env.DEMOS.put(k, v);
        if (k.startsWith("demos/") && !rival) rival = await post(token, DEMO_01, officialNetwork().fetchFn); // a whole second post runs here
        return stored;
      },
    } as unknown as R2Bucket;
    const n = await nonce();
    const request = new Request("https://example.com/scores", { method: "POST", body: DEMO_01, headers: { Authorization: `Bearer ${token}`, "X-Integrity": `ok:${n}`, "X-Nonce": n } });
    const response = await postScore(request, { ...testEnv, DEMOS: hooked }, {}, officialNetwork().fetchFn);
    expect(response.status).toBe(200);
    expect(rival!.status).toBe(200);
    const [row] = await scoreRows(SHA_01);
    expect(await env.DEMOS.head(row!.demo)).not.toBeNull();
    expect(await demoKeys(SHA_01, player.id)).toEqual([row!.demo]);
    expect(await env.DEMOS.head(old)).toBeNull();
  });

  it("ranks by points with ties sharing a rank", async () => {
    const { token } = await signIn("s-7", "Gus");
    await seedScore(SHA_01, "p_other0000000001", 9000);
    await seedScore(SHA_01, "p_other0000000002", POINTS_01);
    const response = await post(token, DEMO_01, officialNetwork().fetchFn);
    expect(await response.json()).toEqual({ points: POINTS_01, rank: 2, best: true });
  });

  it("leaves one row and one demo when two posts race", async () => {
    const { token, player } = await signIn("s-8", "Hal");
    const net = officialNetwork();
    const both = await Promise.all([post(token, DEMO_01, net.fetchFn), post(token, DEMO_01, net.fetchFn)]);
    expect(both.map((r) => r.status)).toEqual([200, 200]);
    const rows = await scoreRows(SHA_01);
    expect(rows).toHaveLength(1);
    expect(await demoKeys(SHA_01, player.id)).toEqual([rows[0]!.demo]);
  });

  it("answers 404 for an unknown hash and for a hidden level", async () => {
    const { token } = await signIn("s-9", "Ivy");
    const net = network({ "https://raw.githubusercontent.com/BRAITG/zero-gx-levels/main/levels/lvl_bbbbbbbbbb/v1.json": LEVEL_05 });
    expect((await post(token, DEMO_05, net.fetchFn)).status).toBe(404);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO levels (id, owner, latest, created) VALUES ('lvl_bbbbbbbbbb', 'p_x', 1, 1)"),
      env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES ('lvl_bbbbbbbbbb', 1, ?, 1)").bind(SHA_05),
    ]);
    expect((await post(token, DEMO_05, net.fetchFn)).status).toBe(200);
    await env.DB.prepare("UPDATE levels SET hidden = 1 WHERE id = 'lvl_bbbbbbbbbb'").run();
    expect((await post(token, DEMO_05, net.fetchFn)).status).toBe(404);
    await env.DB.batch([env.DB.prepare("UPDATE levels SET hidden = 0"), env.DB.prepare("INSERT INTO hidden_levels VALUES ('lvl_bbbbbbbbbb')")]);
    expect((await post(token, DEMO_05, net.fetchFn)).status).toBe(404);
  });

  it("answers 429 on the 31st post within a minute", async () => {
    const { token, player } = await signIn("s-10", "Jo");
    const window = Math.floor(Date.now() / 1000 / 60);
    await env.DB.prepare(`INSERT INTO rate (player, action, "window", count) VALUES (?, 'score', ?, 30)`).bind(player.id, window).run();
    const response = await post(token, DEMO_01, officialNetwork().fetchFn);
    expect(response.status).toBe(429);
    expect(await scoreRows(SHA_01)).toHaveLength(0);
  });

  it("rejects a tampered demo with 400 naming the rule", async () => {
    const { token } = await signIn("s-11", "Kit");
    const response = await post(token, bytes(env.DEMO_TELEPORT), officialNetwork().fetchFn);
    expect(response.status).toBe(400);
    expect(((await response.json()) as { error: string }).error).toContain("px in one frame");
    expect(await scoreRows(SHA_01)).toHaveLength(0);
    expect((await env.DEMOS.list({ prefix: "demos/" })).objects).toHaveLength(0);
  });

  it("rejects bytes that are not a demo with 400", async () => {
    const { token } = await signIn("s-12", "Lou");
    const response = await post(token, new Uint8Array([1, 2, 3]), officialNetwork().fetchFn);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "The demo could not be read." });
  });

  it("rejects a body over 512 KB with 413", async () => {
    const { token } = await signIn("s-13", "Max");
    const n = await nonce();
    const response = await call("/scores", {
      method: "POST",
      body: new Uint8Array(524289),
      headers: { Authorization: `Bearer ${token}`, "X-Integrity": `ok:${n}`, "X-Nonce": n },
    });
    expect(response.status).toBe(413);
  });

  it("rejects a missing integrity token with 403 and a missing session with 401", async () => {
    const { token } = await signIn("s-14", "Ned");
    const withSession = await call("/scores", { method: "POST", body: DEMO_01, headers: { Authorization: `Bearer ${token}` } });
    expect(withSession.status).toBe(403);
    expect((await call("/scores", { method: "POST", body: DEMO_01 })).status).toBe(401);
  });
});

describe("GET /boards/<sha256>", () => {
  const board = (token: string, sha = SHA_01) => call(`/boards/${sha}`, { headers: { Authorization: `Bearer ${token}` } });

  it("lists the top 100 by points, then who posted first, with the requester's own row", async () => {
    const { token, player } = await signIn("b-1", "Ola");
    const stmts = [];
    for (let i = 0; i < 105; i++) {
      const id = `p_board${String(i).padStart(11, "0")}`;
      stmts.push(env.DB.prepare("INSERT OR IGNORE INTO players (id, name, created) VALUES (?, ?, 1)").bind(id, `P${i}`));
      stmts.push(env.DB.prepare("INSERT INTO scores VALUES (?, ?, ?, 1, 2, 3, ?, ?)").bind(SHA_01, id, 1000 + (i % 50), `demos/${SHA_01}/${id}/file0000.demo.gz`, i));
    }
    stmts.push(env.DB.prepare("INSERT INTO scores VALUES (?, ?, 1, 1, 2, 3, 'demos/x', 1)").bind(SHA_01, player.id));
    await env.DB.batch(stmts);
    const response = await board(token);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { level: unknown; rows: { rank: number; player: { id: string; name: string }; points: number; fuel: number; hull: number; seconds: number; demo: string }[]; you: unknown };
    expect(body.level).toEqual({ kind: "official", name: "level_01" });
    expect(body.rows).toHaveLength(100);
    expect(body.rows[0]).toEqual({
      rank: 1,
      player: { id: "p_board00000000049", name: "P49" },
      points: 1049,
      fuel: 1,
      hull: 2,
      seconds: 3,
      demo: `demos/${SHA_01}/p_board00000000049/file0000.demo.gz`,
    });
    expect(body.rows[1]).toMatchObject({ rank: 1, points: 1049, player: { id: "p_board00000000099" } });
    expect(body.rows[2]!.rank).toBe(3);
    expect(body.you).toMatchObject({ rank: 106, points: 1, player: { id: player.id, name: "Ola" } });
  });

  it("names a community level <id>/v<N> and returns null for you with no score", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO levels (id, owner, latest, created) VALUES ('lvl_cccccccccc', 'p_x', 1, 1)"),
      env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES ('lvl_cccccccccc', 1, ?, 1)").bind(SHA_05),
    ]);
    const { token } = await signIn("b-2", "Pia");
    const body = (await (await board(token, SHA_05)).json()) as { level: unknown; rows: unknown[]; you: unknown };
    expect(body).toEqual({ level: { kind: "community", name: "lvl_cccccccccc/v1" }, rows: [], you: null });
  });

  it("answers 404 for an unknown hash, a malformed hash and a hidden level; 401 without a session", async () => {
    const { token } = await signIn("b-3", "Quin");
    expect((await board(token, "0".repeat(64))).status).toBe(404);
    expect((await board(token, "ABC")).status).toBe(404);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO levels (id, owner, latest, hidden, created) VALUES ('lvl_dddddddddd', 'p_x', 1, 1, 1)"),
      env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES ('lvl_dddddddddd', 1, ?, 1)").bind(SHA_05),
    ]);
    expect((await board(token, SHA_05)).status).toBe(404);
    expect((await call(`/boards/${SHA_01}`)).status).toBe(401);
  });
});

describe("GET /demos/<key>", () => {
  const PLAYER = "p_abcdefghij012345";
  const KEY = `demos/${SHA_01}/${PLAYER}/abcdefgh.demo.gz`;
  const get = (path: string, token: string) => call(path, { headers: { Authorization: `Bearer ${token}` } });

  it("serves a stored demo as octet-stream", async () => {
    await env.DEMOS.put(KEY, DEMO_01);
    const { token } = await signIn("d-1", "Rae");
    const response = await get(`/${KEY}`, token);
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("application/octet-stream");
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(DEMO_01);
  });

  it("answers 404 for a missing demo, a key outside the pattern and a traversal; 401 without a session", async () => {
    await env.DEMOS.put(`levels/${SHA_01}.json`, LEVEL_01);
    const { token } = await signIn("d-2", "Sid");
    for (const path of [`/${KEY}`, `/demos/${SHA_01}/${PLAYER}/short.demo.gz`, `/demos/${SHA_01}/${PLAYER}/a%2Fb-12345.demo.gz`, "/demos/%2e%2e/x/y", `/demos/${SHA_01}/%2e%2e/${SHA_01}.json`, "/demos/../x"]) {
      expect((await get(path, token)).status, path).toBe(404);
    }
    expect((await call(`/${KEY}`)).status).toBe(401);
  });
});

describe("router", () => {
  it("answers 404, not 500, for a malformed percent-escape", async () => {
    const { token } = await signIn("r-1", "Tom");
    const response = await call("/boards/%zz", { headers: { Authorization: `Bearer ${token}` } });
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "Not found." });
  });
});

describe("POST /admin/official", () => {
  const admin = (body: unknown, token: string | null = "test-admin-token") =>
    call("/admin/official", { method: "POST", body: JSON.stringify(body), headers: token ? { Authorization: `Bearer ${token}` } : {} });
  const SHA = "a".repeat(64);

  it("refuses a missing or wrong token with 401, also when ADMIN_TOKEN is unset", async () => {
    const body = { release: "r2", levels: [{ name: "level_01", sha256: SHA }] };
    expect((await admin(body, "wrong")).status).toBe(401);
    expect((await admin(body, null)).status).toBe(401);
    const unset = await worker.fetch(
      new Request("https://example.com/admin/official", { method: "POST", body: JSON.stringify(body), headers: { Authorization: "Bearer " } }),
      { ...testEnv, ADMIN_TOKEN: "" },
    );
    expect(unset.status).toBe(401);
    expect(await env.DB.prepare("SELECT 1 FROM official_levels WHERE sha256 = ?").bind(SHA).first()).toBeNull();
  });

  it("registers levels and updates them on a later release", async () => {
    expect((await admin({ release: "r2", levels: [{ name: "level_01", sha256: SHA }] })).status).toBe(200);
    expect((await admin({ release: "r3", levels: [{ name: "level_02", sha256: SHA }] })).status).toBe(200);
    const rows = (await env.DB.prepare("SELECT * FROM official_levels WHERE sha256 = ?").bind(SHA).all()).results;
    expect(rows).toEqual([{ sha256: SHA, name: "level_02", release: "r3" }]);
  });

  it("validates release, names, hashes and the level count", async () => {
    const ok = { name: "level_01", sha256: SHA };
    const bad = [
      { release: "r 2", levels: [ok] },
      { release: "r2", levels: [] },
      { release: "r2", levels: [{ name: "level_1", sha256: SHA }] },
      { release: "r2", levels: [{ name: "level_01", sha256: "A".repeat(64) }] },
      { release: "r2", levels: Array.from({ length: 201 }, () => ok) },
      { release: "r2" },
    ];
    for (const body of bad) expect((await admin(body)).status, JSON.stringify(body).slice(0, 80)).toBe(400);
  });
});
