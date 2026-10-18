import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    projects: [
      // Pure logic: Node, reads the game's levels and shared fixtures from disk.
      { test: { name: "core", environment: "node", include: ["test/*.test.ts"] } },
      // Routes, D1 and R2 inside the Workers runtime.
      {
        plugins: [cloudflareTest({ wrangler: { configPath: "./wrangler.toml" } })],
        test: { name: "worker", include: ["test/worker/**/*.test.ts"] },
      },
    ],
  },
});
