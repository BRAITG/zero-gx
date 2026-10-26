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
