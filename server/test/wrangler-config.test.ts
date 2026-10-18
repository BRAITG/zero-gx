import { readFileSync } from "node:fs";
import { join } from "node:path";
import { expect, it } from "vitest";

// A typo in the binding would silently disable the limiter: the Worker skips the check when it is absent.
it("declares the AUTH_LIMITER rate-limit binding", () => {
  const toml = readFileSync(join(import.meta.dirname, "../wrangler.toml"), "utf8");
  const block = toml.match(/\[\[ratelimits\]\]([^[]*)/)?.[1] ?? "";
  expect(block).toMatch(/^name = "AUTH_LIMITER"$/m);
  expect(block).toMatch(/^simple = \{ limit = 30, period = 60 \}$/m);
});
