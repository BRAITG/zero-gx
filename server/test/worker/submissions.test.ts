import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { sha256Hex } from "../../src/core/level";
import type { Env } from "../../src/env";
import { boundNonce } from "../../src/session";
import { installationToken } from "../../src/github";
import { getMySubmissions, postGithub, postSubmission } from "../../src/submissions";
import worker from "../../src/worker";

const bytes = (b64: string) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const LEVEL_01 = bytes(env.LEVEL_01);
const DEMO_01 = bytes(env.DEMO_LEVEL_01);
const LEVEL_05 = bytes(env.LEVEL_05);
const DEMO_TELEPORT = bytes(env.DEMO_TELEPORT);
const LEVEL_01_TEXT = new TextDecoder().decode(LEVEL_01);
const LEVEL_05_TEXT = new TextDecoder().decode(LEVEL_05);
const SHA_01 = await sha256Hex(LEVEL_01);
const SHA_05 = await sha256Hex(LEVEL_05);
const REPO = "/repos/BRAITG/zero-gx-levels";
const SECRET = "hook-secret";

const pem = (label: string, der: ArrayBuffer) => `-----BEGIN ${label}-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END ${label}-----`;
const keyPair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const APP_KEY = pem("PRIVATE KEY", await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));

const testEnv: Env = { ...env, ALLOW_TEST_VERIFIER: "1", GITHUB_APP_ID: "12345", GITHUB_INSTALLATION_ID: "678", GITHUB_APP_KEY: APP_KEY, GITHUB_WEBHOOK_SECRET: SECRET };

const call = (path: string, init?: RequestInit) => worker.fetch(new Request(`https://example.com${path}`, init), testEnv);
const nonce = async () => ((await (await call("/nonce")).json()) as { nonce: string }).nonce;
const failed = (e: { message: string; status?: number }) => Response.json({ error: e.message }, { status: e.status ?? 500 });

async function signIn(id: string, name: string) {
  const n = await nonce();
  const response = await call("/session", { method: "POST", body: JSON.stringify({ authCode: `test:${id}:${name}`, integrityToken: `ok:${n}`, nonce: n }) });
  return (await response.json()) as { token: string; player: { id: string } };
}

interface Call {
  method: string;
  path: string;
  body: any;
  headers: Headers;
}

/** A fake GitHub that keeps just enough state (files, branches, pull requests) to answer the calls the Worker makes. */
class Github {
  calls: Call[] = [];
  files = new Map<string, { text: string; sha: string }>();
  branches = new Set<string>();
  comments = new Map<number, { body: string; author_association: string }[]>();
  state = {
    nextPull: 1,
    conflicts: 0,
    fail: null as RegExp | null,
    shas: 0,
    /** A pull request that already exists for the branch: creating another answers 422. */
    existingPull: null as number | null,
    pullState: "open",
    /** Runs once, just before the next contents PUT is processed. */
    onPut: null as (() => Promise<void>) | null,
  };

  fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const { calls, files, branches, comments, state } = this;
    const url = new URL(String(input));
    const path = url.pathname + url.search;
    const method = init?.method ?? "GET";
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ method, path, body, headers: new Headers(init?.headers) });
    const json = (value: unknown, status = 200) => Response.json(value, { status });
    if (state.fail?.test(`${method} ${path}`)) return json({}, 500);
    if (path.startsWith("/app/")) return json({ token: "inst-token", expires_at: new Date(Date.now() + 3600_000).toISOString() }, 201);
    if (method === "GET" && path === `${REPO}/git/ref/heads/main`) return json({ object: { sha: "base0" } });
    if (method === "GET" && path === `${REPO}/git/commits/base0`) return json({ tree: { sha: "tree0" } });
    if (method === "POST" && path === `${REPO}/git/blobs`) return json({ sha: `blob${++state.shas}` }, 201);
    if (method === "POST" && path === `${REPO}/git/trees`) return json({ sha: `tree${++state.shas}` }, 201);
    if (method === "POST" && path === `${REPO}/git/commits`) return json({ sha: `commit${++state.shas}` }, 201);
    if (method === "POST" && path === `${REPO}/git/refs`) {
      if (branches.has(body.ref)) return json({}, 422);
      branches.add(body.ref);
      return json({}, 201);
    }
    if (method === "PATCH" && path.startsWith(`${REPO}/git/refs/heads/`)) return json({});
    if (method === "POST" && path === `${REPO}/pulls`) return state.existingPull ? json({}, 422) : json({ number: state.nextPull++ }, 201);
    if (method === "GET" && path.startsWith(`${REPO}/pulls?`)) return json(state.existingPull ? [{ number: state.existingPull }] : []);
    if (method === "GET" && path.match(/\/pulls\/\d+$/)) return json({ state: state.pullState, merged: state.pullState === "merged" });
    if (method === "PATCH" && path.startsWith(`${REPO}/pulls/`)) return json({});
    const thread = path.match(/\/issues\/(\d+)\/comments/);
    if (method === "GET" && thread) return json(comments.get(Number(thread[1])) ?? []);
    const contents = path.match(/\/contents\/([^?]+)/)?.[1];
    if (method === "GET" && contents) {
      const file = files.get(contents);
      // GitHub wraps base64 content in newlines.
      return file ? json({ sha: file.sha, content: `${btoa(file.text).replace(/(.{20})/g, "$1\n")}\n` }) : json({}, 404);
    }
    if (method === "PUT" && contents) {
      if (state.onPut) {
        const run = state.onPut;
        state.onPut = null;
        await run();
      }
      const current = files.get(contents);
      if (state.conflicts > 0) {
        state.conflicts--;
        return json({}, 409);
      }
      if (current && !body.sha) return json({}, 422);
      if (current?.sha !== body.sha) return json({}, 409);
      files.set(contents, { text: new TextDecoder().decode(bytes(body.content)), sha: `file${++state.shas}` });
      return json({}, 200);
    }
    return json({}, 404);
  }) as typeof fetch;

  /** Calls excluding the (cached) token exchange. */
  ops = () => this.calls.filter((c) => !c.path.startsWith("/app/")).map((c) => `${c.method} ${c.path.replace(REPO, "")}`);
  where = (method: string, path: string) => this.calls.filter((c) => c.method === method && c.path === `${REPO}${path}`);
}
const github = () => new Github();

interface Fields {
  level?: Uint8Array<ArrayBuffer>;
  demo?: Uint8Array<ArrayBuffer>;
  level_id?: string;
  based_on?: string;
}

async function submit(token: string, fields: Fields, gh: Github, submitEnv: Env = testEnv) {
  const n = await nonce();
  const form = new FormData();
  form.set("level", new File([fields.level ?? LEVEL_01], "level.json"));
  form.set("demo", new File([fields.demo ?? DEMO_01], "demo.gz"));
  if (fields.level_id) form.set("level_id", fields.level_id);
  if (fields.based_on) form.set("based_on", fields.based_on);
  const bound = await boundNonce(n, [fields.level ?? LEVEL_01, fields.demo ?? DEMO_01]);
  const request = new Request("https://example.com/submissions", { method: "POST", body: form, headers: { Authorization: `Bearer ${token}`, "X-Integrity": `ok:${bound}`, "X-Nonce": n } });
  return postSubmission(request, submitEnv, {}, gh.fetchFn).catch(failed);
}

async function sign(body: string, secret = SECRET) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return `sha256=${Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

async function hook(gh: Github, event: string, payload: object, signature?: string | null) {
  const body = JSON.stringify(payload);
  const headers: Record<string, string> = { "X-GitHub-Event": event };
  const given = signature === undefined ? await sign(body) : signature;
  if (given !== null) headers["X-Hub-Signature-256"] = given;
  return postGithub(new Request("https://example.com/github", { method: "POST", body, headers }), testEnv, {}, gh.fetchFn).catch(failed);
}

const repository = { full_name: "BRAITG/zero-gx-levels" };
const closed = (number: number, merged: boolean) => ({ action: "closed", repository, pull_request: { number, merged } });

const rows = async <T>(sql: string, ...values: unknown[]) => (await env.DB.prepare(sql).bind(...values).all<T>()).results;

async function seedLevel(id: string, owner: string, extra: { latest?: number; sha?: string; title?: string; hidden?: number } = {}) {
  const { latest = 0, sha, title = "Seeded", hidden = 0 } = extra;
  await env.DB.prepare("INSERT INTO levels (id, owner, latest, hidden, title, created) VALUES (?, ?, ?, ?, ?, 1)").bind(id, owner, latest, hidden, latest ? title : null).run();
  for (let v = 1; v <= latest; v++) await env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES (?, ?, ?, 1)").bind(id, v, v === latest && sha ? sha : `${id}-${v}`.padEnd(64, "0")).run();
}

async function seedOpen(level: string, version: number, player: string, pullRequest: number | null, title = "Seeded", sha = "f".repeat(64)) {
  await env.DB.prepare("INSERT INTO submissions (level, version, player, pull_request, status, created, title, sha256) VALUES (?, ?, ?, ?, 'open', 1, ?, ?)").bind(level, version, player, pullRequest, title, sha).run();
}

beforeEach(async () => {
  await env.DB.batch(["play_attempts", "play_summaries", "difficulty_votes", "submissions", "rate", "official_levels", "versions", "levels", "hidden_levels"].map((table) => env.DB.prepare(`DELETE FROM ${table}`)));
});

describe("installationToken", () => {
  it("signs an RS256 App JWT, sends the API headers and caches the token", async () => {
    const gh = github();
    const appEnv = { ...testEnv, GITHUB_APP_ID: "jwt-app" };
    expect(await installationToken(appEnv, gh.fetchFn)).toBe("inst-token");
    expect(await installationToken(appEnv, gh.fetchFn)).toBe("inst-token");
    expect(gh.calls).toHaveLength(1);
    const [token] = gh.calls;
    expect(token).toMatchObject({ method: "POST", path: "/app/installations/678/access_tokens" });
    expect(token!.headers.get("Accept")).toBe("application/vnd.github+json");
    expect(token!.headers.get("X-GitHub-Api-Version")).toBe("2022-11-28");
    expect(token!.headers.get("User-Agent")).toBe("zero-gx");
    const [header, claims, signature] = token!.headers.get("Authorization")!.replace("Bearer ", "").split(".") as [string, string, string];
    const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    expect(decode(header)).toEqual({ alg: "RS256", typ: "JWT" });
    const { iat, exp, iss } = decode(claims);
    expect(iss).toBe("jwt-app");
    expect(exp - iat).toBe(600);
    expect(Math.abs(iat + 60 - Date.now() / 1000)).toBeLessThan(5);
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", keyPair.publicKey, Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0)), new TextEncoder().encode(`${header}.${claims}`));
    expect(valid).toBe(true);
  });

  it("rejects a PKCS#1 key with a clear error and calls nothing", async () => {
    const gh = github();
    const pkcs1 = { ...testEnv, GITHUB_APP_ID: "pkcs1-app", GITHUB_APP_KEY: pem("RSA PRIVATE KEY", new ArrayBuffer(8)) };
    await expect(installationToken(pkcs1, gh.fetchFn)).rejects.toThrow(/PKCS#1.*pkcs8 -topk8/);
    expect(gh.calls).toEqual([]);
  });
});

describe("POST /submissions", () => {
  it("opens a branch with three files and a pull request for a new level", async () => {
    const { token, player } = await signIn("sub-1", "Ada");
    const gh = github();
    const response = await submit(token, {}, gh);
    expect(response.status).toBe(201);
    const result = (await response.json()) as { level_id: string; version: number; pull_request: number };
    expect(result).toEqual({ level_id: expect.stringMatching(/^lvl_[a-z0-9]{10}$/), version: 1, pull_request: 1 });
    const id = result.level_id;

    expect(gh.ops()).toEqual([
      "GET /git/ref/heads/main",
      "GET /git/commits/base0",
      "POST /git/blobs",
      "POST /git/blobs",
      "POST /git/blobs",
      "POST /git/trees",
      "POST /git/commits",
      "POST /git/refs",
      "POST /pulls",
    ]);
    const [levelBlob, demoBlob, metaBlob] = gh.where("POST", "/git/blobs").map((c) => c.body);
    expect(levelBlob).toEqual({ content: new TextDecoder().decode(LEVEL_01), encoding: "utf-8" });
    expect(demoBlob.encoding).toBe("base64");
    expect(bytes(demoBlob.content)).toEqual(DEMO_01);
    expect(metaBlob).toEqual({ content: `{"author":"${player.id}"}\n`, encoding: "utf-8" });
    const [tree] = gh.where("POST", "/git/trees");
    expect(tree!.body.base_tree).toBe("tree0");
    expect(tree!.body.tree.map((e: any) => [e.path, e.mode, e.type])).toEqual([
      [`levels/${id}/v1.json`, "100644", "blob"],
      [`proof/${id}/v1.demo.gz`, "100644", "blob"],
      [`levels/${id}/meta.json`, "100644", "blob"],
    ]);
    expect(gh.where("POST", "/git/commits")[0]!.body).toMatchObject({ message: `Submit ${id} v1`, parents: ["base0"] });
    expect(gh.where("POST", "/git/refs")[0]!.body.ref).toBe(`refs/heads/submission/${id}`);
    const [pull] = gh.where("POST", "/pulls");
    expect(pull!.body).toMatchObject({ title: `${JSON.parse(new TextDecoder().decode(LEVEL_01)).title} (${id} v1)`, head: `submission/${id}`, base: "main" });
    expect(pull!.body.body).toContain(player.id);
    expect(pull!.body.body).not.toContain("Ada");

    expect(await rows("SELECT id, owner, based_on, latest FROM levels")).toEqual([{ id, owner: player.id, based_on: null, latest: 0 }]);
    expect(await rows("SELECT level, version, player, status, pull_request, branch, sha256, title FROM submissions")).toEqual([
      { level: id, version: 1, player: player.id, status: "open", pull_request: 1, branch: `submission/${id}`, sha256: SHA_01, title: JSON.parse(new TextDecoder().decode(LEVEL_01)).title },
    ]);
  });

  it("records based_on in meta.json for a known hash and refuses an unknown one", async () => {
    const { token } = await signIn("sub-2", "Bo");
    await env.DB.prepare("INSERT INTO official_levels VALUES (?, 'level_05', 'r1')").bind(SHA_05).run();
    const unknown = github();
    const refused = await submit(token, { based_on: "a".repeat(64) }, unknown);
    expect(refused.status).toBe(400);
    expect(unknown.calls).toEqual([]);

    const gh = github();
    expect((await submit(token, { based_on: SHA_05 }, gh)).status).toBe(201);
    expect(JSON.parse(gh.where("POST", "/git/blobs")[2]!.body.content)).toMatchObject({ based_on: SHA_05 });
    expect(gh.where("POST", "/pulls")[0]!.body.body).toContain(SHA_05);
    expect((await rows<{ based_on: string }>("SELECT based_on FROM levels"))[0]!.based_on).toBe(SHA_05);
  });

  it("force-updates the branch and the pull request when the level is submitted again while open", async () => {
    const { token, player } = await signIn("sub-3", "Cy");
    const gh = github();
    const first = (await (await submit(token, {}, gh)).json()) as { level_id: string; pull_request: number };
    const before = gh.calls.length;
    const response = await submit(token, { level: LEVEL_05, demo: bytes(env.DEMO_LEVEL_05), level_id: first.level_id }, gh);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ level_id: first.level_id, version: 1, pull_request: first.pull_request });
    const second = gh.calls.slice(before).filter((c) => !c.path.startsWith("/app/"));
    expect(second.map((c) => `${c.method} ${c.path.replace(REPO, "")}`)).toEqual([
      `GET /pulls/${first.pull_request}`,
      "GET /git/ref/heads/main",
      "GET /git/commits/base0",
      "POST /git/blobs",
      "POST /git/blobs",
      "POST /git/blobs",
      "POST /git/trees",
      "POST /git/commits",
      `PATCH /git/refs/heads/submission/${first.level_id}`,
      `PATCH /pulls/${first.pull_request}`,
    ]);
    expect(second.find((c) => c.method === "PATCH" && c.path.includes("/git/refs/"))!.body.force).toBe(true);
    // The level was never published, so meta.json is part of every commit.
    expect(second.find((c) => c.path.endsWith("/git/trees"))!.body.tree).toHaveLength(3);
    expect(gh.where("POST", "/pulls")).toHaveLength(1);
    expect(await rows("SELECT level, version, sha256, player FROM submissions")).toEqual([{ level: first.level_id, version: 1, sha256: SHA_05, player: player.id }]);
  });

  it("numbers the next version after the latest approved one and leaves meta.json alone", async () => {
    const { token, player } = await signIn("sub-4", "Di");
    await seedLevel("lvl_aaaaaaaaaa", player.id, { latest: 2 });
    const gh = github();
    const response = await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh);
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ level_id: "lvl_aaaaaaaaaa", version: 3, pull_request: 1 });
    expect(gh.where("POST", "/git/trees")[0]!.body.tree.map((e: any) => e.path)).toEqual(["levels/lvl_aaaaaaaaaa/v3.json", "proof/lvl_aaaaaaaaaa/v3.demo.gz"]);
    expect(gh.where("POST", "/git/blobs")).toHaveLength(2);
  });

  it("reuses the branch of a rejected submission", async () => {
    const { token, player } = await signIn("sub-5", "Ed");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await env.DB.prepare("INSERT INTO submissions (level, version, player, pull_request, status, created) VALUES ('lvl_aaaaaaaaaa', 1, ?, 9, 'rejected', 1)").bind(player.id).run();
    const gh = github();
    gh.branches.add("refs/heads/submission/lvl_aaaaaaaaaa");
    const response = await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh);
    expect(await response.json()).toMatchObject({ version: 1, pull_request: 1 });
    expect(gh.ops()).toContain("PATCH /git/refs/heads/submission/lvl_aaaaaaaaaa");
  });

  it("refuses a fourth open submission and a sixth in a day, but still updates an open one", async () => {
    const { token, player } = await signIn("sub-6", "Flo");
    for (const [i, id] of ["lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb", "lvl_cccccccccc"].entries()) {
      await seedLevel(id, player.id);
      await seedOpen(id, 1, player.id, 10 + i);
    }
    const blocked = github();
    const fourth = await submit(token, {}, blocked);
    expect(fourth.status).toBe(429);
    expect(blocked.calls).toEqual([]);
    expect((await submit(token, { level_id: "lvl_bbbbbbbbbb" }, github())).status).toBe(200);

    await env.DB.prepare("DELETE FROM submissions").run();
    await env.DB.prepare(`INSERT OR REPLACE INTO rate (player, action, "window", count) VALUES (?, 'submit', ?, 5)`).bind(player.id, Math.floor(Date.now() / 1000 / 86400)).run();
    const sixth = github();
    expect((await submit(token, {}, sixth)).status).toBe(429);
    expect(sixth.calls).toEqual([]);
  });

  it("counts updates toward the daily limit", async () => {
    const { token, player } = await signIn("sub-7", "Gus");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 4);
    await env.DB.prepare(`INSERT INTO rate (player, action, "window", count) VALUES (?, 'submit', ?, 5)`).bind(player.id, Math.floor(Date.now() / 1000 / 86400)).run();
    expect((await submit(token, { level_id: "lvl_aaaaaaaaaa" }, github())).status).toBe(429);
  });

  it("answers 404 for an unknown level, 403 for another player's or a hidden one, 400 for a malformed id", async () => {
    const { token, player } = await signIn("sub-8", "Hal");
    const other = await signIn("sub-8b", "Ida");
    await seedLevel("lvl_aaaaaaaaaa", other.player.id);
    await seedLevel("lvl_bbbbbbbbbb", player.id, { hidden: 1 });
    await seedLevel("lvl_cccccccccc", player.id);
    await env.DB.prepare("INSERT INTO hidden_levels VALUES ('lvl_cccccccccc')").run();
    const gh = github();
    expect((await submit(token, { level_id: "lvl_zzzzzzzzzz" }, gh)).status).toBe(404);
    expect((await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh)).status).toBe(403);
    expect((await submit(token, { level_id: "lvl_bbbbbbbbbb" }, gh)).status).toBe(403);
    expect((await submit(token, { level_id: "lvl_cccccccccc" }, gh)).status).toBe(403);
    expect((await submit(token, { level_id: "../etc" }, gh)).status).toBe(400);
    expect(gh.calls).toEqual([]);
  });

  it("rejects invalid input before any GitHub call", async () => {
    const { token } = await signIn("sub-9", "Jo");
    const gh = github();
    const cases: [Fields, number, RegExp?][] = [
      [{ demo: DEMO_TELEPORT }, 400],
      [{ demo: new Uint8Array([1, 2, 3]) }, 400, /demo could not be read/],
      [{ level: new TextEncoder().encode('{"format":"nope"}') }, 400, /zero-gx-level/],
      [{ level: new TextEncoder().encode("not json") }, 400, /not valid/],
      [{ level: new Uint8Array(65537) }, 413],
      [{ demo: new Uint8Array(524289) }, 413],
    ];
    for (const [fields, status, message] of cases) {
      const response = await submit(token, fields, gh);
      expect(response.status).toBe(status);
      if (message) expect(((await response.json()) as { error: string }).error).toMatch(message);
    }
    const n = await nonce();
    const empty = new Request("https://example.com/submissions", { method: "POST", body: new FormData(), headers: { Authorization: `Bearer ${token}`, "X-Integrity": `ok:${n}`, "X-Nonce": n } });
    expect((await postSubmission(empty, testEnv, {}, gh.fetchFn).catch(failed)).status).toBe(400);
    expect(await rows("SELECT * FROM levels")).toEqual([]);
    expect(await rows("SELECT * FROM submissions")).toEqual([]);
    expect(gh.calls).toEqual([]);
  });

  it("refuses a body over 600000 bytes and a level that is already published", async () => {
    const { token, player } = await signIn("sub-10", "Kit");
    const gh = github();
    const n = await nonce();
    const big = new Request("https://example.com/submissions", { method: "POST", body: new Uint8Array(600_001), headers: { Authorization: `Bearer ${token}`, "X-Integrity": `ok:${n}`, "X-Nonce": n } });
    expect((await postSubmission(big, testEnv, {}, gh.fetchFn).catch(failed)).status).toBe(413);
    await seedLevel("lvl_aaaaaaaaaa", player.id, { latest: 1, sha: SHA_01 });
    expect((await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh)).status).toBe(409);
    expect(gh.calls).toEqual([]);
  });

  it("releases the reserved rows when GitHub fails, so the player can retry", async () => {
    const { token } = await signIn("sub-11", "Lu");
    const gh = github();
    gh.state.fail = /POST .*\/pulls$/;
    const response = await submit(token, {}, gh);
    expect(response.status).toBe(502);
    expect(await rows("SELECT * FROM levels")).toEqual([]);
    expect(await rows("SELECT * FROM submissions")).toEqual([]);
    gh.state.fail = null;
    expect((await submit(token, {}, gh)).status).toBe(201);
  });

  it("leaves one open submission and one pull request when two requests race for a level", async () => {
    const { token, player } = await signIn("sub-12", "Max");
    await seedLevel("lvl_aaaaaaaaaa", player.id, { latest: 1 });
    const gh = github();
    const both = await Promise.all([submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh), submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh)]);
    expect(both.map((r) => r.status).sort()).toSatisfy((statuses: number[]) => statuses.every((s) => [200, 201, 409].includes(s)) && statuses.includes(201));
    expect(gh.where("POST", "/pulls")).toHaveLength(1);
    expect(await rows("SELECT status FROM submissions WHERE status = 'open'")).toHaveLength(1);
  });
});

describe("GET /me/submissions", () => {
  it("lists the player's submissions, newest first", async () => {
    const { token, player } = await signIn("me-1", "Nia");
    const other = await signIn("me-2", "Ole");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedLevel("lvl_bbbbbbbbbb", other.player.id);
    await env.DB.prepare("INSERT INTO submissions (level, version, player, pull_request, status, comment, created, title) VALUES ('lvl_aaaaaaaaaa', 1, ?, 3, 'rejected', 'too easy', 1, 'Alpha')").bind(player.id).run();
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 4, "Alpha 2");
    await seedOpen("lvl_bbbbbbbbbb", 1, other.player.id, 5);
    const response = await getMySubmissions(new Request("https://example.com/me/submissions", { headers: { Authorization: `Bearer ${token}` } }), testEnv);
    expect(await response.json()).toEqual([
      { level_id: "lvl_aaaaaaaaaa", version: 1, status: "open", comment: null, pull_request: 4, title: "Alpha 2" },
      { level_id: "lvl_aaaaaaaaaa", version: 1, status: "rejected", comment: "too easy", pull_request: 3, title: "Alpha" },
    ]);
    expect((await call("/me/submissions")).status).toBe(401);
  });
});

describe("POST /github", () => {
  it("refuses a missing or wrong signature and changes nothing", async () => {
    const { player } = await signIn("hook-1", "Pat");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7);
    const gh = github();
    const payload = closed(7, true);
    expect((await hook(gh, "pull_request", payload, null)).status).toBe(401);
    expect((await hook(gh, "pull_request", payload, await sign(JSON.stringify(payload), "wrong"))).status).toBe(401);
    expect((await hook(gh, "pull_request", payload, "sha256=zz")).status).toBe(401);
    expect(gh.calls).toEqual([]);
    expect(await rows("SELECT status FROM submissions")).toEqual([{ status: "open" }]);
    expect(await rows("SELECT * FROM versions")).toEqual([]);
  });

  it("records a merge as a version and commits an index without hidden levels; a repeated delivery changes nothing", async () => {
    const { player } = await signIn("hook-2", "Quinn");
    const bo = await signIn("hook-2b", "Bo");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7, "Alpha", SHA_01);
    await seedLevel("lvl_bbbbbbbbbb", bo.player.id, { latest: 2, title: "Beta" });
    await seedLevel("lvl_cccccccccc", bo.player.id, { latest: 1, title: "Gamma" });
    await env.DB.prepare("INSERT INTO hidden_levels VALUES ('lvl_cccccccccc')").run();
    await seedLevel("lvl_dddddddddd", bo.player.id); // never approved: not listed
    const gh = github();
    gh.files.set("levels/lvl_aaaaaaaaaa/v1.json", { text: LEVEL_01_TEXT, sha: "m1" });

    const response = await hook(gh, "pull_request", closed(7, true));
    expect(response.status).toBe(200);
    expect(await rows("SELECT level, version, sha256 FROM versions WHERE level = 'lvl_aaaaaaaaaa'")).toEqual([{ level: "lvl_aaaaaaaaaa", version: 1, sha256: SHA_01 }]);
    expect((await rows<{ approved: number }>("SELECT approved FROM versions WHERE level = 'lvl_aaaaaaaaaa'"))[0]!.approved).toBeGreaterThan(0);
    expect(await rows("SELECT latest, title FROM levels WHERE id = 'lvl_aaaaaaaaaa'")).toEqual([{ latest: 1, title: "Alpha" }]);
    const [submission] = await rows<{ status: string; decided: number }>("SELECT status, decided FROM submissions");
    expect(submission).toMatchObject({ status: "approved" });
    expect(submission!.decided).toBeGreaterThan(0);

    const expected =
      JSON.stringify(
        {
          levels: [
            { id: "lvl_aaaaaaaaaa", title: "Alpha", author: "Quinn", latest: 1, versions: [{ version: 1, sha256: SHA_01 }] },
            {
              id: "lvl_bbbbbbbbbb",
              title: "Beta",
              author: "Bo",
              latest: 2,
              versions: [
                { version: 1, sha256: "lvl_bbbbbbbbbb-1".padEnd(64, "0") },
                { version: 2, sha256: "lvl_bbbbbbbbbb-2".padEnd(64, "0") },
              ],
            },
          ],
        },
        null,
        2,
      ) + "\n";
    expect(gh.files.get("index.json")!.text).toBe(expected);
    const [put] = gh.where("PUT", "/contents/index.json");
    expect(put!.body).toMatchObject({ message: "Update index", branch: "main" });

    const snapshot = async () => JSON.stringify([await rows("SELECT * FROM versions"), await rows("SELECT * FROM levels"), await rows("SELECT * FROM submissions")]);
    const state = await snapshot();
    const writes = gh.calls.filter((c) => c.method === "PUT").length;
    expect((await hook(gh, "pull_request", closed(7, true))).status).toBe(200);
    expect(await snapshot()).toBe(state);
    expect(gh.calls.filter((c) => c.method === "PUT")).toHaveLength(writes);

    // A replay must not roll the level back once a later version has been approved.
    await env.DB.prepare("UPDATE levels SET latest = 5, title = 'Later' WHERE id = 'lvl_aaaaaaaaaa'").run();
    await hook(gh, "pull_request", closed(7, true));
    expect(await rows("SELECT latest, title FROM levels WHERE id = 'lvl_aaaaaaaaaa'")).toEqual([{ latest: 5, title: "Later" }]);
  });

  it("refetches once when the index write conflicts", async () => {
    const { player } = await signIn("hook-3", "Rae");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7, "Alpha", SHA_01);
    const gh = github();
    gh.files.set("levels/lvl_aaaaaaaaaa/v1.json", { text: LEVEL_01_TEXT, sha: "m1" });
    gh.state.conflicts = 1;
    expect((await hook(gh, "pull_request", closed(7, true))).status).toBe(200);
    expect(gh.where("PUT", "/contents/index.json")).toHaveLength(2);
    expect(gh.files.get("index.json")!.text).toContain("lvl_aaaaaaaaaa");
  });

  it("records a closed pull request as rejected with the last comment, truncated", async () => {
    const { player } = await signIn("hook-4", "Sam");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedLevel("lvl_bbbbbbbbbb", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7);
    await seedOpen("lvl_bbbbbbbbbb", 1, player.id, 8);
    const gh = github();
    gh.comments.set(7, [
      { body: "first", author_association: "MEMBER" },
      { body: "x".repeat(600), author_association: "OWNER" },
      { body: "drive-by", author_association: "NONE" },
    ]);
    expect((await hook(gh, "pull_request", closed(7, false))).status).toBe(200);
    expect((await hook(gh, "pull_request", closed(8, false))).status).toBe(200);
    const [a, b] = await rows<{ status: string; comment: string | null; decided: number }>("SELECT status, comment, decided FROM submissions ORDER BY pull_request");
    expect(a).toMatchObject({ status: "rejected", comment: "x".repeat(500) });
    expect(a!.decided).toBeGreaterThan(0);
    expect(b).toMatchObject({ status: "rejected", comment: null });
    expect(await rows("SELECT * FROM versions")).toEqual([]);
    expect(gh.calls.some((c) => c.method === "PUT")).toBe(false);

    // A later comment must not rewrite a decided submission.
    gh.comments.set(7, [{ body: "changed", author_association: "OWNER" }]);
    await hook(gh, "pull_request", closed(7, false));
    expect((await rows<{ comment: string }>("SELECT comment FROM submissions WHERE pull_request = 7"))[0]!.comment).toBe("x".repeat(500));
  });

  it("hides the levels in hidden.txt and drops them from the index when a push touches it", async () => {
    const { player } = await signIn("hook-5", "Tia");
    await seedLevel("lvl_aaaaaaaaaa", player.id, { latest: 1, title: "Alpha" });
    await seedLevel("lvl_bbbbbbbbbb", player.id, { latest: 1, title: "Beta" });
    await env.DB.prepare("INSERT INTO hidden_levels VALUES ('lvl_stale00000')").run();
    await env.DB.prepare("UPDATE levels SET hidden = 1 WHERE id = 'lvl_bbbbbbbbbb'").run();
    const gh = github();
    gh.files.set("hidden.txt", { text: "lvl_aaaaaaaaaa\r\nnot an id\n\nlvl_aaaaaaaaaa\n", sha: "h1" });
    const push = (touched: string[]) => ({ ref: "refs/heads/main", repository, commits: [{ added: [], modified: touched, removed: [] }] });

    expect((await hook(gh, "push", push(["README.md"]))).status).toBe(204);
    expect((await hook(gh, "push", { ...push(["hidden.txt"]), ref: "refs/heads/other" })).status).toBe(204);
    expect(gh.calls).toEqual([]);

    expect((await hook(gh, "push", push(["hidden.txt"]))).status).toBe(200);
    expect(await rows("SELECT level FROM hidden_levels")).toEqual([{ level: "lvl_aaaaaaaaaa" }]);
    expect(await rows("SELECT id, hidden FROM levels ORDER BY id")).toEqual([
      { id: "lvl_aaaaaaaaaa", hidden: 1 },
      { id: "lvl_bbbbbbbbbb", hidden: 0 },
    ]);
    expect(JSON.parse(gh.files.get("index.json")!.text).levels.map((l: { id: string }) => l.id)).toEqual(["lvl_bbbbbbbbbb"]);
  });

  it("answers ping with 200 and ignores other events, other repositories and unknown pull requests", async () => {
    const gh = github();
    expect((await hook(gh, "ping", { zen: "hi" })).status).toBe(200);
    expect((await hook(gh, "issues", { action: "opened", repository })).status).toBe(204);
    expect((await hook(gh, "pull_request", { ...closed(7, true), repository: { full_name: "someone/else" } })).status).toBe(204);
    expect((await hook(gh, "pull_request", closed(99, true))).status).toBe(204);
    expect((await hook(gh, "pull_request", { ...closed(7, true), action: "opened" })).status).toBe(204);
    expect(gh.calls).toEqual([]);
  });
});

describe("recovering from partial failures", () => {
  const merged = (number: number, head?: string, headRepo = repository.full_name) => ({ action: "closed", repository, pull_request: { number, merged: true, head: head ? { ref: head, repo: { full_name: headRepo } } : undefined } });
  const levelFile = (gh: Github, level: string, version: number, text = LEVEL_01_TEXT) => gh.files.set(`levels/${level}/v${version}.json`, { text, sha: `main-${level}-${version}` });
  /** Inserts an open submission whose pull request was never recorded, created `age` seconds ago. */
  const seedUnrecorded = (level: string, player: string, age: number) =>
    env.DB.prepare("INSERT INTO submissions (level, version, player, status, created) VALUES (?, 1, ?, 'open', ?)").bind(level, player, Math.floor(Date.now() / 1000) - age).run();

  it("keeps the row when recording the pull request fails, and the webhook links it by branch", async () => {
    const { token } = await signIn("fix-1", "Una");
    const gh = github();
    const flaky = {
      ...testEnv,
      DB: new Proxy(env.DB, {
        get(target, prop) {
          if (prop !== "prepare") return Reflect.get(target, prop, target).bind(target);
          return (sql: string) => {
            if (sql.startsWith("UPDATE submissions SET pull_request")) throw new Error("D1 is down");
            return target.prepare(sql);
          };
        },
      }) as unknown as D1Database,
    };
    const response = await submit(token, {}, gh, flaky);
    expect(response.status).toBe(502);
    expect(gh.where("POST", "/pulls")).toHaveLength(1);
    const [row] = await rows<{ level: string; pull_request: number | null }>("SELECT level, pull_request FROM submissions");
    expect(row!.pull_request).toBeNull();
    expect(await rows("SELECT id FROM levels")).toEqual([{ id: row!.level }]);

    levelFile(gh, row!.level, 1);
    expect((await hook(gh, "pull_request", merged(1, `submission/${row!.level}`))).status).toBe(200);
    expect(await rows("SELECT status, pull_request, branch FROM submissions")).toEqual([{ status: "approved", pull_request: 1, branch: `submission/${row!.level}` }]);
    expect(await rows("SELECT latest FROM levels")).toEqual([{ latest: 1 }]);
  });

  it("ignores a pull request from a fork whose branch has a submission's name", async () => {
    const { player } = await signIn("fix-fork", "Fay");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedUnrecorded("lvl_aaaaaaaaaa", player.id, 10);
    const gh = github();
    expect((await hook(gh, "pull_request", merged(5, "submission/lvl_aaaaaaaaaa", "mallory/zero-gx-levels"))).status).toBe(204);
    expect(await rows("SELECT status, pull_request FROM submissions")).toEqual([{ status: "open", pull_request: null }]);
    expect(gh.calls).toEqual([]);
  });

  it("takes over a submission whose pull request was never recorded once it is stale, and refuses while it is fresh", async () => {
    const { token, player } = await signIn("fix-2", "Val");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedUnrecorded("lvl_aaaaaaaaaa", player.id, 10);
    const fresh = github();
    expect((await submit(token, { level_id: "lvl_aaaaaaaaaa" }, fresh)).status).toBe(409);
    expect(fresh.calls).toEqual([]);

    await env.DB.prepare("UPDATE submissions SET created = 1").run();
    const gh = github();
    gh.branches.add("refs/heads/submission/lvl_aaaaaaaaaa");
    const response = await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh);
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ level_id: "lvl_aaaaaaaaaa", version: 1, pull_request: 1 });
    expect(await rows("SELECT level, status, pull_request, branch FROM submissions")).toEqual([{ level: "lvl_aaaaaaaaaa", status: "open", pull_request: 1, branch: "submission/lvl_aaaaaaaaaa" }]);
  });

  it("finds the pull request that already exists when a takeover cannot create one", async () => {
    const { token, player } = await signIn("fix-3", "Wes");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedUnrecorded("lvl_aaaaaaaaaa", player.id, 3600);
    const gh = github();
    gh.state.existingPull = 42;
    const response = await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh);
    expect(await response.json()).toMatchObject({ pull_request: 42 });
    expect(gh.ops()).toContain("GET /pulls?head=BRAITG:submission/lvl_aaaaaaaaaa&state=open");
    expect(await rows("SELECT pull_request FROM submissions")).toEqual([{ pull_request: 42 }]);
  });

  it("does not count stale unrecorded submissions toward the open limit, but counts fresh ones", async () => {
    const { token, player } = await signIn("fix-4", "Xia");
    for (const id of ["lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb", "lvl_cccccccccc"]) {
      await seedLevel(id, player.id);
      await seedUnrecorded(id, player.id, 3600);
    }
    expect((await submit(token, {}, github())).status).toBe(201);
    await env.DB.prepare("UPDATE submissions SET created = ? WHERE level = 'lvl_aaaaaaaaaa'").bind(Math.floor(Date.now() / 1000)).run();
    await env.DB.prepare("UPDATE submissions SET created = ? WHERE level = 'lvl_bbbbbbbbbb'").bind(Math.floor(Date.now() / 1000)).run();
    // Two fresh unrecorded plus the new one above is the limit.
    expect((await submit(token, { level: LEVEL_05, demo: bytes(env.DEMO_LEVEL_05) }, github())).status).toBe(429);
  });

  it("refuses to update a pull request that GitHub has closed or merged", async () => {
    const { token, player } = await signIn("fix-5", "Yan");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 4);
    for (const state of ["closed", "merged"]) {
      const gh = github();
      gh.state.pullState = state;
      const response = await submit(token, { level_id: "lvl_aaaaaaaaaa" }, gh);
      expect(response.status).toBe(409);
      expect(gh.ops()).toEqual(["GET /pulls/4"]);
    }
  });

  it("refuses a level whose bytes another open submission already carries", async () => {
    const { token, player } = await signIn("fix-6", "Zed");
    const other = await signIn("fix-6b", "Abe");
    await seedLevel("lvl_aaaaaaaaaa", other.player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, other.player.id, 5, "Theirs", SHA_01);
    const gh = github();
    expect((await submit(token, {}, gh)).status).toBe(409);
    expect(gh.calls).toEqual([]);
    expect(await rows("SELECT * FROM levels WHERE owner = ?", player.id)).toEqual([]);
    // The owner may resubmit the same bytes to their own open submission.
    const own = await signIn("fix-6c", "Bea");
    await seedLevel("lvl_bbbbbbbbbb", own.player.id);
    await seedOpen("lvl_bbbbbbbbbb", 1, own.player.id, 6, "Mine", "e".repeat(64));
    await env.DB.prepare("UPDATE submissions SET status = 'rejected' WHERE level = 'lvl_aaaaaaaaaa'").run();
    expect((await submit(own.token, { level_id: "lvl_bbbbbbbbbb" }, github())).status).toBe(200);
  });

  it("takes the last open slot for only one of two concurrent submissions", async () => {
    const { token, player } = await signIn("fix-7", "Cai");
    for (const [i, id] of ["lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb"].entries()) {
      await seedLevel(id, player.id);
      await seedOpen(id, 1, player.id, 10 + i, "Seeded", `${i}`.repeat(64));
    }
    const gh = github();
    const both = await Promise.all([submit(token, {}, gh), submit(token, { level: LEVEL_05, demo: bytes(env.DEMO_LEVEL_05) }, gh)]);
    expect(both.map((r) => r.status).sort()).toEqual([201, 429]);
    expect(await rows("SELECT id FROM levels")).toHaveLength(3);
    expect(await rows("SELECT id FROM submissions WHERE status = 'open'")).toHaveLength(3);
  });

  it("records the hash of the merged file, not the uploaded one", async () => {
    const { player } = await signIn("fix-8", "Dee");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7, "Alpha", "f".repeat(64));
    const gh = github();
    levelFile(gh, "lvl_aaaaaaaaaa", 1, LEVEL_05_TEXT);
    expect((await hook(gh, "pull_request", merged(7))).status).toBe(200);
    expect(await rows("SELECT sha256 FROM versions")).toEqual([{ sha256: SHA_05 }]);
    expect(await rows("SELECT sha256, status FROM submissions")).toEqual([{ sha256: SHA_05, status: "approved" }]);
    expect(JSON.parse(gh.files.get("index.json")!.text).levels[0].versions).toEqual([{ version: 1, sha256: SHA_05 }]);
  });

  it("fails loudly and leaves the submission open when the merged file's hash is already published", async () => {
    const { player } = await signIn("fix-9", "Eli");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedLevel("lvl_bbbbbbbbbb", player.id, { latest: 1, sha: SHA_05 });
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7, "Alpha");
    const gh = github();
    levelFile(gh, "lvl_aaaaaaaaaa", 1, LEVEL_05_TEXT);
    expect((await hook(gh, "pull_request", merged(7))).status).toBe(500);
    expect(await rows("SELECT status FROM submissions")).toEqual([{ status: "open" }]);
    expect(await rows("SELECT latest FROM levels WHERE id = 'lvl_aaaaaaaaaa'")).toEqual([{ latest: 0 }]);
    expect(gh.calls.some((c) => c.method === "PUT")).toBe(false);
  });

  it("keeps both levels in the index when two merges race", async () => {
    const { player } = await signIn("fix-10", "Fay");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedLevel("lvl_bbbbbbbbbb", player.id);
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 7, "Alpha");
    await seedOpen("lvl_bbbbbbbbbb", 1, player.id, 8, "Beta");
    const gh = github();
    levelFile(gh, "lvl_aaaaaaaaaa", 1, LEVEL_01_TEXT);
    levelFile(gh, "lvl_bbbbbbbbbb", 1, LEVEL_05_TEXT);
    gh.files.set("index.json", { text: '{"levels": []}\n', sha: "i0" });
    // The second merge lands completely between the first one's read of the index and its write.
    gh.state.onPut = async () => {
      expect((await hook(gh, "pull_request", merged(8))).status).toBe(200);
    };
    expect((await hook(gh, "pull_request", merged(7))).status).toBe(200);
    expect(JSON.parse(gh.files.get("index.json")!.text).levels.map((l: { id: string }) => l.id)).toEqual(["lvl_aaaaaaaaaa", "lvl_bbbbbbbbbb"]);
  });

  it("approves a merged pull request that was closed first, and puts a reopened one back under review", async () => {
    const { player } = await signIn("fix-11", "Gil");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await seedLevel("lvl_bbbbbbbbbb", player.id);
    for (const [id, pr] of [["lvl_aaaaaaaaaa", 7], ["lvl_bbbbbbbbbb", 8]] as const) {
      await env.DB.prepare("INSERT INTO submissions (level, version, player, pull_request, status, comment, created, decided, title, sha256) VALUES (?, 1, ?, ?, 'rejected', 'no', 1, 2, 'T', ?)").bind(id, player.id, pr, "f".repeat(64)).run();
    }
    const gh = github();
    levelFile(gh, "lvl_aaaaaaaaaa", 1);
    levelFile(gh, "lvl_bbbbbbbbbb", 1, LEVEL_05_TEXT);
    const reopened = (number: number) => ({ action: "reopened", repository, pull_request: { number, merged: false } });

    expect((await hook(gh, "pull_request", reopened(7))).status).toBe(200);
    expect(await rows("SELECT status, comment, decided FROM submissions WHERE pull_request = 7")).toEqual([{ status: "open", comment: null, decided: null }]);
    expect((await hook(gh, "pull_request", merged(7))).status).toBe(200);
    expect((await hook(gh, "pull_request", merged(8))).status).toBe(200);
    expect(await rows("SELECT pull_request, status, comment FROM submissions ORDER BY pull_request")).toEqual([
      { pull_request: 7, status: "approved", comment: null },
      { pull_request: 8, status: "approved", comment: null },
    ]);
    expect(await rows("SELECT latest FROM levels ORDER BY id")).toEqual([{ latest: 1 }, { latest: 1 }]);
  });

  it("does not reopen a rejected submission when the level has a newer open one", async () => {
    const { player } = await signIn("fix-12", "Hui");
    await seedLevel("lvl_aaaaaaaaaa", player.id);
    await env.DB.prepare("INSERT INTO submissions (level, version, player, pull_request, status, created) VALUES ('lvl_aaaaaaaaaa', 1, ?, 7, 'rejected', 1)").bind(player.id).run();
    await seedOpen("lvl_aaaaaaaaaa", 1, player.id, 9);
    const gh = github();
    expect((await hook(gh, "pull_request", { action: "reopened", repository, pull_request: { number: 7, merged: false } })).status).toBe(200);
    expect(await rows("SELECT pull_request, status FROM submissions ORDER BY pull_request")).toEqual([
      { pull_request: 7, status: "rejected" },
      { pull_request: 9, status: "open" },
    ]);
  });
});
