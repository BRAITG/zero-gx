import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { runCron } from "../../src/community";
import type { Env } from "../../src/env";
import { playEligibility } from "../../src/plays";
import { boundNonce, signSession } from "../../src/session";
import worker from "../../src/worker";

const testEnv: Env = { ...env, ALLOW_TEST_VERIFIER: "1" };
const offlineGithub = (async () => Response.json({}, { status: 500 })) as typeof fetch;

const ALICE = "p_alice";
const BOB = "p_bob";
const CAROL = "p_carol";
const LEVEL = "lvl_aaaaaaaaaa";
const HIDDEN_LEVEL = "lvl_bbbbbbbbbb";
const LISTED_LEVEL = "lvl_cccccccccc";

/** A version hash: 64 lowercase hex characters. */
const sha = (n: number) => n.toString(16).padStart(64, "0");
/** An attempt id: 32 lowercase hex characters. */
const attemptId = (n: number) => n.toString(16).padStart(32, "0");

const V1 = sha(1);
const V2 = sha(2);
const HIDDEN = sha(3);
const LISTED = sha(4);
const UNKNOWN = sha(5);
const [A, B, C, D] = [1, 2, 3, 4].map(attemptId);

interface Snapshot {
  id: string;
  sha256: string;
  started_ms: number;
  revision: number;
  outcome: string | null;
  ended_ms: number | null;
}

const start = (id: string, sha256: string, started_ms: number): Snapshot => ({ id, sha256, started_ms, revision: 1, outcome: null, ended_ms: null });
const finish = (id: string, sha256: string, started_ms: number, outcome: string, ended_ms: number): Snapshot => ({ id, sha256, started_ms, revision: 2, outcome, ended_ms });

interface Reply {
  acknowledged: { id: string; revision: number }[];
  discarded: { id: string; revision: number; reason: string }[];
  cleared: string[];
}

interface Eligibility {
  attempts: number;
  cleared: boolean;
  eligible: boolean;
}

const json = (value: unknown) => new TextEncoder().encode(JSON.stringify(value));
const wire = (attempts: unknown[], player_id: unknown = ALICE) => json({ player_id, attempts });

/** The JSON of `value` followed by spaces, exactly `size` bytes long. */
function padded(value: unknown, size: number): Uint8Array<ArrayBuffer> {
  const text = JSON.stringify(value);
  if (text.length > size) throw new Error(`the JSON is ${text.length} bytes, more than ${size}`);
  return new TextEncoder().encode(text + " ".repeat(size - text.length));
}

const rows = async <T>(sql: string, ...values: unknown[]) => (await env.DB.prepare(sql).bind(...values).all<T>()).results;

async function nonce(): Promise<string> {
  const response = await worker.fetch(new Request("https://example.com/nonce"), testEnv);
  return (await response.json<{ nonce: string }>()).nonce;
}

/** A POST /plays for `as` carrying `bytes`; the integrity token binds nonce `n` to `signed`, which differs from `bytes` only to test tampering. */
async function playsRequest(as: string, bytes: Uint8Array<ArrayBuffer>, signed: Uint8Array<ArrayBuffer>, n: string): Promise<Request> {
  return new Request("https://example.com/plays", {
    method: "POST",
    body: bytes,
    headers: {
      Authorization: `Bearer ${await signSession(testEnv, as)}`,
      "Content-Type": "application/json",
      "X-Integrity": `ok:${await boundNonce(n, [signed])}`,
      "X-Nonce": n,
    },
  });
}

/** Sends raw `bytes` as `as` with a fresh nonce. */
async function sendRaw(as: string, bytes: Uint8Array<ArrayBuffer>, signed = bytes): Promise<Response> {
  return worker.fetch(await playsRequest(as, bytes, signed, await nonce()), testEnv);
}

/** `player` reports `attempts`, naming `claimed` as its owner. */
const plays = (player: string, attempts: Snapshot[], claimed = player) => sendRaw(player, json({ player_id: claimed, attempts }));

/** A report the server must accept in full. */
async function report(player: string, attempts: Snapshot[]): Promise<Reply> {
  const response = await plays(player, attempts);
  expect(response.status).toBe(200);
  return response.json<Reply>();
}

/** The start of an attempt, reported on its own as the app does. */
const begin = (player: string, id: string, sha256: string, started_ms: number) => report(player, [start(id, sha256, started_ms)]);
/** The result of an attempt, reported after its start. */
const conclude = (player: string, id: string, sha256: string, started_ms: number, outcome: string, ended_ms: number) =>
  report(player, [finish(id, sha256, started_ms, outcome, ended_ms)]);
/** A whole attempt, reported the way the app does: its start, then its result. */
async function attempt(player: string, id: string, sha256: string, started_ms: number, outcome: string, ended_ms: number): Promise<void> {
  await begin(player, id, sha256, started_ms);
  await conclude(player, id, sha256, started_ms, outcome, ended_ms);
}

const summaryOf = async (player: string, sha256: string) =>
  (await rows<{ attempts: number; first_clear_ms: number | null }>("SELECT attempts, first_clear_ms FROM play_summaries WHERE player = ? AND sha256 = ?", player, sha256))[0];

const attemptOf = async (player: string, id: string) =>
  (
    await rows<{ sha256: string; started_ms: number; revision: number; outcome: string | null; ended_ms: number | null; received_ms: number }>(
      "SELECT sha256, started_ms, revision, outcome, ended_ms, received_ms FROM play_attempts WHERE player = ? AND id = ?",
      player,
      id,
    )
  )[0];

function eligibility(player: string, level: string, sha256?: string): Promise<Eligibility> {
  return playEligibility(env, player, level, sha256);
}

async function seedPlayer(id: string, banned = 0) {
  await env.DB.prepare("INSERT INTO players (id, name, banned, created) VALUES (?, ?, ?, 1)").bind(id, id, banned).run();
}

/** A published version of `level` (its level row is created on first use). */
async function seedVersion(level: string, version: number, sha256: string, hidden = 0) {
  await env.DB.prepare(
    "INSERT INTO levels (id, owner, latest, hidden, title, created) VALUES (?, 'p_author', ?, ?, ?, 1) ON CONFLICT (id) DO UPDATE SET latest = excluded.latest",
  )
    .bind(level, version, hidden, level)
    .run();
  await env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES (?, ?, ?, 1)").bind(level, version, sha256).run();
}

beforeEach(async () => {
  await env.DB.batch(
    ["play_attempts", "play_summaries", "players", "levels", "versions", "scores", "likes", "reports", "rate", "nonces", "hidden_levels", "player_ranking", "sweep"].map((table) =>
      env.DB.prepare(`DELETE FROM ${table}`),
    ),
  );
});

describe("POST /plays", () => {
  beforeEach(async () => {
    await seedPlayer(ALICE);
    await seedPlayer(BOB);
    await seedVersion(LEVEL, 1, V1);
    await seedVersion(LEVEL, 2, V2);
  });

  describe("recording attempts", () => {
    it("counts an attempt once through its first clear, ignoring a repeated finish and a stale start", async () => {
      expect(await report(ALICE, [start(A, V1, 1000)])).toEqual({ acknowledged: [{ id: A, revision: 1 }], discarded: [], cleared: [] });
      expect(await report(ALICE, [finish(A, V1, 1000, "cleared", 2000)])).toEqual({ acknowledged: [{ id: A, revision: 2 }], discarded: [], cleared: [V1] });
      expect(await report(ALICE, [finish(A, V1, 1000, "cleared", 2000)])).toMatchObject({ acknowledged: [{ id: A, revision: 2 }], discarded: [] });
      expect(await report(ALICE, [start(A, V1, 1000)])).toMatchObject({ acknowledged: [{ id: A, revision: 1 }], discarded: [] });

      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 1, first_clear_ms: 2000 });
      expect(await attemptOf(ALICE, A)).toMatchObject({ revision: 2, outcome: "cleared", ended_ms: 2000 });
    });

    it("stores the server's receipt time, not the client's start hint", async () => {
      const before = Date.now();
      await begin(ALICE, A, V1, 1000);
      const after = Date.now();

      const stored = await attemptOf(ALICE, A);
      expect(stored).toMatchObject({ started_ms: 1000 });
      expect(stored.received_ms).toBeGreaterThanOrEqual(before);
      expect(stored.received_ms).toBeLessThanOrEqual(after);
    });

    it("gives the same summary whether the finish or the start reaches the server first", async () => {
      expect(await report(ALICE, [finish(A, V1, 1000, "cleared", 2000)])).toMatchObject({ acknowledged: [{ id: A, revision: 2 }] });
      expect(await begin(ALICE, A, V1, 1000)).toMatchObject({ acknowledged: [{ id: A, revision: 1 }] });
      await attempt(BOB, A, V1, 1000, "cleared", 2000);

      expect(await summaryOf(ALICE, V1)).toEqual(await summaryOf(BOB, V1));
      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 1, first_clear_ms: 2000 });
      expect(await attemptOf(ALICE, A)).toMatchObject({ revision: 2, outcome: "cleared" });
    });

    it("counts concurrent identical reports once", async () => {
      const sendTwice = (attempts: Snapshot[]) => Promise.all([plays(ALICE, attempts), plays(ALICE, attempts)]);

      const starts = await sendTwice([start(A, V1, 1000)]);
      expect(starts.map((r) => r.status)).toEqual([200, 200]);
      const finishes = await sendTwice([finish(A, V1, 1000, "cleared", 2000)]);
      expect(finishes.map((r) => r.status)).toEqual([200, 200]);
      for (const response of [...starts, ...finishes]) expect(await response.json()).toMatchObject({ discarded: [] });

      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 1, first_clear_ms: 2000 });
    });

    it("counts starts up to the first clear, and an older clear reported later moves that cutoff", async () => {
      await attempt(ALICE, A, V1, 1000, "failed", 1200);
      await attempt(ALICE, B, V1, 2000, "cleared", 2500);
      await attempt(ALICE, C, V1, 3000, "failed", 3400);
      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 2, first_clear_ms: 2500 });

      // An offline report from earlier: D started at 500 and cleared at 750.
      await attempt(ALICE, D, V1, 500, "cleared", 750);
      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 1, first_clear_ms: 750 });
    });

    it("counts a start made at the exact moment of the first clear", async () => {
      await attempt(ALICE, A, V1, 1000, "cleared", 2000);
      await attempt(ALICE, B, V1, 2000, "failed", 2100);
      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 2, first_clear_ms: 2000 });
    });

    it("discards unknown and hidden versions without blocking valid records beside them", async () => {
      await seedVersion(HIDDEN_LEVEL, 1, HIDDEN, 1);
      await seedVersion(LISTED_LEVEL, 1, LISTED);
      await env.DB.prepare("INSERT INTO hidden_levels (level) VALUES (?)").bind(LISTED_LEVEL).run();

      const reply = await report(ALICE, [start(A, V1, 1000), start(B, UNKNOWN, 1000), start(C, HIDDEN, 1000), start(D, LISTED, 1000)]);
      expect(reply.acknowledged).toEqual([{ id: A, revision: 1 }]);
      expect(reply.discarded).toHaveLength(3);
      expect(reply.discarded).toEqual(
        expect.arrayContaining([
          { id: B, revision: 1, reason: "unknown_version" },
          { id: C, revision: 1, reason: "hidden_version" },
          { id: D, revision: 1, reason: "hidden_version" },
        ]),
      );
      expect(await rows("SELECT id FROM play_attempts WHERE player = ?", ALICE)).toEqual([{ id: A }]);

      expect(await report(ALICE, [finish(A, V1, 1000, "cleared", 2000)])).toMatchObject({ acknowledged: [{ id: A, revision: 2 }] });
      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 1, first_clear_ms: 2000 });
    });

    it("classifies a version hidden after its lookup as hidden_version, and stores only the unrelated record", async () => {
      await seedVersion(LISTED_LEVEL, 1, LISTED);
      // The lookup has already seen LEVEL as visible; hiding it here lands between the lookup and the guarded batch.
      let raced = false;
      const racing = {
        ...testEnv,
        DB: new Proxy(env.DB, {
          get(target, prop) {
            if (prop !== "batch") return Reflect.get(target, prop, target).bind(target);
            return async (statements: D1PreparedStatement[]) => {
              raced = true;
              await target.prepare("INSERT INTO hidden_levels (level) VALUES (?)").bind(LEVEL).run();
              return target.batch(statements);
            };
          },
        }) as unknown as D1Database,
      };

      const bytes = wire([start(A, V1, 1000), start(B, LISTED, 1000)]);
      const response = await worker.fetch(await playsRequest(ALICE, bytes, bytes, await nonce()), racing);
      expect(response.status).toBe(200);
      expect(raced).toBe(true);
      expect(await response.json<Reply>()).toEqual({
        acknowledged: [{ id: B, revision: 1 }],
        discarded: [{ id: A, revision: 1, reason: "hidden_version" }],
        cleared: [],
      });
      expect(await rows("SELECT id FROM play_attempts WHERE player = ?", ALICE)).toEqual([{ id: B }]);
      expect(await rows("SELECT sha256 FROM play_summaries WHERE player = ?", ALICE)).toEqual([{ sha256: LISTED }]);
    });

    it("keeps a conflicting record's original, discards the conflict, and still acknowledges unrelated records", async () => {
      await begin(ALICE, A, V1, 1000);
      expect(await report(ALICE, [start(A, V2, 1000), start(B, V1, 1500)])).toMatchObject({
        acknowledged: [{ id: B, revision: 1 }],
        discarded: [{ id: A, revision: 1, reason: "conflict" }],
      });

      await conclude(ALICE, A, V1, 1000, "cleared", 2000);
      expect(await report(ALICE, [finish(A, V1, 1000, "failed", 1500), start(C, V1, 3000)])).toMatchObject({
        acknowledged: [{ id: C, revision: 1 }],
        discarded: [{ id: A, revision: 2, reason: "conflict" }],
      });
      expect(await report(ALICE, [finish(A, V1, 1000, "cleared", 2500)])).toMatchObject({
        acknowledged: [],
        discarded: [{ id: A, revision: 2, reason: "conflict" }],
      });

      expect(await attemptOf(ALICE, A)).toMatchObject({ sha256: V1, started_ms: 1000, revision: 2, outcome: "cleared", ended_ms: 2000 });
      expect(await rows("SELECT sha256, attempts, first_clear_ms FROM play_summaries WHERE player = ?", ALICE)).toEqual([
        { sha256: V1, attempts: 2, first_clear_ms: 2000 },
      ]);
    });
  });

  describe("refusals", () => {
    it("accepts a 16384-byte batch and refuses one byte more with 413 before storing anything", async () => {
      expect((await sendRaw(ALICE, padded({ player_id: ALICE, attempts: [start(A, V1, 1000)] }, 16384))).status).toBe(200);
      expect((await sendRaw(ALICE, padded({ player_id: ALICE, attempts: [start(B, V1, 1000)] }, 16385))).status).toBe(413);
      expect(await rows("SELECT id FROM play_attempts WHERE player = ?", ALICE)).toEqual([{ id: A }]);
    });

    it("accepts 32 records and refuses 33 with 400, storing nothing from the refused batch", async () => {
      const thirtyTwo = Array.from({ length: 32 }, (_, i) => start(attemptId(i + 1), V1, 1000 + i));
      expect((await report(ALICE, thirtyTwo)).acknowledged).toHaveLength(32);
      expect(await summaryOf(ALICE, V1)).toMatchObject({ attempts: 32, first_clear_ms: null });

      expect((await plays(ALICE, [...thirtyTwo, start(attemptId(33), V1, 1000)])).status).toBe(400);
      expect(await rows("SELECT COUNT(*) AS n FROM play_attempts WHERE player = ?", ALICE)).toEqual([{ n: 32 }]);
    });

    const valid = start(A, V1, 1000);
    const ended = finish(A, V1, 1000, "cleared", 2000);
    it.each<[string, Uint8Array<ArrayBuffer>]>([
      ["a revision other than 1 or 2", wire([{ ...valid, revision: 3 }])],
      ["a start that carries an outcome", wire([{ ...valid, outcome: "failed" }])],
      ["a start that carries an end time", wire([{ ...valid, ended_ms: 1500 }])],
      ["a finish without an outcome", wire([{ ...ended, outcome: null }])],
      ["an unknown outcome", wire([{ ...ended, outcome: "won" }])],
      ["an end time before the start time", wire([{ ...ended, ended_ms: 999 }])],
      ["a negative start time", wire([{ ...valid, started_ms: -1 }])],
      ["a fractional start time", wire([{ ...valid, started_ms: 1.5 }])],
      ["a start time beyond the safe integer range", wire([{ ...valid, started_ms: Number.MAX_SAFE_INTEGER + 2 }])],
      ["a start time sent as a string", wire([{ ...valid, started_ms: "1000" }])],
      ["a revision sent as a string", wire([{ ...valid, revision: "1" }])],
      ["an uppercase attempt id", wire([{ ...valid, id: "A".repeat(32) }])],
      ["a short attempt id", wire([{ ...valid, id: "a".repeat(31) }])],
      ["an uppercase version hash", wire([{ ...valid, sha256: "F".repeat(64) }])],
      ["an unexpected snapshot field", wire([{ ...valid, note: "extra" }])],
      ["a snapshot without ended_ms", wire([{ id: A, sha256: V1, started_ms: 1000, revision: 1, outcome: null }])],
      ["a repeated attempt id in one batch", wire([valid, ended, start(B, V1, 3000)])],
      ["a valid record beside a malformed one", wire([start(B, V1, 3000), { ...valid, revision: 3 }])],
      ["a missing player_id", json({ attempts: [valid] })],
      ["a player_id that is not a string", wire([valid], 7)],
      ["attempts that are not an array", json({ player_id: ALICE, attempts: valid })],
      ["a body that is not JSON", new TextEncoder().encode("{not json")],
    ])("refuses %s with 400 and stores nothing", async (_name, bytes) => {
      expect((await sendRaw(ALICE, bytes)).status).toBe(400);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([]);
      expect(await rows("SELECT player FROM play_summaries")).toEqual([]);
    });

    it("refuses a report that names another player as its owner, with 403", async () => {
      expect((await plays(ALICE, [start(A, V1, 1000)], BOB)).status).toBe(403);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([]);
    });

    it("refuses a body that differs from the bytes its integrity token was bound to, with 403", async () => {
      const signed = wire([start(A, V1, 1000)]);
      const sent = wire([start(A, V1, 9000)]);
      expect((await sendRaw(ALICE, sent, signed)).status).toBe(403);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([]);
    });

    it("refuses a report without a session, with 401", async () => {
      const bytes = wire([start(A, V1, 1000)]);
      const n = await nonce();
      const request = new Request("https://example.com/plays", {
        method: "POST",
        body: bytes,
        headers: { "X-Integrity": `ok:${await boundNonce(n, [bytes])}`, "X-Nonce": n },
      });
      expect((await worker.fetch(request, testEnv)).status).toBe(401);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([]);
    });

    it("refuses a report without an integrity token, and a nonce that was already used, with 403", async () => {
      const bytes = wire([start(A, V1, 1000)]);
      const bare = new Request("https://example.com/plays", {
        method: "POST",
        body: bytes,
        headers: { Authorization: `Bearer ${await signSession(testEnv, ALICE)}`, "X-Nonce": await nonce() },
      });
      expect((await worker.fetch(bare, testEnv)).status).toBe(403);

      const used = await nonce();
      expect((await worker.fetch(await playsRequest(ALICE, bytes, bytes, used), testEnv)).status).toBe(200);
      expect((await worker.fetch(await playsRequest(ALICE, bytes, bytes, used), testEnv)).status).toBe(403);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([{ id: A }]);
    });

    it("refuses a banned player with 403", async () => {
      await seedPlayer(CAROL, 1);
      expect((await plays(CAROL, [start(A, V1, 1000)])).status).toBe(403);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([]);
    });

    it("allows 30 batches a minute per player and refuses the 31st with 429", async () => {
      const minute = Math.floor(Date.now() / 1000 / 60);
      await env.DB.prepare(`INSERT INTO rate (player, action, "window", count) VALUES (?, 'plays', ?, 29)`).bind(ALICE, minute).run();

      expect((await plays(ALICE, [start(A, V1, 1000)])).status).toBe(200);
      expect((await plays(ALICE, [start(B, V1, 1000)])).status).toBe(429);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([{ id: A }]);
    });
  });

  describe("eligibility", () => {
    it("four counted attempts do not unlock a version's vote; the fifth does", async () => {
      for (const [i, outcome] of ["failed", "abandoned", "failed", "abandoned"].entries()) {
        await attempt(ALICE, attemptId(i + 1), V1, 1000 * (i + 1), outcome, 1000 * (i + 1) + 100);
      }
      expect(await eligibility(ALICE, LEVEL, V1)).toEqual({ attempts: 4, cleared: false, eligible: false });

      await attempt(ALICE, attemptId(5), V1, 5000, "failed", 5100);
      expect(await eligibility(ALICE, LEVEL, V1)).toEqual({ attempts: 5, cleared: false, eligible: true });
    });

    it("an unfinished attempt counts as one of the five", async () => {
      for (const i of [1, 2, 3, 4]) await attempt(ALICE, attemptId(i), V1, 1000 * i, "failed", 1000 * i + 100);
      await begin(ALICE, attemptId(5), V1, 5000); // the app closed before the result

      expect(await eligibility(ALICE, LEVEL, V1)).toEqual({ attempts: 5, cleared: false, eligible: true });
    });

    it("one clear qualifies at once: for its version and the stage, but not for another version", async () => {
      await attempt(ALICE, A, V1, 1000, "cleared", 2000);

      expect(await eligibility(ALICE, LEVEL, V1)).toEqual({ attempts: 1, cleared: true, eligible: true });
      expect(await eligibility(ALICE, LEVEL)).toEqual({ attempts: 1, cleared: true, eligible: true });
      expect(await eligibility(ALICE, LEVEL, V2)).toEqual({ attempts: 0, cleared: false, eligible: false });
    });

    it("attempts on other versions count toward a stage's like but never unlock a new version's vote", async () => {
      for (const [i, sha256] of [V1, V1, V2, V2].entries()) await attempt(ALICE, attemptId(i + 1), sha256, 1000 * (i + 1), "failed", 1000 * (i + 1) + 100);
      expect(await eligibility(ALICE, LEVEL)).toEqual({ attempts: 4, cleared: false, eligible: false });
      expect(await eligibility(ALICE, LEVEL, V1)).toEqual({ attempts: 2, cleared: false, eligible: false });

      await attempt(ALICE, attemptId(5), V2, 5000, "failed", 5100);
      expect(await eligibility(ALICE, LEVEL)).toEqual({ attempts: 5, cleared: false, eligible: true });
      expect(await eligibility(ALICE, LEVEL, V2)).toEqual({ attempts: 3, cleared: false, eligible: false });
    });

    it("a verified score keeps its eligibility without play history; other players' attempts never count for it", async () => {
      await env.DB.prepare("INSERT INTO scores VALUES (?, ?, 100, 1, 1, 1, 'demos/score.demo.gz', 1)").bind(V1, ALICE).run();
      await attempt(BOB, A, V1, 1000, "failed", 1100);

      expect(await eligibility(ALICE, LEVEL, V1)).toMatchObject({ attempts: 0, eligible: true });
      expect(await eligibility(ALICE, LEVEL)).toMatchObject({ attempts: 0, eligible: true });
      expect(await eligibility(ALICE, LEVEL, V2)).toMatchObject({ attempts: 0, eligible: false });
    });
  });

  describe("account deletion", () => {
    it("DELETE /me removes only the caller's play history", async () => {
      await attempt(ALICE, A, V1, 1000, "cleared", 2000);
      await attempt(BOB, A, V1, 1000, "failed", 1500);

      const deleted = await worker.fetch(
        new Request("https://example.com/me", { method: "DELETE", headers: { Authorization: `Bearer ${await signSession(testEnv, ALICE)}` } }),
        testEnv,
      );
      expect(deleted.status).toBe(204);
      expect(await rows("SELECT player, id FROM play_attempts")).toEqual([{ player: BOB, id: A }]);
      expect(await rows("SELECT player FROM play_summaries")).toEqual([{ player: BOB }]);
      expect(await summaryOf(BOB, V1)).toEqual({ attempts: 1, first_clear_ms: null });
    });

    it("stores nothing for an account deleted while its report body is still arriving", async () => {
      const bytes = wire([start(A, V1, 1000)]);
      const n = await nonce();

      let reading!: () => void;
      const readStarted = new Promise<void>((resolve) => (reading = resolve));
      let release!: () => void;
      const gate = new Promise<void>((resolve) => (release = resolve));
      // highWaterMark 0: the Worker pulls the body only when it reads it, which happens after authentication.
      const body = new ReadableStream<Uint8Array>(
        {
          async pull(controller) {
            reading();
            await gate;
            controller.enqueue(bytes);
            controller.close();
          },
        },
        { highWaterMark: 0 },
      );
      const request = new Request("https://example.com/plays", {
        method: "POST",
        body,
        headers: {
          Authorization: `Bearer ${await signSession(testEnv, ALICE)}`,
          "X-Integrity": `ok:${await boundNonce(n, [bytes])}`,
          "X-Nonce": n,
        },
      });
      const sent = worker.fetch(request, testEnv);

      const first = await Promise.race([readStarted.then(() => "reading" as const), sent]);
      if (first !== "reading") expect(first.status).toBe(200); // only an early refusal before the body is read answers first

      const deleted = await worker.fetch(
        new Request("https://example.com/me", { method: "DELETE", headers: { Authorization: `Bearer ${await signSession(testEnv, ALICE)}` } }),
        testEnv,
      );
      expect(deleted.status).toBe(204);
      release();

      const response = await sent;
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(response.status).toBeLessThan(500);
      expect(await rows("SELECT id FROM play_attempts")).toEqual([]);
      expect(await rows("SELECT player FROM play_summaries")).toEqual([]);
    });
  });
});

describe("cron", () => {
  it("clears 'plays' rate windows older than two minutes and keeps the recent ones", async () => {
    const minute = Math.floor(Date.now() / 1000 / 60);
    await env.DB.prepare(`INSERT INTO rate (player, action, "window", count) VALUES (?, 'plays', ?, 1), (?, 'plays', ?, 1)`)
      .bind(ALICE, minute - 3, ALICE, minute - 1)
      .run();

    await runCron(testEnv, offlineGithub);

    expect(await rows(`SELECT "window" FROM rate WHERE action = 'plays'`)).toEqual([{ window: minute - 1 }]);
  });
});
