import { readFileSync } from "node:fs";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const migrations = await readD1Migrations("./migrations");

// Workerd has no filesystem: the fixtures reach worker tests as base64 bindings.
const fixture = (path: string) => readFileSync(`../fixtures/${path}`).toString("base64");
const fixtures = {
  LEVEL_01: fixture("levels/level_01.json"),
  DEMO_LEVEL_01: fixture("demos/level_01.demo.gz"),
  DEMO_TELEPORT: fixture("demos/level_01.teleport.demo.gz"),
  LEVEL_05: fixture("levels/level_05.json"),
  DEMO_LEVEL_05: fixture("demos/level_05.demo.gz"),
};

export default defineConfig({
  test: {
    projects: [
      // Pure logic: Node, reads the game's levels and shared fixtures from disk.
      { test: { name: "core", environment: "node", include: ["test/*.test.ts"] } },
      // Routes, D1 and R2 inside the Workers runtime.
      {
        plugins: [
          cloudflareTest({
            wrangler: { configPath: "./wrangler.toml" },
            // The suite signs in far more than 30 times a minute; the limiter itself is tested with a stub binding.
            miniflare: { ratelimits: { AUTH_LIMITER: { namespace_id: "1001", simple: { limit: 1_000_000, period: 60 } } }, bindings: { TEST_MIGRATIONS: migrations, SESSION_KEY: "test-session-key", ADMIN_TOKEN: "test-admin-token", ...fixtures } },
          }),
        ],
        test: {
          name: "worker",
          include: ["test/worker/**/*.test.ts"],
          setupFiles: ["test/worker/apply-migrations.ts"],
        },
      },
    ],
  },
});
