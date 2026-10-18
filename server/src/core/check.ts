// Port of scripts/demo_check.gd: same rules, order and error wording, run on untrusted uploads.
// Keep the two in step. The level hash is passed in (the server hashes the stored file bytes).

import { Event, STEP, shipAt, type Demo, type ShipSample } from "./demo";
import { BARRIER_THICKNESS, GOAL_RADIUS, SHIP_RADIUS, UNLIMITED, bodyValue, closestOnSegment, dist, vec, type Obj, type Vec } from "./level";

const TUNNEL_LIMIT = 1200; // scenes/ship.gd
const MAX_FUEL = 100; // scenes/ship.gd
const MAX_HEALTH = 100; // scenes/ship.gd
const BASE_POINTS = 1000; // scripts/progress.gd
const MIN_POINTS = 100;
const POINTS_FUEL = 15; // Tuning.DEFAULTS: scoring never follows the live tuning
const POINTS_HULL = 3;
const POINTS_PER_SECOND = 2;

const START_TOLERANCE = 2;
const SPEED_MARGIN = 1.1;
const CLAIM_TOLERANCE = 0.5;
const SECONDS_TOLERANCE = 2 * STEP;
const POINTS_TOLERANCE = 2;
const CLOCK_TOLERANCE = 1;
const CONTACT_MARGIN = 2;
const RED_CONTACT = BARRIER_THICKNESS / 2 + SHIP_RADIUS - CONTACT_MARGIN;
const CMP_EPSILON = 0.00001; // Godot's, used by its segment routines

export interface Claim {
  points: number;
  fuel: number;
  hull: number;
  seconds: number;
}

interface Wall {
  kind: string;
  a: Vec;
  b: Vec;
  min: Vec; // bounding box grown by RED_CONTACT
  max: Vec;
}

const pos = (s: ShipSample): Vec => [s.x, s.y];
const isUnlimited = (v: unknown) => v === UNLIMITED;
// GDScript's roundi: half away from zero.
const roundi = (v: number) => Math.sign(v) * Math.floor(Math.abs(v) + 0.5);

/** Every rule the demo breaks; empty when it passes. With no claim the claim rule is skipped. */
export function checkDemo(level: unknown, levelSha256: string, demo: Demo, claim?: Claim): string[] {
  const lv = level as Obj;
  const ship = lv.ship as Obj;
  const errors: string[] = [];
  if (demo.truncated) errors.push("the demo is truncated");
  if (demo.levelSha256 !== levelSha256) errors.push("the demo was recorded on a different level");
  const count = demo.frames;
  if (count === 0) {
    errors.push("the demo has no frames");
    return errors;
  }
  const goal = vec((lv.goal as Obj).position);
  if (dist(pos(shipAt(demo, 0)), vec(ship.position)) > START_TOLERANCE) {
    errors.push("frame 0: the ship does not start at the level's start");
  }
  const last = shipAt(demo, count - 1);
  if (dist(pos(last), goal) > GOAL_RADIUS + SHIP_RADIUS) errors.push(`frame ${count - 1}: the ship is not inside the goal`);
  const events = demo.events;
  const end = events[events.length - 1];
  if (end === undefined || end.code !== Event.GOAL_REACHED || end.frame !== count) errors.push("the demo does not end with the goal event");

  // Hostile input must stay cheap: each rule reports its first failing frame only, and a wall is
  // tested only against steps whose bounding box comes near it.
  const maxStep = TUNNEL_LIMIT * SPEED_MARGIN * STEP;
  const walls = wallSegments(lv);
  const hazards = ((lv.bodies ?? []) as Obj[]).filter((b) => b.kind !== "planet");
  const fuelLimited = !isUnlimited(ship.fuel ?? MAX_FUEL);
  const failed: Record<string, true> = {};
  let firstThrust = -1;
  for (let f = 0; f < count; f++) {
    const now = shipAt(demo, f);
    if (firstThrust < 0 && now.firing) firstThrust = f;
    const before = shipAt(demo, Math.max(f - 1, 0));
    const p = pos(now);
    const q = pos(before);
    const lowX = Math.min(p[0], q[0]);
    const highX = Math.max(p[0], q[0]);
    const lowY = Math.min(p[1], q[1]);
    const highY = Math.max(p[1], q[1]);
    for (const wall of walls) {
      // Godot's Rect2.intersects: touching edges do not count.
      if (!(wall.min[0] < highX && wall.max[0] > lowX && wall.min[1] < highY && wall.max[1] > lowY)) continue;
      if (!failed.red && wall.kind === "red" && segmentGap(q, p, wall.a, wall.b) < RED_CONTACT) {
        failed.red = true;
        errors.push(`frame ${f}: the ship touched a red wall`);
      }
      if (f > 0 && !failed.crossed && segmentsIntersect(q, p, wall.a, wall.b)) {
        failed.crossed = true;
        errors.push(`frame ${f}: the ship crossed a wall`);
      }
    }
    for (const body of hazards) {
      if (failed.hazard) break;
      // The whole step, so a fast frame cannot hop over the body.
      const centre = vec(body.position);
      if (dist(closestOnSegment(centre, q, p), centre) < bodyValue(body, "radius") + SHIP_RADIUS - CONTACT_MARGIN) {
        failed.hazard = true;
        errors.push(`frame ${f}: the ship hit a ${(body.kind as string).replaceAll("_", " ")}`);
      }
    }
    if (f === 0) continue;
    const moved = dist(p, q);
    if (moved > maxStep && !failed.speed) {
      failed.speed = true;
      errors.push(`frame ${f}: the ship moved ${Math.trunc(moved)} px in one frame`);
    }
    if (fuelLimited && now.fuel > before.fuel && !failed.fuel) {
      failed.fuel = true;
      errors.push(`frame ${f}: fuel rose from ${before.fuel.toFixed(1)} to ${now.fuel.toFixed(1)}`);
    }
  }
  const clocks = events.filter((e) => e.code === Event.CLOCK_STARTED);
  if (clocks.length > 1) {
    errors.push(`the demo has ${clocks.length} clock events`);
  } else if (clocks.length === 1 && firstThrust < 0) {
    errors.push("the clock started but the ship never fired");
  } else if (clocks.length === 0 && firstThrust >= 0) {
    errors.push(`the ship fired at frame ${firstThrust} but the clock never started`);
  } else if (clocks.length === 1 && Math.abs(clocks[0].frame - firstThrust) > CLOCK_TOLERANCE) {
    errors.push(`the clock started at frame ${clocks[0].frame}, the ship first fired at frame ${firstThrust}`);
  }

  if (claim) {
    const clock = clockSeconds(demo);
    if (Math.abs(claim.seconds - clock) > SECONDS_TOLERANCE) errors.push(`claimed ${claim.seconds.toFixed(2)} seconds, the run took ${clock.toFixed(2)}`);
    if (Math.abs(claim.fuel - last.fuel) > CLAIM_TOLERANCE) errors.push(`claimed fuel ${claim.fuel.toFixed(1)}, the demo ends with ${last.fuel.toFixed(1)}`);
    if (Math.abs(claim.hull - last.hull) > CLAIM_TOLERANCE) errors.push(`claimed hull ${claim.hull.toFixed(1)}, the demo ends with ${last.hull.toFixed(1)}`);
    const points = pointsFor(claim.fuel, claim.hull, claim.seconds);
    // GDScript's absi truncates a float argument.
    if (Math.abs(Math.trunc(claim.points - points)) > POINTS_TOLERANCE) errors.push(`claimed ${Math.trunc(claim.points)} points, the claim is worth ${points}`);
  }
  return errors;
}

/** What the demo is worth, by the default weights. An unlimited tank scores nothing. */
export function scoreDemo(level: unknown, demo: Demo): { points: number; fuel: number; hull: number; seconds: number } {
  const ship = (level as Obj).ship as Obj;
  const last = demo.frames > 0 ? shipAt(demo, demo.frames - 1) : null;
  const fuel = isUnlimited(ship.fuel ?? MAX_FUEL) ? 0 : (last?.fuel ?? 0);
  const hull = isUnlimited(ship.hull ?? MAX_HEALTH) ? 0 : (last?.hull ?? 0);
  const seconds = clockSeconds(demo);
  return { points: pointsFor(fuel, hull, seconds), fuel, hull, seconds };
}

// Order matters: the sum, then the rounding, then the floor.
const pointsFor = (fuel: number, hull: number, seconds: number) =>
  Math.max(MIN_POINTS, roundi(BASE_POINTS + fuel * POINTS_FUEL + hull * POINTS_HULL - seconds * POINTS_PER_SECOND));

/** Seconds from the clock-started event to the last frame; 0 when the clock never started. */
function clockSeconds(demo: Demo): number {
  const clock = demo.events.find((e) => e.code === Event.CLOCK_STARTED);
  return clock ? (demo.frames - clock.frame) * STEP : 0;
}

// Geometry2D.segment_intersects_segment
function segmentsIntersect(a: Vec, b: Vec, c: Vec, d: Vec): boolean {
  const bx = b[0] - a[0];
  const by = b[1] - a[1];
  const len = bx * bx + by * by;
  if (len <= 0) return false;
  const nx = bx / len;
  const ny = by / len;
  const cx = c[0] - a[0];
  const cy = c[1] - a[1];
  const dx = d[0] - a[0];
  const dy = d[1] - a[1];
  const cX = cx * nx + cy * ny;
  const cY = cy * nx - cx * ny;
  const dX = dx * nx + dy * ny;
  const dY = dy * nx - dx * ny;
  if ((cY < -CMP_EPSILON && dY < -CMP_EPSILON) || (cY > CMP_EPSILON && dY > CMP_EPSILON)) return false;
  // Parallel or colinear (Math::is_equal_approx).
  if (cY === dY || Math.abs(cY - dY) < Math.max(CMP_EPSILON * Math.abs(cY), CMP_EPSILON)) return false;
  const along = dX + ((cX - dX) * dY) / (dY - cY);
  return along >= 0 && along <= 1;
}

// The least distance between segments a-b and c-d (Geometry2D.get_closest_points_between_segments).
function segmentGap(p1: Vec, q1: Vec, p2: Vec, q2: Vec): number {
  const d1: Vec = [q1[0] - p1[0], q1[1] - p1[1]];
  const d2: Vec = [q2[0] - p2[0], q2[1] - p2[1]];
  const r: Vec = [p1[0] - p2[0], p1[1] - p2[1]];
  const a = d1[0] * d1[0] + d1[1] * d1[1];
  const e = d2[0] * d2[0] + d2[1] * d2[1];
  const f = d2[0] * r[0] + d2[1] * r[1];
  const clamp = (v: number) => Math.min(Math.max(v, 0), 1);
  let s: number;
  let t: number;
  if (a <= CMP_EPSILON && e <= CMP_EPSILON) return dist(p1, p2);
  if (a <= CMP_EPSILON) {
    s = 0;
    t = clamp(f / e);
  } else {
    const c = d1[0] * r[0] + d1[1] * r[1];
    if (e <= CMP_EPSILON) {
      t = 0;
      s = clamp(-c / a);
    } else {
      const b = d1[0] * d2[0] + d1[1] * d2[1];
      const denom = a * e - b * b;
      s = denom !== 0 ? clamp((b * f - c * e) / denom) : 0;
      t = (b * s + f) / e;
      if (t < 0) {
        t = 0;
        s = clamp(-c / a);
      } else if (t > 1) {
        t = 1;
        s = clamp((b - c) / a);
      }
    }
  }
  return dist([p1[0] + d1[0] * s, p1[1] + d1[1] * s], [p2[0] + d2[0] * t, p2[1] + d2[1] * t]);
}

// Every wall as separate segments; a closed wall includes the last point back to the first.
function wallSegments(level: Obj): Wall[] {
  const out: Wall[] = [];
  for (const wall of (level.walls ?? []) as Obj[]) {
    const points = wall.points as unknown[];
    const n = wall.closed ? points.length : points.length - 1;
    for (let i = 0; i < n; i++) {
      const a = vec(points[i]);
      const b = vec(points[(i + 1) % points.length]);
      out.push({
        kind: wall.kind as string,
        a,
        b,
        min: [Math.min(a[0], b[0]) - RED_CONTACT, Math.min(a[1], b[1]) - RED_CONTACT],
        max: [Math.max(a[0], b[0]) + RED_CONTACT, Math.max(a[1], b[1]) + RED_CONTACT],
      });
    }
  }
  return out;
}
