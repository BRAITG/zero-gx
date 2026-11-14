import { env } from "cloudflare:workers";
import { expect, it } from "vitest";

it("0006 lowers every stored score by the dropped 1000 base, floors it at 100, and clears the stale ranking", async () => {
  const migration = env.TEST_MIGRATIONS.find((m) => m.name === "0006_drop_base_points.sql")!;
  const seed = (player: string, points: number) => env.DB.prepare("INSERT INTO scores VALUES ('a', ?, ?, 1, 1, 1, '', 0)").bind(player, points);
  await env.DB.batch([seed("p_old", 2345), seed("p_low", 1050), seed("p_floor", 100), env.DB.prepare("INSERT INTO player_ranking VALUES ('p_old', 2345, 1, 0)")]);

  await env.DB.batch(migration.queries.map((sql) => env.DB.prepare(sql)));

  const { results } = await env.DB.prepare("SELECT player, points FROM scores ORDER BY player").all();
  expect(results).toEqual([
    { player: "p_floor", points: 100 },
    { player: "p_low", points: 100 },
    { player: "p_old", points: 1345 },
  ]);
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM player_ranking").first("n")).toBe(0);
});

it("0009 backfills last_ms as the maximum received_ms per player and version", async () => {
  const migration = env.TEST_MIGRATIONS.find((m) => m.name === "0009_version_stats.sql")!;
  const V1 = "a".repeat(64);
  const V2 = "b".repeat(64);
  const attempt = (player: string, id: string, sha256: string, received: number) => env.DB.prepare("INSERT INTO play_attempts (player, id, sha256, started_ms, revision, received_ms) VALUES (?, ?, ?, 1, 1, ?)").bind(player, id, sha256, received);
  const summary = (player: string, sha256: string) => env.DB.prepare("INSERT INTO play_summaries (player, sha256, attempts) VALUES (?, ?, 1)").bind(player, sha256);
  await env.DB.batch([
    env.DB.prepare("DROP TABLE version_stats"),
    env.DB.prepare("ALTER TABLE play_summaries DROP COLUMN last_ms"),
    env.DB.prepare("INSERT INTO players (id, name, created) VALUES ('p_a', 'a', 1), ('p_b', 'b', 1)"),
    env.DB.prepare("INSERT INTO versions (level, version, sha256, approved) VALUES ('lvl_aaaaaaaaaa', 1, ?1, 1), ('lvl_aaaaaaaaaa', 2, ?2, 1)").bind(V1, V2),
    attempt("p_a", "x1", V1, 100),
    attempt("p_a", "x2", V1, 300),
    attempt("p_a", "x3", V2, 200),
    attempt("p_b", "x4", V1, 50),
    summary("p_a", V1),
    summary("p_a", V2),
    summary("p_b", V1),
  ]);

  await env.DB.batch(migration.queries.map((sql) => env.DB.prepare(sql)));

  const { results } = await env.DB.prepare("SELECT player, sha256, last_ms FROM play_summaries ORDER BY player, sha256").all();
  expect(results).toEqual([
    { player: "p_a", sha256: V1, last_ms: 300 },
    { player: "p_a", sha256: V2, last_ms: 200 },
    { player: "p_b", sha256: V1, last_ms: 50 },
  ]);
  await env.DB.batch(["play_attempts", "play_summaries", "versions", "players"].map((table) => env.DB.prepare(`DELETE FROM ${table}`)));
});
