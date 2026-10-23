import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../../src/env";
import { signSession } from "../../src/session";
import worker from "../../src/worker";

const testEnv: Env = { ...env, ALLOW_TEST_VERIFIER: "1" };

const A = "lvl_aaaaaaaaaa";
const B = "lvl_bbbbbbbbbb";
const C = "lvl_cccccccccc";
const HIDDEN = "lvl_hhhhhhhhhh";
const UNKNOWN = "lvl_zzzzzzzzzz";

/** A version hash: 64 lowercase hex characters. */
const sha = (n: number) => n.toString(16).padStart(64, "0");
const A1 = sha(0x11);
const A2 = sha(0x12);
const B1 = sha(0x21);
const C1 = sha(0x31);
const H1 = sha(0x41);

/** Ten starters of a version as the server counts them: [counted attempts, cleared]. */
const EXAMPLE: [attempts: number, cleared: boolean][] = [
  [1, true],
  [3, true],
  [5, true],
  [5, false],
  [10, false],
  [20, false],
  [1, false],
  [2, false],
  [3, false],
  [4, false],
];

interface Stats {
  players_started: number;
  players_cleared: number;
  total_attempts: number;
  clear_rate: number | null;
  attempts_per_first_clear: number | null;
  median_tries: number | null;
  unbeaten_5: number;
  unbeaten_10: number;
  unbeaten_20: number;
}

interface Feedback {
  level_id: string;
  sha256: string;
  reviewed_difficulty: string | null;
  community_difficulty: { value: string | null; votes: number };
  stats: Stats;
  you: { liked: boolean; like_eligible: boolean; difficulty: string | null; difficulty_eligible: boolean; attempts: number; cleared: boolean };
}

interface ListRow {
  level_id: string;
  reviewed_difficulty: string | null;
  community_difficulty: { value: string | null; votes: number };
}

const rows = async <T>(sql: string, ...values: unknown[]) => (await env.DB.prepare(sql).bind(...values).all<T>()).results;

/** A request as `player`, or signed out when null. `bindings` lets a test wrap the database. */
async function call(player: string | null, method: string, path: string, body?: unknown, bindings: Env = testEnv): Promise<Response> {
  const headers: Record<string, string> = player ? { Authorization: `Bearer ${await signSession(testEnv, player)}` } : {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  return worker.fetch(new Request(`https://example.com${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }), bindings);
}

/** The worker's bindings with the database wrapped so that `beforeBatch` runs once, just before the first batch the handler writes. */
function racing(beforeBatch: () => Promise<unknown>) {
  const state = { raced: false };
  const DB = new Proxy(env.DB, {
    get(target, prop) {
      if (prop !== "batch") return Reflect.get(target, prop, target).bind(target);
      return async (statements: D1PreparedStatement[]) => {
        if (!state.raced) {
          state.raced = true;
          await beforeBatch();
        }
        return target.batch(statements);
      };
    },
  });
  return { env: { ...testEnv, DB } as Env, state };
}

async function seedPlayer(id: string, banned = 0) {
  await env.DB.prepare("INSERT OR IGNORE INTO players (id, name, banned, created) VALUES (?, ?, ?, 1)").bind(id, id, banned).run();
}

/** A published stage whose versions 1..n have these hashes; `hidden` hides it the way moderation does. */
async function seedStage(level: string, hashes: string[], hidden = 0) {
  await env.DB.prepare("INSERT INTO levels (id, owner, latest, hidden, title, created) VALUES (?, 'p_author', ?, ?, ?, 1)").bind(level, hashes.length, hidden, level).run();
  for (const [i, sha256] of hashes.entries()) {
    await env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES (?, ?, ?, ?)").bind(level, i + 1, sha256, i + 1).run();
  }
}

/** Play history as the server keeps it: counted attempts, and whether the version was cleared. */
async function summary(player: string, sha256: string, attempts: number, cleared = false) {
  await env.DB.prepare("INSERT INTO play_summaries (player, sha256, attempts, first_clear_ms) VALUES (?, ?, ?, ?)").bind(player, sha256, attempts, cleared ? 1000 : null).run();
}

/** Starters of `sha256`, one per entry, named p_s1, p_s2, ... */
async function starters(sha256: string, history: [attempts: number, cleared: boolean][]) {
  for (const [i, [attempts, cleared]] of history.entries()) {
    await seedPlayer(`p_s${i + 1}`);
    await summary(`p_s${i + 1}`, sha256, attempts, cleared);
  }
}

/** A server-verified score: eligibility from before play history existed. */
async function score(player: string, sha256: string) {
  await env.DB.prepare("INSERT INTO scores (sha256, player, points, fuel, hull, seconds, demo, posted) VALUES (?, ?, 1, 1, 1, 1, ?, 1)").bind(sha256, player, `demos/${player}.demo.gz`).run();
}

/** The feedback of `sha256` on `level` as `viewer` sees it. */
async function feedback(viewer: string, level: string, sha256: string): Promise<Feedback> {
  const response = await call(viewer, "GET", `/levels/${level}/feedback?sha256=${sha256}`);
  expect(response.status).toBe(200);
  return response.json<Feedback>();
}

const vote = (player: string, level: string, sha256: string, difficulty: string) => call(player, "PUT", `/levels/${level}/difficulty`, { sha256, difficulty });
const like = (player: string, level: string) => call(player, "POST", `/levels/${level}/like`);

beforeEach(async () => {
  await env.DB.batch(
    ["play_attempts", "play_summaries", "difficulty_votes", "players", "levels", "versions", "scores", "likes", "reports", "rate", "nonces", "hidden_levels", "player_ranking", "sweep"].map((table) =>
      env.DB.prepare(`DELETE FROM ${table}`),
    ),
  );
});

describe("GET /levels/:level/feedback", () => {
  it("answers an unplayed version with the empty shape", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    expect(await feedback("p_you", A, A1)).toEqual({
      level_id: A,
      sha256: A1,
      reviewed_difficulty: null,
      community_difficulty: { value: null, votes: 0 },
      stats: { players_started: 0, players_cleared: 0, total_attempts: 0, clear_rate: null, attempts_per_first_clear: null, median_tries: null, unbeaten_5: 0, unbeaten_10: 0, unbeaten_20: 0 },
      you: { liked: false, like_eligible: false, difficulty: null, difficulty_eligible: false, attempts: 0, cleared: false },
    });
  });

  it("answers 400 without a well-formed sha256", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    expect((await call("p_you", "GET", `/levels/${A}/feedback`)).status).toBe(400);
    expect((await call("p_you", "GET", `/levels/${A}/feedback?sha256=ABC`)).status).toBe(400);
  });

  it("counts ten starters, three clears and 54 attempts, with the derived ratios", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    await starters(A1, EXAMPLE);
    const reply = await feedback("p_you", A, A1);
    expect(reply.stats).toMatchObject({
      players_started: 10,
      players_cleared: 3,
      total_attempts: 54,
      clear_rate: 0.3,
      attempts_per_first_clear: 18,
      median_tries: 3,
      unbeaten_5: 3,
      unbeaten_10: 2,
      unbeaten_20: 1,
    });
  });

  it("withholds ratios and the median below ten starters, and gives a clear rate of 0 at ten with no clear", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    await seedStage(B, [B1]);

    await starters(A1, [[1, true], [2, false], [2, false], [2, false], [2, false], [2, false], [2, false], [2, false], [2, false]]);
    expect(await feedback("p_you", A, A1)).toMatchObject({
      stats: { players_started: 9, players_cleared: 1, total_attempts: 17, clear_rate: null, attempts_per_first_clear: null, median_tries: null, unbeaten_5: 0 },
    });

    await starters(B1, [[1, false], [2, false], [3, false], [4, false], [5, false], [6, false], [7, false], [8, false], [9, false], [10, false]]);
    expect(await feedback("p_you", B, B1)).toMatchObject({
      stats: { players_started: 10, players_cleared: 0, total_attempts: 55, clear_rate: 0, attempts_per_first_clear: null, median_tries: null, unbeaten_5: 6, unbeaten_10: 1, unbeaten_20: 0 },
    });
  });

  it("gives the ordinary median of finishers, averaging the middle two", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    await starters(A1, [[1, true], [2, true], [3, true], [4, true], [1, false], [1, false], [1, false], [1, false], [1, false], [1, false]]);
    expect(await feedback("p_you", A, A1)).toMatchObject({
      stats: { players_started: 10, players_cleared: 4, total_attempts: 16, clear_rate: 0.4, attempts_per_first_clear: 4, median_tries: 2.5 },
    });
  });

  it("exposes the caller's own state and no other player's", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    await starters(A1, EXAMPLE);
    const text = JSON.stringify(await feedback("p_you", A, A1));
    expect(text).not.toContain("p_s");
  });

  it("gives each caller eligibility from their own history on this version, and a stage-wide like from any version", async () => {
    await seedStage(A, [A1, A2]);
    for (const id of ["p_four", "p_five", "p_clear", "p_other"]) await seedPlayer(id);
    await summary("p_four", A1, 2);
    await summary("p_four", A2, 2);
    await summary("p_five", A1, 5);
    await summary("p_clear", A1, 1, true);
    await summary("p_other", A2, 5);

    expect((await feedback("p_four", A, A1)).you).toEqual({ liked: false, like_eligible: false, difficulty: null, difficulty_eligible: false, attempts: 2, cleared: false });
    expect((await feedback("p_five", A, A1)).you).toEqual({ liked: false, like_eligible: true, difficulty: null, difficulty_eligible: true, attempts: 5, cleared: false });
    expect((await feedback("p_clear", A, A1)).you).toMatchObject({ like_eligible: true, difficulty_eligible: true, attempts: 1, cleared: true });
    expect((await feedback("p_other", A, A1)).you).toEqual({ liked: false, like_eligible: true, difficulty: null, difficulty_eligible: false, attempts: 0, cleared: false });
  });

  it("keeps a verified score's eligibility without fabricating statistics", async () => {
    await seedPlayer("p_old");
    await seedStage(A, [A1, A2]);
    await score("p_old", A1);

    const reply = await feedback("p_old", A, A1);
    expect(reply.stats).toMatchObject({ players_started: 0, total_attempts: 0, clear_rate: null });
    expect(reply.you).toMatchObject({ like_eligible: true, difficulty_eligible: true, attempts: 0 });
    expect((await feedback("p_old", A, A2)).you).toMatchObject({ like_eligible: true, difficulty_eligible: false });
    expect(await rows("SELECT player FROM play_summaries")).toEqual([]);
  });
});

describe("POST /levels/:level/like", () => {
  beforeEach(async () => {
    await seedPlayer("p_l");
    await seedStage(A, [A1, A2]);
  });

  it("needs a clear on any version or five counted attempts across the stage", async () => {
    await summary("p_l", A1, 2);
    await summary("p_l", A2, 2);
    expect((await like("p_l", A)).status).toBe(403);

    await env.DB.prepare("UPDATE play_summaries SET attempts = 3 WHERE player = ? AND sha256 = ?").bind("p_l", A2).run();
    const liked = await like("p_l", A);
    expect(liked.status).toBe(200);
    expect(await liked.json()).toEqual({ likes: 1 });
  });

  it("accepts a like after a clear on any version, which does not qualify a vote on another", async () => {
    await summary("p_l", A1, 1, true);
    const liked = await like("p_l", A);
    expect(liked.status).toBe(200);
    expect(await liked.json()).toEqual({ likes: 1 });
    expect((await feedback("p_l", A, A2)).you).toMatchObject({ liked: true, like_eligible: true, difficulty_eligible: false });
  });

  it("keeps a like unlocked by a verified score", async () => {
    await score("p_l", A1);
    const liked = await like("p_l", A);
    expect(liked.status).toBe(200);
    expect(await liked.json()).toEqual({ likes: 1 });
  });

  it("removes a like without any play", async () => {
    await env.DB.prepare("INSERT INTO likes (player, level) VALUES (?, ?)").bind("p_l", A).run();
    const removed = await call("p_l", "DELETE", `/levels/${A}/like`);
    expect(removed.status).toBe(200);
    expect(await removed.json()).toEqual({ likes: 0 });
  });

  it.each([false, true])("answers 404 and leaves the likes unchanged when the level is hidden between the lookup and the write (repeated like: %s)", async (repeated) => {
    await seedPlayer("p_other");
    await summary("p_l", A1, 1, true);
    await env.DB.prepare("INSERT INTO likes (player, level) VALUES (?, ?)").bind("p_other", A).run();
    if (repeated) await env.DB.prepare("INSERT INTO likes (player, level) VALUES (?, ?)").bind("p_l", A).run();

    const race = racing(() => env.DB.prepare("INSERT INTO hidden_levels (level) VALUES (?)").bind(A).run());
    const response = await call("p_l", "POST", `/levels/${A}/like`, undefined, race.env);
    expect(race.state.raced).toBe(true);
    expect(response.status).toBe(404);
    const likers = repeated ? ["p_l", "p_other"] : ["p_other"];
    expect(await rows("SELECT player FROM likes WHERE level = ? ORDER BY player", A)).toEqual(likers.map((player) => ({ player })));
    expect(await rows("SELECT sha256, attempts FROM play_summaries WHERE player = ?", "p_l")).toEqual([{ sha256: A1, attempts: 1 }]);
    expect(await rows("SELECT level FROM hidden_levels")).toEqual([{ level: A }]);
  });
});

describe("PUT and DELETE /levels/:level/difficulty", () => {
  beforeEach(async () => {
    await seedStage(A, [A1, A2]);
  });

  it("needs four counted attempts to vote on a version, and five to vote", async () => {
    await seedPlayer("p_r");
    await summary("p_r", A1, 4);
    expect((await vote("p_r", A, A1, "hard")).status).toBe(403);

    await env.DB.prepare("UPDATE play_summaries SET attempts = 5 WHERE player = ? AND sha256 = ?").bind("p_r", A1).run();
    expect((await vote("p_r", A, A1, "hard")).status).toBe(200);
    expect((await feedback("p_r", A, A1)).you).toMatchObject({ difficulty: "hard", difficulty_eligible: true });
  });

  it("counts a clear on this version, but not a clear on another", async () => {
    await seedPlayer("p_c");
    await summary("p_c", A1, 1, true);
    expect((await vote("p_c", A, A2, "easy")).status).toBe(403);
    expect((await vote("p_c", A, A1, "easy")).status).toBe(200);
  });

  it("replaces one vote, and removes it without playing again", async () => {
    await seedPlayer("p_c");
    await summary("p_c", A1, 1, true);
    expect((await vote("p_c", A, A1, "easy")).status).toBe(200);
    expect((await vote("p_c", A, A1, "hard")).status).toBe(200);
    expect(await feedback("p_c", A, A1)).toMatchObject({ community_difficulty: { value: null, votes: 1 }, you: { difficulty: "hard" } });

    await env.DB.prepare("DELETE FROM play_summaries WHERE player = ?").bind("p_c").run();
    expect((await call("p_c", "DELETE", `/levels/${A}/difficulty?sha256=${A1}`)).status).toBe(200);
    expect(await feedback("p_c", A, A1)).toMatchObject({ community_difficulty: { value: null, votes: 0 }, you: { difficulty: null, difficulty_eligible: false } });
    expect((await call("p_c", "DELETE", `/levels/${A}/difficulty?sha256=${A1}`)).status).toBe(200);
  });

  it("gives the upper median from five voters, and a sixth expert vote moves it to hard", async () => {
    const voters = ["p_v1", "p_v2", "p_v3", "p_v4", "p_v5", "p_v6"];
    for (const id of voters) {
      await seedPlayer(id);
      await summary(id, A1, 5);
    }
    for (const [i, label] of ["easy", "normal", "normal", "hard"].entries()) expect((await vote(voters[i]!, A, A1, label)).status).toBe(200);
    expect(await feedback("p_v1", A, A1)).toMatchObject({ community_difficulty: { value: null, votes: 4 } });

    expect((await vote("p_v5", A, A1, "expert")).status).toBe(200);
    expect(await feedback("p_v1", A, A1)).toMatchObject({ community_difficulty: { value: "normal", votes: 5 } });

    expect((await vote("p_v6", A, A1, "expert")).status).toBe(200);
    expect(await feedback("p_v1", A, A1)).toMatchObject({ community_difficulty: { value: "hard", votes: 6 } });
  });

  it("rejects an unknown label or a malformed hash, and stores nothing", async () => {
    await seedPlayer("p_c");
    await summary("p_c", A1, 1, true);
    const bodies = [
      { sha256: A1, difficulty: "legendary" },
      { sha256: A1, difficulty: "Normal" },
      { sha256: A1, difficulty: "constructor" },
      { sha256: A1 },
      { sha256: "ABC", difficulty: "easy" },
      { sha256: sha(0xab).toUpperCase(), difficulty: "easy" },
    ];
    for (const body of bodies) expect((await call("p_c", "PUT", `/levels/${A}/difficulty`, body)).status).toBe(400);
    expect((await feedback("p_c", A, A1)).community_difficulty.votes).toBe(0);
  });

  it("answers 404 for a hash off this stage, an unknown hash, and hidden or unknown stages", async () => {
    await seedPlayer("p_r");
    await seedStage(B, [B1]);
    await seedStage(C, [C1]);
    await env.DB.prepare("INSERT INTO hidden_levels (level) VALUES (?)").bind(C).run();
    await seedStage(HIDDEN, [H1], 1);
    for (const hash of [A1, B1, C1, H1]) await summary("p_r", hash, 5, true);

    // A positive control first, so the refusals below cannot pass against a missing route.
    expect((await vote("p_r", A, A1, "easy")).status).toBe(200);
    expect((await vote("p_r", A, B1, "easy")).status).toBe(404); // another stage's version
    expect((await vote("p_r", A, sha(0x99), "easy")).status).toBe(404); // a hash no version has
    expect((await vote("p_r", C, C1, "easy")).status).toBe(404); // hidden through hidden_levels
    expect((await vote("p_r", HIDDEN, H1, "easy")).status).toBe(404); // hidden stage
    expect((await vote("p_r", UNKNOWN, A1, "easy")).status).toBe(404); // no such stage
    expect((await call("p_r", "GET", `/levels/${A}/feedback?sha256=${B1}`)).status).toBe(404);
    expect((await call("p_r", "GET", `/levels/${HIDDEN}/feedback?sha256=${H1}`)).status).toBe(404);
    expect((await call("p_r", "GET", `/levels/${C}/feedback?sha256=${C1}`)).status).toBe(404);
    expect((await call("p_r", "GET", `/levels/${UNKNOWN}/feedback?sha256=${A1}`)).status).toBe(404);
  });

  it("refuses a vote from a banned player", async () => {
    await seedPlayer("p_b", 1);
    await summary("p_b", A1, 5, true);
    expect((await vote("p_b", A, A1, "easy")).status).toBe(403);
  });

  it("requires a session to read feedback, vote or remove a vote", async () => {
    expect((await call(null, "GET", `/levels/${A}/feedback?sha256=${A1}`)).status).toBe(401);
    expect((await call(null, "PUT", `/levels/${A}/difficulty`, { sha256: A1, difficulty: "easy" })).status).toBe(401);
    expect((await call(null, "DELETE", `/levels/${A}/difficulty?sha256=${A1}`)).status).toBe(401);
  });
});

describe("reviewed difficulty", () => {
  it("shows a version's reviewed label on that version only, and refuses an unknown label", async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1, A2]);
    expect((await feedback("p_you", A, A2)).reviewed_difficulty).toBeNull();

    await env.DB.prepare("UPDATE versions SET reviewed_difficulty = 'expert' WHERE sha256 = ?").bind(A2).run();
    expect((await feedback("p_you", A, A2)).reviewed_difficulty).toBe("expert");
    expect((await feedback("p_you", A, A1)).reviewed_difficulty).toBeNull();
    await expect(env.DB.prepare("UPDATE versions SET reviewed_difficulty = 'legendary' WHERE sha256 = ?").bind(A1).run()).rejects.toThrow();
  });
});

describe("GET /levels rows", () => {
  it("lists each stage's reviewed label and its community label with the voter count, kept apart", async () => {
    await seedStage(A, [A1, A2]);
    await seedStage(B, [B1]);
    const voters = ["p_v1", "p_v2", "p_v3", "p_v4", "p_v5"];
    for (const id of voters) {
      await seedPlayer(id);
      await summary(id, A2, 5);
    }

    const before = await (await call("p_v1", "GET", "/levels")).json<ListRow[]>();
    expect(before.find((row) => row.level_id === A)).toMatchObject({ reviewed_difficulty: null, community_difficulty: { value: null, votes: 0 } });

    for (const [i, label] of ["easy", "normal", "normal", "hard", "expert"].entries()) expect((await vote(voters[i]!, A, A2, label)).status).toBe(200);
    await env.DB.prepare("UPDATE versions SET reviewed_difficulty = 'expert' WHERE sha256 = ?").bind(A2).run();

    const after = await (await call("p_v1", "GET", "/levels")).json<ListRow[]>();
    expect(after.find((row) => row.level_id === A)).toMatchObject({ reviewed_difficulty: "expert", community_difficulty: { value: "normal", votes: 5 } });
    expect(after.find((row) => row.level_id === B)).toMatchObject({ reviewed_difficulty: null, community_difficulty: { value: null, votes: 0 } });
  });
});

describe("banned and deleted contributors", () => {
  beforeEach(async () => {
    await seedPlayer("p_you");
    await seedStage(A, [A1]);
    await starters(A1, EXAMPLE);
  });

  it("drops a banned starter at query time and reapplies the small-sample thresholds", async () => {
    expect((await feedback("p_you", A, A1)).stats).toMatchObject({ players_started: 10, total_attempts: 54, unbeaten_20: 1 });

    await env.DB.prepare("UPDATE players SET banned = 1 WHERE id = ?").bind("p_s6").run();
    expect((await feedback("p_you", A, A1)).stats).toMatchObject({
      players_started: 9,
      players_cleared: 3,
      total_attempts: 34,
      clear_rate: null,
      attempts_per_first_clear: null,
      median_tries: null,
      unbeaten_5: 2,
      unbeaten_10: 1,
      unbeaten_20: 0,
    });
  });

  it("drops a banned voter from the community label", async () => {
    for (const [id, label] of [
      ["p_s1", "easy"],
      ["p_s2", "normal"],
      ["p_s3", "normal"],
      ["p_s4", "hard"],
      ["p_s5", "expert"],
    ]) {
      expect((await vote(id, A, A1, label)).status).toBe(200);
    }
    expect(await feedback("p_you", A, A1)).toMatchObject({ community_difficulty: { value: "normal", votes: 5 } });

    await env.DB.prepare("UPDATE players SET banned = 1 WHERE id = ?").bind("p_s5").run();
    expect(await feedback("p_you", A, A1)).toMatchObject({ community_difficulty: { value: null, votes: 4 } });
  });

  it("removes a deleted account's history, likes and vote with it", async () => {
    expect((await vote("p_s1", A, A1, "easy")).status).toBe(200);
    expect((await like("p_s1", A)).status).toBe(200);

    expect((await call("p_s1", "DELETE", "/me")).status).toBe(204);
    expect(await feedback("p_you", A, A1)).toMatchObject({
      stats: { players_started: 9, players_cleared: 2, total_attempts: 53, clear_rate: null, attempts_per_first_clear: null },
      community_difficulty: { value: null, votes: 0 },
    });
    expect(await rows("SELECT player FROM play_summaries WHERE player = ?", "p_s1")).toEqual([]);
    expect(await rows("SELECT level FROM likes WHERE player = ?", "p_s1")).toEqual([]);
  });
});

describe("concurrent deletion", () => {
  it("stores no like for an account deleted before the like is written", async () => {
    await seedPlayer("p_r");
    await seedStage(A, [A1]);
    await score("p_r", A1);

    const race = racing(() => call("p_r", "DELETE", "/me"));
    const response = await call("p_r", "POST", `/levels/${A}/like`, undefined, race.env);
    expect(race.state.raced).toBe(true);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(500);
    expect(await rows("SELECT level FROM likes WHERE player = ?", "p_r")).toEqual([]);
  });

  it("stores no vote for an account deleted before the vote is written", async () => {
    await seedPlayer("p_r");
    await seedStage(A, [A1]);
    await summary("p_r", A1, 1, true);

    const race = racing(() => call("p_r", "DELETE", "/me"));
    const response = await call("p_r", "PUT", `/levels/${A}/difficulty`, { sha256: A1, difficulty: "hard" }, race.env);
    expect(race.state.raced).toBe(true);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.status).toBeLessThan(500);
    expect(await rows("SELECT player FROM difficulty_votes WHERE player = ?", "p_r")).toEqual([]);
  });
});
