import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { boundNonce } from "../src/session";

const fixture = JSON.parse(readFileSync(join(import.meta.dirname, "../../fixtures/bound_nonce.json"), "utf8")) as {
  nonce: string;
  level_base64: string;
  demo_base64: string;
  bound: string;
};

describe("bound nonce", () => {
  it("matches the value the game computes for the shared fixture", async () => {
    const [level, demo] = [fixture.level_base64, fixture.demo_base64].map((b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
    expect(await boundNonce(fixture.nonce, [level, demo])).toBe(fixture.bound);
  });
});
