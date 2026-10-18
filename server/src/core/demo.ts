// Port of the decoder in scripts/demo.gd: same layout, limits and rejections, run on untrusted
// uploads. Keep the two in step. Asteroid positions are validated but not kept: no check needs them.

const FORMAT_VERSION = 1;
const MAGIC = [0x5a, 0x47, 0x58, 0x44]; // "ZGXD"
export const STEP = 1 / 30;
export const MAX_FRAMES = 18000;
export const MAX_BYTES = 524288;
export const MAX_DECOMPRESSED = 8 * 1024 * 1024;
const MAX_ALIVE = 1024;
const MAX_ASTEROID_FRAMES = 4_000_000;
const HEADER_BYTES = 42; // magic, version, 32-byte hash, frame count, truncated flag
const FRAME_MIN_BYTES = 17;
const EVENT_BYTES = 7;
const POSITION_SCALE = 8;
const ROTATION_SCALE = 1000;
const FUEL_SCALE = 10;

export const Event = { PICKUP_TAKEN: 1, PLANET_SHATTERED: 2, SHIP_LOST: 3, GOAL_REACHED: 4, ASTEROID_SPAWNED: 5, ASTEROID_REMOVED: 6, CLOCK_STARTED: 7 } as const;

const DELTA = 0;
const ABSOLUTE = 1;
const REMOVED = 2;

export interface DemoEvent {
  frame: number;
  code: number;
}

export interface Demo {
  levelSha256: string;
  truncated: boolean;
  frames: number;
  ship: Int32Array; // per frame: x, y, rotation, flags, fuel, hull, as stored
  events: DemoEvent[];
}

export interface ShipSample {
  x: number;
  y: number;
  rotation: number;
  firing: boolean;
  fuel: number;
  hull: number;
}

export function shipAt(demo: Demo, frame: number): ShipSample {
  const i = frame * 6;
  const s = demo.ship;
  return {
    x: s[i] / POSITION_SCALE,
    y: s[i + 1] / POSITION_SCALE,
    rotation: s[i + 2] / ROTATION_SCALE,
    firing: (s[i + 3] & 1) !== 0,
    fuel: s[i + 4] / FUEL_SCALE,
    hull: s[i + 5] / FUEL_SCALE,
  };
}

/** Null when the output would pass MAX_DECOMPRESSED, so a gzip bomb is never buffered. */
async function gunzip(bytes: Uint8Array): Promise<Uint8Array | null> {
  const reader = new Blob([bytes as Uint8Array<ArrayBuffer>]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > MAX_DECOMPRESSED) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
  } catch {
    return null;
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

/** Null for anything malformed, oversized, truncated, or of another format version. */
export async function decodeDemo(bytes: Uint8Array): Promise<Demo | null> {
  if (bytes.length > MAX_BYTES || bytes.length < 2 || bytes[0] !== 0x1f || bytes[1] !== 0x8b) return null;
  const raw = await gunzip(bytes);
  if (raw === null || raw.length < HEADER_BYTES || MAGIC.some((b, i) => raw[i] !== b) || raw[4] !== FORMAT_VERSION) return null;
  const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
  const levelSha256 = Array.from(raw.subarray(5, 37), (b) => b.toString(16).padStart(2, "0")).join("");
  const frames = view.getUint32(37, true);
  const truncated = raw[41] !== 0;
  if (frames > MAX_FRAMES) return null;

  let pos = HEADER_BYTES;
  const left = () => raw.length - pos;
  const ship = new Int32Array(frames * 6);
  const alive = new Set<number>();
  let asteroidFrames = 0;
  for (let f = 0; f < frames; f++) {
    if (left() < FRAME_MIN_BYTES) return null;
    ship.set([view.getInt32(pos, true), view.getInt32(pos + 4, true), view.getInt16(pos + 8, true), raw[pos + 10], view.getUint16(pos + 11, true), view.getUint16(pos + 13, true)], f * 6);
    const entries = view.getUint16(pos + 15, true);
    pos += FRAME_MIN_BYTES;
    for (let n = 0; n < entries; n++) {
      if (left() < 3) return null;
      const id = view.getUint16(pos, true);
      const flag = raw[pos + 2];
      pos += 3;
      if (flag === REMOVED && alive.delete(id)) continue;
      if (flag === ABSOLUTE && left() >= 10) {
        alive.add(id);
        pos += 10;
      } else if (flag === DELTA && alive.has(id) && left() >= 6) {
        pos += 6;
      } else {
        return null;
      }
      if (alive.size > MAX_ALIVE) return null;
    }
    asteroidFrames += alive.size;
    if (asteroidFrames > MAX_ASTEROID_FRAMES) return null;
  }
  if (left() < 4) return null;
  const eventCount = view.getUint32(pos, true);
  pos += 4;
  if (left() !== eventCount * EVENT_BYTES) return null;
  const events: DemoEvent[] = [];
  for (let n = 0; n < eventCount; n++, pos += EVENT_BYTES) {
    const frame = view.getUint32(pos, true);
    const code = raw[pos + 4];
    if (frame > frames || code < Event.PICKUP_TAKEN || code > Event.CLOCK_STARTED) return null;
    events.push({ frame, code });
  }
  return { levelSha256, truncated, frames, ship, events };
}
