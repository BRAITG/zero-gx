import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { Env } from "../../src/env";
import { boundNonce, requireIntegrity, requirePlayer, signSession } from "../../src/session";
import { GoogleVerifier, TestVerifier } from "../../src/verify";
import worker from "../../src/worker";

const testEnv: Env = { ...env, ALLOW_TEST_VERIFIER: "1" };

const call = (path: string, init?: RequestInit, e: Env = testEnv) =>
  worker.fetch(new Request(`https://example.com${path}`, init), e);

const post = (path: string, body: unknown, e: Env = testEnv) =>
  call(path, { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) }, e);

const nonce = async (e: Env = testEnv): Promise<string> =>
  ((await (await call("/nonce", undefined, e)).json()) as { nonce: string }).nonce;

async function signIn(id: string, name: string, e: Env = testEnv) {
  const n = await nonce(e);
  return post("/session", { authCode: `test:${id}:${name}`, integrityToken: `ok:${n}`, nonce: n }, e);
}

const bearer = (token: string) => new Request("https://example.com/x", { headers: { Authorization: `Bearer ${token}` } });
const now = () => Math.floor(Date.now() / 1000);

describe("nonce", () => {
  it("issues a 32-byte base64url nonce that expires in five minutes", async () => {
    const response = await call("/nonce");
    expect(response.status).toBe(200);
    const n = ((await response.json()) as { nonce: string }).nonce;
    expect(n).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const row = await env.DB.prepare("SELECT expires FROM nonces WHERE nonce = ?").bind(n).first<{ expires: number }>();
    expect(Math.abs(row!.expires - (now() + 300))).toBeLessThan(5);
  });

  it("purges expired nonces when a new one is issued", async () => {
    await env.DB.prepare("INSERT INTO nonces VALUES ('stale', ?)").bind(now() - 1).run();
    await nonce();
    expect(await env.DB.prepare("SELECT 1 FROM nonces WHERE nonce = 'stale'").first()).toBeNull();
  });
});

describe("auth rate limit", () => {
  const limited: Env = { ...testEnv, AUTH_LIMITER: { limit: async () => ({ success: false }) } };

  it("answers 429 on /nonce and /session when the limiter refuses", async () => {
    expect((await call("/nonce", undefined, limited)).status).toBe(429);
    expect((await post("/session", { authCode: "test:g-1:Ada", integrityToken: "ok:x", nonce: "x" }, limited)).status).toBe(429);
  });

  it("keys the limiter by client IP", async () => {
    const keys: string[] = [];
    const spy: Env = { ...testEnv, AUTH_LIMITER: { limit: async ({ key }) => (keys.push(key), { success: true }) } };
    await call("/nonce", { headers: { "cf-connecting-ip": "203.0.113.7" } }, spy);
    await call("/nonce", undefined, spy);
    expect(keys).toEqual(["203.0.113.7", "unknown"]);
  });
});

describe("POST /session", () => {
  it("signs a player in and returns a session token that requirePlayer accepts", async () => {
    const response = await signIn("g-100", "Ada");
    expect(response.status).toBe(200);
    const body = (await response.json()) as { token: string; player: { id: string; name: string } };
    expect(body.player.id).toMatch(/^p_[a-z0-9]{16}$/);
    expect(body.player.name).toBe("Ada");
    const account = await env.DB.prepare("SELECT player FROM accounts WHERE provider = 'play_games' AND provider_id = 'g-100'").first<{ player: string }>();
    expect(account!.player).toBe(body.player.id);
    const player = await requirePlayer(bearer(body.token), testEnv);
    expect(player).toMatchObject({ id: body.player.id, name: "Ada", banned: 0 });
  });

  it("keeps the player id and updates the display name on a later sign-in", async () => {
    const first = (await (await signIn("g-101", "Old")).json()) as { player: { id: string } };
    const second = (await (await signIn("g-101", "New")).json()) as { player: { id: string; name: string } };
    expect(second.player).toEqual({ id: first.player.id, name: "New" });
  });

  it("rejects a reused nonce with 401", async () => {
    const n = await nonce();
    const body = { authCode: "test:g-102:A", integrityToken: `ok:${n}`, nonce: n };
    expect((await post("/session", body)).status).toBe(200);
    expect((await post("/session", body)).status).toBe(401);
  });

  it("rejects an unknown or expired nonce with 401", async () => {
    const unknown = { authCode: "test:g-103:A", integrityToken: "ok:nope", nonce: "nope" };
    expect((await post("/session", unknown)).status).toBe(401);
    await env.DB.prepare("INSERT INTO nonces VALUES ('old', ?)").bind(now() - 1).run();
    const expired = { authCode: "test:g-103:A", integrityToken: "ok:old", nonce: "old" };
    expect((await post("/session", expired)).status).toBe(401);
  });

  it("rejects an integrity token for another nonce with 403", async () => {
    const n = await nonce();
    const response = await post("/session", { authCode: "test:g-104:A", integrityToken: "ok:other", nonce: n });
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: expect.any(String) });
  });

  it("rejects a bad auth code with 401", async () => {
    const n = await nonce();
    const response = await post("/session", { authCode: "garbage", integrityToken: `ok:${n}`, nonce: n });
    expect(response.status).toBe(401);
  });

  it("rejects a banned player with 403, and their old session too", async () => {
    const { token, player } = (await (await signIn("g-105", "Eve")).json()) as { token: string; player: { id: string } };
    await env.DB.prepare("UPDATE players SET banned = 1 WHERE id = ?").bind(player.id).run();
    expect((await signIn("g-105", "Eve")).status).toBe(403);
    await expect(requirePlayer(bearer(token), testEnv)).rejects.toMatchObject({ status: 403 });
  });

  it("refuses the test verifier unless ALLOW_TEST_VERIFIER is \"1\"", async () => {
    for (const flag of ["0", undefined]) {
      const e = { ...testEnv, ALLOW_TEST_VERIFIER: flag } as Env;
      const response = await signIn("g-106", "Mallory", e);
      expect(response.status).toBe(403);
    }
    expect(await env.DB.prepare("SELECT 1 FROM accounts WHERE provider_id = 'g-106'").first()).toBeNull();
  });

  it("rejects a body over 4 KB with 413, bad JSON and missing fields with 400", async () => {
    expect((await post("/session", "x".repeat(4097))).status).toBe(413);
    expect((await post("/session", "{nope")).status).toBe(400);
    expect((await post("/session", { authCode: "a" })).status).toBe(400);
  });
});

describe("requirePlayer", () => {
  const sign = (e: Env, exp?: number) => signSession(e, "p_unknownplayer000", exp);

  it("rejects a missing header, a malformed token, and a token signed with another key with 401", async () => {
    const { token } = (await (await signIn("g-107", "Zed")).json()) as { token: string };
    const other = await signSession({ ...testEnv, SESSION_KEY: "another-key" }, "p_whoever", now() + 3600);
    const [payload] = token.split(".");
    for (const request of [new Request("https://example.com/x"), bearer("garbage"), bearer(other), bearer(`${payload}.AAAA`)]) {
      await expect(requirePlayer(request, testEnv)).rejects.toMatchObject({ status: 401 });
    }
  });

  it("rejects an expired token and a token for an unknown player with 401", async () => {
    await expect(requirePlayer(bearer(await sign(testEnv, now() - 1)), testEnv)).rejects.toMatchObject({ status: 401 });
    await expect(requirePlayer(bearer(await sign(testEnv, now() + 3600)), testEnv)).rejects.toMatchObject({ status: 401 });
  });

  it("issues tokens valid for 7 days", async () => {
    const { token } = (await (await signIn("g-108", "Kim")).json()) as { token: string };
    const payload = JSON.parse(atob(token.split(".")[0]!.replace(/-/g, "+").replace(/_/g, "/"))) as { exp: number };
    expect(Math.abs(payload.exp - (now() + 7 * 86400))).toBeLessThan(5);
  });
});

describe("DELETE /me", () => {
  const remaining = (id: string) =>
    env.DB.prepare(
      `SELECT (SELECT COUNT(*) FROM players WHERE id = ?1) + (SELECT COUNT(*) FROM accounts WHERE player = ?1)
        + (SELECT COUNT(*) FROM scores WHERE player = ?1) + (SELECT COUNT(*) FROM likes WHERE player = ?1)
        + (SELECT COUNT(*) FROM reports WHERE player = ?1) + (SELECT COUNT(*) FROM rate WHERE player = ?1)
        + (SELECT COUNT(*) FROM player_ranking WHERE player = ?1) AS n`,
    )
      .bind(id)
      .first<{ n: number }>();

  it("erases a banned player's data, ends their session, keeps their level as a deleted author's, and lets them start over", async () => {
    const { token, player } = (await (await signIn("g-120", "Gone")).json()) as { token: string; player: { id: string } };
    const other = (await (await signIn("g-121", "Stays")).json()) as { token: string; player: { id: string } };
    const sha = "a".repeat(64);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO levels (id, owner, latest, created, title) VALUES ('lvl_del0000001', ?, 1, 0, 'Mine')").bind(player.id),
      env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES ('lvl_del0000001', 1, ?, 1)").bind(sha),
      ...[player.id, other.player.id].map((id) =>
        env.DB.prepare("INSERT INTO scores VALUES (?, ?, 1000, 1, 1, 1, ?, 0)").bind(sha, id, `demos/${sha}/${id}/x.demo.gz`),
      ),
      env.DB.prepare("INSERT INTO likes VALUES (?, 'lvl_del0000001')").bind(player.id),
      env.DB.prepare("INSERT INTO reports VALUES (?, 'lvl_del0000001')").bind(player.id),
      env.DB.prepare("INSERT INTO rate VALUES (?, 'score', 0, 1)").bind(player.id),
      env.DB.prepare("INSERT INTO player_ranking VALUES (?, 1000, 1, 0)").bind(player.id),
      env.DB.prepare("UPDATE players SET banned = 1 WHERE id = ?").bind(player.id),
    ]);

    const response = await call("/me", { method: "DELETE", headers: { Authorization: `Bearer ${token}` } });
    expect(response.status).toBe(204);
    expect((await remaining(player.id))!.n).toBe(0);
    expect((await remaining(other.player.id))!.n).toBeGreaterThan(0);
    await expect(requirePlayer(bearer(token), testEnv)).rejects.toMatchObject({ status: 401 });

    const levels = await call("/levels?sort=new", { headers: { Authorization: `Bearer ${other.token}` } });
    const items = (await levels.json()) as { level_id: string; author: string }[];
    expect(items.find((l) => l.level_id === "lvl_del0000001")?.author).toBe("Deleted player");

    const again = (await (await signIn("g-120", "Back")).json()) as { player: { id: string } };
    expect(again.player.id).not.toBe(player.id);
  });

  it("rejects a request without a valid session with 401", async () => {
    expect((await call("/me", { method: "DELETE" })).status).toBe(401);
  });
});

describe("requireIntegrity", () => {
  const withHeaders = (token: string, n: string) => new Request("https://example.com/x", { headers: { "X-Integrity": token, "X-Nonce": n } });

  const body = new TextEncoder().encode("payload");
  const check = (request: Request, level: "device" | "strong" = "device", parts = [body]) => requireIntegrity(request, testEnv, parts, level, new TestVerifier());

  it("consumes the nonce and accepts a token bound to the nonce and the payload", async () => {
    const n = await nonce();
    const bound = await boundNonce(n, [body]);
    await expect(check(withHeaders(`ok:${bound}`, n))).resolves.toBeUndefined();
    await expect(check(withHeaders(`ok:${bound}`, n))).rejects.toMatchObject({ status: 403 });
  });

  it("rejects missing headers and a token for another nonce with 403", async () => {
    const n = await nonce();
    await expect(check(new Request("https://example.com/x"))).rejects.toMatchObject({ status: 403 });
    await expect(check(withHeaders("ok:other", n))).rejects.toMatchObject({ status: 403 });
  });

  it("rejects a token signed for other payload bytes", async () => {
    const n = await nonce();
    const forOther = await boundNonce(n, [new TextEncoder().encode("other payload")]);
    await expect(check(withHeaders(`ok:${forOther}`, n))).rejects.toMatchObject({ status: 403 });
  });

  it("rejects the unbound server nonce", async () => {
    const n = await nonce();
    await expect(check(withHeaders(`ok:${n}`, n))).rejects.toMatchObject({ status: 403 });
  });

  it("requires a strong verdict when asked", async () => {
    const n = await nonce();
    const bound = await boundNonce(n, [body]);
    await expect(check(withHeaders(`ok:${bound}`, n), "strong")).rejects.toMatchObject({ status: 403 });
    const m = await nonce();
    await expect(check(withHeaders(`strong:${await boundNonce(m, [body])}`, m), "strong")).resolves.toBeUndefined();
  });

  it("binds every part in order", async () => {
    const a = new TextEncoder().encode("a");
    const b = new TextEncoder().encode("b");
    expect(await boundNonce("n", [a, b])).not.toBe(await boundNonce("n", [b, a]));
    expect(await boundNonce("n", [a, b])).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});

describe("GoogleVerifier", () => {
  const PACKAGE = "dev.braitg.zerogx";
  let privateKeyPem: string;

  async function serviceAccount(): Promise<string> {
    if (!privateKeyPem) {
      const pair = await crypto.subtle.generateKey(
        { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
        true,
        ["sign", "verify"],
      );
      const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
      privateKeyPem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der)).replace(/.{64}/g, "$&\n")}\n-----END PRIVATE KEY-----\n`;
    }
    return JSON.stringify({ client_email: "bot@example.iam.gserviceaccount.com", private_key: privateKeyPem });
  }

  const verdict = (patch: Record<string, unknown> = {}) => ({
    tokenPayloadExternal: {
      requestDetails: { requestPackageName: PACKAGE, nonce: "n1", timestampMillis: String(Date.now()) },
      appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED" },
      deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY", "MEETS_DEVICE_INTEGRITY"] },
      ...patch,
    },
  });

  // Routes each Google endpoint to a canned response and records the calls.
  function fakeGoogle(decoded: unknown) {
    const calls: { url: string; init?: RequestInit }[] = [];
    const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      calls.push({ url, init });
      if (url === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "tok" });
      if (url === "https://games.googleapis.com/games/v1/players/me") return Response.json({ playerId: "g-1", displayName: "Ada" });
      if (url === `https://playintegrity.googleapis.com/v1/${PACKAGE}:decodeIntegrityToken`) return Response.json(decoded);
      return new Response("unexpected", { status: 500 });
    }) as typeof fetch;
    return { fetchFn, calls };
  }

  const verifier = async (decoded: unknown) => {
    const google = fakeGoogle(decoded);
    const v = new GoogleVerifier(
      { GOOGLE_CLIENT_ID: "cid", GOOGLE_CLIENT_SECRET: "secret", PLAY_SERVICE_ACCOUNT: await serviceAccount() },
      google.fetchFn,
    );
    return { v, ...google };
  };

  it("exchanges the auth code and reads the Play Games player", async () => {
    const { v, calls } = await verifier(verdict());
    await expect(v.player("code-1")).resolves.toEqual({ providerId: "g-1", name: "Ada" });
    const form = new URLSearchParams(String(calls[0]!.init!.body));
    expect(Object.fromEntries(form)).toEqual({
      grant_type: "authorization_code",
      code: "code-1",
      client_id: "cid",
      client_secret: "secret",
      redirect_uri: "",
    });
    expect((calls[1]!.init!.headers as Record<string, string>).Authorization).toBe("Bearer tok");
  });

  it("rejects a failed code exchange", async () => {
    const v = new GoogleVerifier({ GOOGLE_CLIENT_ID: "c", GOOGLE_CLIENT_SECRET: "s", PLAY_SERVICE_ACCOUNT: "{}" }, async () =>
      Response.json({ error: "invalid_grant" }, { status: 400 }),
    );
    await expect(v.player("bad")).rejects.toThrow();
  });

  it("accepts a good integrity verdict and sends a service-account assertion", async () => {
    const { v, calls } = await verifier(verdict());
    await expect(v.integrity("itok", "n1", "device")).resolves.toBeUndefined();
    const form = new URLSearchParams(String(calls[0]!.init!.body));
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    const [header, claims] = form.get("assertion")!.split(".").slice(0, 2).map((part) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/"))));
    expect(header).toEqual({ alg: "RS256", typ: "JWT" });
    expect(claims).toMatchObject({
      iss: "bot@example.iam.gserviceaccount.com",
      scope: "https://www.googleapis.com/auth/playintegrity",
      aud: "https://oauth2.googleapis.com/token",
    });
    expect(JSON.parse(String(calls[1]!.init!.body))).toEqual({ integrity_token: "itok" });
  });

  const bad: [string, Record<string, unknown>][] = [
    ["another package", { requestDetails: { requestPackageName: "com.evil", nonce: "n1", timestampMillis: String(Date.now()) } }],
    ["another nonce", { requestDetails: { requestPackageName: PACKAGE, nonce: "n2", timestampMillis: String(Date.now()) } }],
    ["a stale token", { requestDetails: { requestPackageName: PACKAGE, nonce: "n1", timestampMillis: String(Date.now() - 6 * 60_000) } }],
    ["an unrecognized app", { appIntegrity: { appRecognitionVerdict: "UNRECOGNIZED_VERSION" } }],
    ["a device failing basic integrity", { deviceIntegrity: { deviceRecognitionVerdict: [] } }],
    ["a device with only basic integrity", { deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY"] } }],
    ["a missing device verdict", { deviceIntegrity: {} }],
  ];
  it.each(bad)("rejects %s", async (_name, patch) => {
    const { v } = await verifier(verdict(patch));
    await expect(v.integrity("itok", "n1", "device")).rejects.toThrow();
  });

  it("requires MEETS_STRONG_INTEGRITY for the strong level", async () => {
    const { v } = await verifier(verdict());
    await expect(v.integrity("itok", "n1", "strong")).rejects.toThrow();
    const strong = await verifier(verdict({ deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY", "MEETS_DEVICE_INTEGRITY", "MEETS_STRONG_INTEGRITY"] } }));
    await expect(strong.v.integrity("itok", "n1", "strong")).resolves.toBeUndefined();
  });

  it("rejects a response without a payload", async () => {
    const { v } = await verifier({});
    await expect(v.integrity("itok", "n1", "device")).rejects.toThrow();
  });
});
