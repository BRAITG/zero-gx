import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const migrations = await readD1Migrations("./migrations");

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
            miniflare: { bindings: { TEST_MIGRATIONS: migrations, SESSION_KEY: "test-session-key" } },
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
