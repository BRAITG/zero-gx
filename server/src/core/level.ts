// Port of scripts/level_format.gd `validate`: same rules, limits and error wording, so the
// community server accepts exactly what the game's editor produces. Keep the two in step.

const FORMAT = "zero-gx-level";
const VERSION = 1;
export const UNLIMITED = "unlimited";
const TAU = Math.PI * 2;

const WALL_KINDS = ["blue", "orange", "red"];
const BODY_KINDS = ["planet", "black_hole", "star"];
const PICKUP_KINDS = ["thrust_up", "thrust_down", "boost"];

export const MAX_LEVEL_BYTES = 65536;
const MAX_COORD = 50000;
const MAX_WALLS = 300;
const MAX_WALL_POINTS = 64;
const MAX_BODIES = 32;
const MAX_ASTEROIDS = 150;
const MAX_PICKUPS = 50;
const MAX_TOUR = 12;
const MAX_ROUTE = 64;
const MAX_TITLE = 40;
const MAX_TEXT = 200;
const MIN_PAR = 100; // Progress.MIN_POINTS in scripts/progress.gd
const TANK_RANGE: Range = [1, 1000]; // fuel and hull, unless unlimited
const BODY_RANGES: Record<string, Range> = {
  radius: [8, 3000],
  strength: [0, 6000000], // covers the heaviest, smallest black hole
  reach: [0, 10000],
  health: [1, 10000],
};
// Per-kind limits, independent of each other; total_pull is the pull at 1000 px (like mass).
// Black holes overlap stars in mass but always out-pull them at the surface.
const KIND_LIMITS: Record<string, Record<string, Range>> = {
  planet: { radius: [32, 240], total_pull: [0, 100], reach: [0, 1500] },
  star: { radius: [600, 3000], total_pull: [150, 5000], reach: [0, 8000] },
  black_hole: { radius: [32, 64], total_pull: [60, 6000], reach: [0, 1500] },
};
// GravityBody.PRESETS in scenes/gravity_body.gd: [radius, strength, reach].
const PRESETS: Record<string, Record<string, number>> = {
  planet: { radius: 64, strength: 3200, reach: 450 },
  black_hole: { radius: 64, strength: 16000, reach: 800 },
  star: { radius: 600, strength: 3000, reach: 3000 },
};
export const SHIP_RADIUS = 16; // scenes/ship.gd
export const BARRIER_THICKNESS = 16; // scenes/barrier.gd
export const GOAL_RADIUS = 80; // scenes/goal.gd

type Range = [number, number];
export type Obj = Record<string, unknown>;

const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const isNum = (v: unknown): v is number => typeof v === "number";
// Dictionary.get(key, default): only an absent key falls back, an explicit null does not.
const get = (o: Obj, key: string, fallback: unknown = null): unknown => (key in o ? o[key] : fallback);
// GDScript's "%s" of a float: 15 significant digits, whole numbers keep ".0".
const fmt = (n: number): string => {
  const s = String(Number(n.toPrecision(15)));
  return /^-?\d+$/.test(s) ? `${s}.0` : s;
};

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes as Uint8Array<ArrayBuffer>));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function validateLevel(data: unknown): string[] {
  const errors: string[] = [];
  const bytes = new TextEncoder().encode(JSON.stringify(data) ?? "").length;
  if (bytes > MAX_LEVEL_BYTES) errors.push(`level is larger than ${MAX_LEVEL_BYTES} bytes`);
  const d: Obj = isObj(data) ? data : {};
  const version = get(d, "version");
  if (d.format !== FORMAT || !isNum(version) || Math.trunc(version) !== VERSION) {
    errors.push(`not a ${FORMAT} version ${VERSION} file`);
    return errors;
  }
  const title = get(d, "title");
  if (typeof title !== "string" || [...title].length < 1 || [...title].length > MAX_TITLE) {
    errors.push(`title must be 1-${MAX_TITLE} characters`);
  }
  text(get(d, "hint", ""), "hint", errors);
  if ("par" in d && (!Number.isInteger(d.par) || (d.par as number) < MIN_PAR)) {
    errors.push(`par must be a whole number of at least ${MIN_PAR} points`);
  }
  const ship = get(d, "ship");
  if (!isObj(ship)) {
    errors.push("missing ship");
    return errors;
  }
  point(get(ship, "position"), "ship position", errors);
  point(get(ship, "velocity", [0, 0]), "ship velocity", errors);
  number(get(ship, "rotation", 0), -TAU, TAU, "ship rotation", errors);
  for (const tank of ["fuel", "hull"]) {
    const value = get(ship, tank, 100);
    if (value !== UNLIMITED) number(value, TANK_RANGE[0], TANK_RANGE[1], `ship ${tank}`, errors);
  }
  const goal = get(d, "goal");
  if (!isObj(goal)) errors.push("missing goal");
  else point(get(goal, "position"), "goal position", errors);

  const walls = list(d, "walls", MAX_WALLS, errors);
  walls.forEach((wall, i) => {
    if (!isObj(wall) || !WALL_KINDS.includes(get(wall, "kind") as string)) {
      errors.push(`wall ${i}: unknown kind`);
      return;
    }
    const points = get(wall, "points");
    if (!Array.isArray(points) || points.length < 2 || points.length > MAX_WALL_POINTS) {
      errors.push(`wall ${i}: needs 2-${MAX_WALL_POINTS} points`);
      return;
    }
    for (const p of points) point(p, `wall ${i} point`, errors);
  });

  const bodies = list(d, "bodies", MAX_BODIES, errors);
  bodies.forEach((body, i) => {
    if (!isObj(body) || !BODY_KINDS.includes(get(body, "kind") as string)) {
      errors.push(`body ${i}: unknown kind`);
      return;
    }
    const before = errors.length;
    point(get(body, "position"), `body ${i} position`, errors);
    for (const [key, [low, high]] of Object.entries(BODY_RANGES)) {
      if (key in body) number(body[key], low, high, `body ${i} ${key}`, errors);
    }
    if (errors.length === before) checkKindLimits(i, body, errors); // only well-formed numbers can be compared
  });

  const rocks = list(d, "asteroids", MAX_ASTEROIDS, errors);
  rocks.forEach((rock, i) => {
    if (!isObj(rock)) {
      errors.push(`asteroid ${i}: not an object`);
      return;
    }
    point(get(rock, "position"), `asteroid ${i} position`, errors);
    point(get(rock, "velocity", [0, 0]), `asteroid ${i} velocity`, errors);
    const orbit = get(rock, "orbit");
    if (orbit !== null) {
      const index = isObj(orbit) ? get(orbit, "body") : null;
      if (!isNum(index) || Math.trunc(index) < 0 || Math.trunc(index) >= bodies.length) {
        errors.push(`asteroid ${i}: orbit names no body`);
      }
    }
  });

  const pickups = list(d, "pickups", MAX_PICKUPS, errors);
  pickups.forEach((pickup, i) => {
    if (!isObj(pickup) || !PICKUP_KINDS.includes(get(pickup, "kind") as string)) {
      errors.push(`pickup ${i}: unknown kind`);
      return;
    }
    point(get(pickup, "position"), `pickup ${i} position`, errors);
  });

  const tour = list(d, "tour", MAX_TOUR, errors);
  tour.forEach((stop, i) => {
    if (!isObj(stop)) {
      errors.push(`tour stop ${i}: not an object`);
      return;
    }
    point(get(stop, "position"), `tour stop ${i} position`, errors);
    text(get(stop, "text", ""), `tour stop ${i} text`, errors);
  });

  const route = get(d, "route");
  if (route !== null) {
    const points = isObj(route) ? get(route, "points") : null;
    if (!Array.isArray(points) || points.length > MAX_ROUTE) {
      errors.push(`route needs up to ${MAX_ROUTE} points`);
    } else {
      for (const p of points) point(p, "route point", errors);
    }
  }
  if (errors.length === 0) checkStart(d, errors);
  return errors;
}

export function bodyValue(body: Obj, key: string): number {
  return get(body, key, PRESETS[body.kind as string][key]) as number;
}

function checkKindLimits(i: number, body: Obj, errors: string[]): void {
  const kind = body.kind as string;
  for (const [key, [low, high]] of Object.entries(KIND_LIMITS[kind])) {
    const value = key === "total_pull" ? bodyValue(body, "strength") * (bodyValue(body, "radius") / 1000) ** 2 : bodyValue(body, key);
    if (value < low - 0.001 || value > high + 0.001) {
      errors.push(`body ${i}: a ${kind.replaceAll("_", " ")}'s ${key.replaceAll("_", " ")} must be ${fmt(low)} to ${fmt(high)}`);
    }
  }
}

// Godot's Vector2 is float32: every operation is rounded so thresholds compare as in the game.
export type Vec = [number, number];
export const f32 = Math.fround;
export const vec = (v: unknown): Vec => [f32((v as number[])[0]), f32((v as number[])[1])];
export const dist = (a: Vec, b: Vec): number => {
  const dx = f32(a[0] - b[0]);
  const dy = f32(a[1] - b[1]);
  return f32(Math.sqrt(f32(f32(dx * dx) + f32(dy * dy))));
};

// Geometry2D.get_closest_point_to_segment
export function closestOnSegment(s: Vec, a: Vec, b: Vec): Vec {
  const n: Vec = [f32(b[0] - a[0]), f32(b[1] - a[1])];
  const l2 = f32(f32(n[0] * n[0]) + f32(n[1] * n[1]));
  if (l2 < f32(1e-20)) return a;
  const t = f32(f32(f32(n[0] * f32(s[0] - a[0])) + f32(n[1] * f32(s[1] - a[1]))) / l2);
  if (t <= 0) return a;
  if (t >= 1) return b;
  return [f32(a[0] + f32(n[0] * t)), f32(a[1] + f32(n[1] * t))];
}

function checkStart(d: Obj, errors: string[]): void {
  const start = vec((d.ship as Obj).position);
  const clearance = SHIP_RADIUS + BARRIER_THICKNESS / 2;
  (get(d, "walls", []) as Obj[]).forEach((wall, i) => {
    const points = wall.points as unknown[];
    for (let k = 0; k < points.length - 1; k++) {
      if (dist(closestOnSegment(start, vec(points[k]), vec(points[k + 1])), start) < clearance) {
        errors.push(`the ship starts inside wall ${i}`);
      }
    }
  });
  (get(d, "bodies", []) as Obj[]).forEach((body, i) => {
    if (dist(vec(body.position), start) < bodyValue(body, "radius") + SHIP_RADIUS) {
      errors.push(`the ship starts inside body ${i}`);
    }
  });
  if (dist(vec((d.goal as Obj).position), start) < GOAL_RADIUS + SHIP_RADIUS) {
    errors.push("the ship starts inside the goal");
  }
}

function list(d: Obj, key: string, limit: number, errors: string[]): unknown[] {
  const value = get(d, key, []);
  if (!Array.isArray(value)) {
    errors.push(`${key} must be a list`);
    return [];
  }
  if (value.length > limit) {
    errors.push(`more than ${limit} ${key}`);
    return [];
  }
  return value;
}

function point(value: unknown, what: string, errors: string[]): void {
  if (!Array.isArray(value) || value.length !== 2) {
    errors.push(`${what} must be [x, y]`);
    return;
  }
  for (const c of value) number(c, -MAX_COORD, MAX_COORD, what, errors);
}

function number(value: unknown, low: number, high: number, what: string, errors: string[]): void {
  if (!isNum(value) || !Number.isFinite(value) || value < low || value > high) {
    errors.push(`${what} must be a number from ${fmt(low)} to ${fmt(high)}`);
  }
}

function text(value: unknown, what: string, errors: string[]): void {
  if (typeof value !== "string" || [...value].length > MAX_TEXT) {
    errors.push(`${what} must be text up to ${MAX_TEXT} characters`);
  }
}
