import { readFileSync } from "node:fs";
import { join } from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { checkDemo, scoreDemo, type Claim } from "../src/core/check";
import { MAX_BYTES, decodeDemo } from "../src/core/demo";
import { sha256Hex } from "../src/core/level";

const root = join(import.meta.dirname, "../..");
const expected = JSON.parse(readFileSync(join(root, "fixtures/expected.json"), "utf8")) as {
  demos: Record<string, { level: string; errors: string[]; points: number | null; claim?: Claim }>;
};

describe("fixture demos", () => {
  for (const [file, want] of Object.entries(expected.demos)) {
    it(file, async () => {
      const levelBytes = readFileSync(join(root, "fixtures/levels", want.level));
      const level = JSON.parse(levelBytes.toString("utf8"));
      const demo = await decodeDemo(readFileSync(join(root, "fixtures/demos", file)));
      expect(demo).not.toBeNull();
      const errors = checkDemo(level, await sha256Hex(levelBytes), demo!, want.claim);
      for (const error of errors) expect(want.errors.some((s) => error.includes(s)), error).toBe(true);
      for (const s of want.errors) expect(errors.some((e) => e.includes(s)), s).toBe(true);
      if (want.points !== null) expect(scoreDemo(level, demo!).points).toBe(want.points);
    });
  }
});

describe("decodeDemo rejects", () => {
  const good = () => readFileSync(join(root, "fixtures/demos/level_01.demo.gz"));
  const raw = () => gunzipSync(good());
  const header = (frames: number) => {
    const h = Buffer.alloc(42);
    h.write("ZGXD");
    h[4] = 1;
    h.writeUInt32LE(frames, 37);
    return h;
  };

  it("garbage, empty and truncated input", async () => {
    expect(await decodeDemo(new Uint8Array(0))).toBeNull();
    expect(await decodeDemo(Buffer.from("not a demo at all"))).toBeNull();
    expect(await decodeDemo(Buffer.from([0x1f, 0x8b, 0, 0, 0]))).toBeNull();
    expect(await decodeDemo(good().subarray(0, good().length - 20))).toBeNull();
  });

  it("a wrong magic, version or trailing byte", async () => {
    for (const mutate of [(b: Buffer) => (b[0] = 0x58), (b: Buffer) => (b[4] = 2), (b: Buffer) => void b.writeUInt32LE(18001, 37)]) {
      const body = raw();
      mutate(body);
      expect(await decodeDemo(gzipSync(body))).toBeNull();
    }
    expect(await decodeDemo(gzipSync(Buffer.concat([raw(), Buffer.from([0])])))).toBeNull();
  });

  it("input over MAX_BYTES", async () => {
    const big = Buffer.alloc(MAX_BYTES + 1);
    big[0] = 0x1f;
    big[1] = 0x8b;
    expect(await decodeDemo(big)).toBeNull();
  });

  it("a gzip bomb", async () => {
    const bomb = gzipSync(Buffer.alloc(64 * 1024 * 1024));
    expect(bomb.length).toBeLessThan(MAX_BYTES);
    expect(await decodeDemo(bomb)).toBeNull();
  });

  it("MAX_ALIVE + 1 asteroids", async () => {
    const frame = Buffer.alloc(17);
    frame.writeUInt16LE(1025, 15);
    // id, ABSOLUTE flag, then x, y (s32) and rotation (s16)
    const entries = Array.from({ length: 1025 }, (_, id) => Buffer.concat([u16(id), Buffer.from([1]), Buffer.alloc(10)]));
    const body = Buffer.concat([header(1), frame, ...entries, Buffer.alloc(4)]);
    expect(await decodeDemo(gzipSync(body))).toBeNull();
    // The same body with MAX_ALIVE asteroids is fine.
    frame.writeUInt16LE(1024, 15);
    expect(await decodeDemo(gzipSync(Buffer.concat([header(1), frame, ...entries.slice(0, 1024), Buffer.alloc(4)])))).not.toBeNull();
  });
});

const u16 = (n: number) => {
  const b = Buffer.alloc(2);
  b.writeUInt16LE(n);
  return b;
};
