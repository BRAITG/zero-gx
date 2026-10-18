import { exports } from "cloudflare:workers";
import { expect, it } from "vitest";

it("answers unknown routes with a 404 JSON error", async () => {
  const response = await exports.default.fetch("https://example.com/nope");
  expect(response.status).toBe(404);
  expect(await response.json()).toEqual({ error: "Not found." });
});
