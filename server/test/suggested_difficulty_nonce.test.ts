import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { isDifficulty } from "../src/core/difficulty";
import { boundNonce } from "../src/session";

const fixture = JSON.parse(readFileSync(join(import.meta.dirname, "../../fixtures/suggested_difficulty_nonce.json"), "utf8")) as {
  nonce: string;
  level_base64: string;
  demo_base64: string;
  suggested_difficulty: string;
  level_sha256: string;
  demo_sha256: string;
  suggested_difficulty_sha256: string;
  bound: string;
};

const level = Uint8Array.from(atob(fixture.level_base64), (c) => c.charCodeAt(0));
const demo = Uint8Array.from(atob(fixture.demo_base64), (c) => c.charCodeAt(0));
const suggestion = new TextEncoder().encode(fixture.suggested_difficulty);
const sha256Hex = (data: Uint8Array) => createHash("sha256").update(data).digest("hex");

describe("bound nonce with an author's suggested difficulty", () => {
  it("names one of the four labels, so the golden vector is a suggestion the server accepts", () => {
    expect(isDifficulty(fixture.suggested_difficulty)).toBe(true);
  });

  it("pins each part's SHA-256 as computed by a standard library, so other languages can check their inputs", () => {
    expect(sha256Hex(level)).toBe(fixture.level_sha256);
    expect(sha256Hex(demo)).toBe(fixture.demo_sha256);
    expect(sha256Hex(suggestion)).toBe(fixture.suggested_difficulty_sha256);
  });

  it("matches the value the game must compute over level, demo and the suggestion's UTF-8 bytes", async () => {
    expect(await boundNonce(fixture.nonce, [level, demo, suggestion])).toBe(fixture.bound);
  });

  it("differs from the two-part binding and from any other suggestion, so a tampered field cannot reuse it", async () => {
    expect(await boundNonce(fixture.nonce, [level, demo])).not.toBe(fixture.bound);
    expect(await boundNonce(fixture.nonce, [level, demo, new TextEncoder().encode("expert")])).not.toBe(fixture.bound);
  });
});
