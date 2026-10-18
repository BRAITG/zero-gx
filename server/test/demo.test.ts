import { readFileSync } from "node:fs";
import { join } from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { checkDemo, scoreDemo, segmentsIntersect, type Claim } from "../src/core/check";
import { MAX_BYTES, MAX_DECOMPRESSED, decodeDemo } from "../src/core/demo";
import { sha256Hex, vec } from "../src/core/level";

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

  // A frame: ship record, changed-asteroid count, then the entries.
  const frameOf = (...entries: Buffer[]) => {
    const head = Buffer.alloc(17);
    head.writeUInt16LE(entries.length, 15);
    return Buffer.concat([head, ...entries]);
  };
  const absolute = (id: number) => Buffer.concat([u16(id), Buffer.from([1]), Buffer.alloc(10)]); // x, y s32, rotation s16
  const entry = (id: number, flag: number, payload = 6) => Buffer.concat([u16(id), Buffer.from([flag]), Buffer.alloc(payload)]);
  const eventsOf = (...list: [number, number][]) =>
    Buffer.concat([u32(list.length), ...list.map(([frame, code]) => Buffer.concat([u32(frame), Buffer.from([code]), u16(0)]))]);
  const decode = (...parts: Buffer[]) => decodeDemo(gzipSync(Buffer.concat(parts)));

  it("MAX_ALIVE + 1 asteroids", async () => {
    const entries = Array.from({ length: 1025 }, (_, id) => absolute(id));
    expect(await decode(header(1), frameOf(...entries), eventsOf())).toBeNull();
    // The same body with MAX_ALIVE asteroids is fine.
    expect(await decode(header(1), frameOf(...entries.slice(0, 1024)), eventsOf())).not.toBeNull();
  });

  it("more than MAX_ASTEROID_FRAMES asteroid-frames", async () => {
    const alive = frameOf(...Array.from({ length: 1024 }, (_, id) => absolute(id)));
    const quiet = frameOf();
    // 1024 alive for 3906 frames is 3,999,744: under the cap, one more frame is over.
    expect(await decode(header(3906), alive, ...Array(3905).fill(quiet), eventsOf())).not.toBeNull();
    expect(await decode(header(3907), alive, ...Array(3906).fill(quiet), eventsOf())).toBeNull();
  });

  it("a delta or removal of an asteroid that is not alive", async () => {
    expect(await decode(header(1), frameOf(entry(5, 0)), eventsOf())).toBeNull();
    expect(await decode(header(1), frameOf(entry(5, 2, 0)), eventsOf())).toBeNull();
    expect(await decode(header(2), frameOf(absolute(5)), frameOf(entry(5, 2, 0), entry(5, 2, 0)), eventsOf())).toBeNull();
    expect(await decode(header(1), frameOf(entry(5, 3, 0)), eventsOf())).toBeNull();
    // A delta and a removal of a live one are fine.
    expect(await decode(header(2), frameOf(absolute(5)), frameOf(entry(5, 0), entry(5, 2, 0)), eventsOf())).not.toBeNull();
  });

  it("an event with code 0 or 8, or past the last frame", async () => {
    expect(await decode(header(1), frameOf(), eventsOf([1, 4]))).not.toBeNull();
    expect(await decode(header(1), frameOf(), eventsOf([1, 0]))).toBeNull();
    expect(await decode(header(1), frameOf(), eventsOf([1, 8]))).toBeNull();
    expect(await decode(header(1), frameOf(), eventsOf([2, 4]))).toBeNull();
    expect(await decode(header(1), frameOf(), eventsOf([1, 4]), Buffer.from([0]))).toBeNull();
  });

  it("the most events a body can hold decode into compact arrays", async () => {
    const count = Math.floor((MAX_DECOMPRESSED - 42 - 4) / 7);
    const events = Buffer.alloc(count * 7);
    for (let i = 0; i < count; i++) events[i * 7 + 4] = 1 + (i % 7);
    const body = Buffer.concat([header(0), u32(count), events]);
    expect(body.length).toBeLessThanOrEqual(MAX_DECOMPRESSED);
    const demo = await decodeDemo(gzipSync(body));
    expect(demo?.eventCodes.length).toBe(count);
    expect(demo?.eventCodes[count - 1]).toBe(1 + ((count - 1) % 7));
  });
});

describe("segment geometry against Godot 4.7.2", () => {
  // Geometry2D.segment_intersects_segment results, from a headless Godot run. The first group are
  // exact touches (shared endpoint, T-touch) where float64 arithmetic gives the opposite verdict.
  const cases: [number[], boolean][] = [
    [[16, 16, 0, 40, 16, 16, 16, 0], true], // shared endpoint
    [[24, 16, 0, 24, 0, 24, 32, 0], true], // shared endpoint
    [[40, 0, 24, 24, 24, 24, 32, 16], false], // shared endpoint
    [[8, 32, 16, 8, 8, 32, 24, 40], false], // shared endpoint
    [[24, 24, 32, 0, 24, 8, 24, 32], true], // T-touch: a lies on the other segment
    [[16, 16, 32, 24, 32, 8, 32, 32], true], // T-touch: b lies on the other segment
    [[40, 16, 24, 8, 24, 0, 24, 40], true], // T-touch
    [[0, 0, 10, 10, 10, 10, 20, 0], true],
    [[0, 0, 10, 10, 20, 0, 10, 10], true],
    [[0, 0, 10, 0, 10, 0, 10, 10], true],
    [[0, 0, 10, 0, 5, 0, 5, 10], true], // T-touch
    [[0, 0, 10, 0, 5, -10, 5, 0], true],
    [[0.1, 0.1, 0.7, 0.3, 0.4, 0.2, 0.4, 5.0], true],
    [[0.1, 0.3, 0.7, 0.9, 0.7, 0.9, 3.3, -1.1], true],
    [[0, 0, 10, 0, 5, 5, 5, -5], true],
    [[0, 0, 10, 0, 3, 1, 7, 1], false],
  ];
  for (const [c, want] of cases) {
    it(c.join(","), () => {
      expect(segmentsIntersect(vec([c[0], c[1]]), vec([c[2], c[3]]), vec([c[4], c[5]]), vec([c[6], c[7]]))).toBe(want);
    });
  }
});

const u16 = (n: number) => {
  const b = Buffer.alloc(2);
  b.writeUInt16LE(n);
  return b;
};
const u32 = (n: number) => {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n);
  return b;
};
