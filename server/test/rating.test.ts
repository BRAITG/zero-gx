import { describe, expect, it } from "vitest";
import type { Difficulty } from "../src/core/difficulty";
import { bandOf, fit, type History, rate, variances, type VersionRating } from "../src/core/rating";

const NOW = Date.UTC(2026, 10, 14);
const sigmoid = (x: number) => 1 / (1 + Math.exp(-x));

/** One play summary; the version defaults to the level, the last report to now. */
const play = (player: string, level: string, attempts: number, cleared: boolean, sha256 = level, lastMs = NOW): History => ({ player, level, sha256, attempts, cleared, lastMs });

/** `count` players named `prefix0…`, each with the plays `plays` returns. */
const cohort = (prefix: string, count: number, plays: (name: string, index: number) => History[]): History[] =>
  Array.from({ length: count }, (_, index) => plays(`${prefix}${index}`, index)).flat();

const version = (result: { versions: VersionRating[] }, sha256: string) => result.versions.find((entry) => entry.sha256 === sha256)!;

// Test-side oracle, written from the spec independently of the module.

/** The fit's histories: players with one level dropped, histories past 30 attempts counted as 30 misses. */
function fitRows(histories: History[]): History[] {
  const levels = new Map<string, Set<string>>();
  for (const h of histories) levels.set(h.player, (levels.get(h.player) ?? new Set()).add(h.level));
  return histories.filter((h) => levels.get(h.player)!.size >= 2).map((h) => (h.attempts > 30 ? { ...h, attempts: 30, cleared: false } : h));
}

type Fitted = { theta: Map<string, number>; beta: Map<string, number> };

/** Each parameter's full Newton step at the fitted values: zero at the posterior mode. */
function modeSteps(histories: History[], fitted: Fitted): number[] {
  const slope = new Map<string, number>();
  const curve = new Map<string, number>();
  const add = (key: string, s: number, c: number) => {
    slope.set(key, (slope.get(key) ?? 0) + s);
    curve.set(key, (curve.get(key) ?? 0) + c);
  };
  for (const [id, value] of fitted.theta) add(`θ${id}`, value / 1.5 ** 2, 1 / 1.5 ** 2);
  for (const [sha, value] of fitted.beta) add(`β${sha}`, (value - 2.6) / 2.5 ** 2, 1 / 2.5 ** 2);
  for (const h of fitRows(histories)) {
    const p = sigmoid(fitted.theta.get(h.player)! - fitted.beta.get(h.sha256)!);
    const g = (h.cleared ? 1 : 0) - h.attempts * p;
    add(`θ${h.player}`, -g, h.attempts * p * (1 - p));
    add(`β${h.sha256}`, g, h.attempts * p * (1 - p));
  }
  return [...slope].map(([key, s]) => Math.abs(s / curve.get(key)!));
}

/** Inverse by Gauss–Jordan with partial pivoting. */
function invert(matrix: number[][]): number[][] {
  const n = matrix.length;
  const a = matrix.map((row, k) => [...row, ...Array.from({ length: n }, (_, l) => (k === l ? 1 : 0))]);
  for (let col = 0; col < n; col++) {
    let pivot = col;
    for (let row = col + 1; row < n; row++) if (Math.abs(a[row]![col]!) > Math.abs(a[pivot]![col]!)) pivot = row;
    [a[col], a[pivot]] = [a[pivot]!, a[col]!];
    const scale = a[col]![col]!;
    a[col] = a[col]!.map((value) => value / scale);
    for (let row = 0; row < n; row++) {
      if (row === col) continue;
      const factor = a[row]![col]!;
      a[row] = a[row]!.map((value, k) => value - factor * a[col]![k]!);
    }
  }
  return a.map((row) => row.slice(n));
}

/** Var(θ_ref − β) from the dense inverse of the full joint Hessian of the negative log posterior. */
function denseVariance(histories: History[], fitted: Fitted, reference: string[], sha256: string): number {
  const players = [...fitted.theta.keys()];
  const versions = [...fitted.beta.keys()];
  const n = players.length + versions.length;
  const hessian = Array.from({ length: n }, (_, k) => Array.from({ length: n }, (_, l) => (k !== l ? 0 : k < players.length ? 1 / 1.5 ** 2 : 1 / 2.5 ** 2)));
  for (const h of fitRows(histories)) {
    const i = players.indexOf(h.player);
    const j = players.length + versions.indexOf(h.sha256);
    const p = sigmoid(fitted.theta.get(h.player)! - fitted.beta.get(h.sha256)!);
    const w = h.attempts * p * (1 - p);
    hessian[i]![i]! += w;
    hessian[j]![j]! += w;
    hessian[i]![j]! -= w;
    hessian[j]![i]! -= w;
  }
  const inverse = invert(hessian);
  const u = new Array<number>(n).fill(0);
  for (const id of reference) u[players.indexOf(id)] = 1 / reference.length;
  u[players.length + versions.indexOf(sha256)] = -1;
  return u.reduce((sum, uk, k) => sum + uk * u.reduce((inner, ul, l) => inner + inverse[k]![l]! * ul, 0), 0);
}

/** Seeded uniform [0, 1) (mulberry32). */
function seeded(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

describe("fit", () => {
  it("clips one Newton step to ±1", () => {
    // Clears two levels at once: raw steps +3.248 on θ, then −2.776 on β.
    const quick = fit([play("p", "A", 1, true), play("p", "B", 1, true)], { maxPasses: 1 });
    expect(quick.converged).toBe(false);
    expect(quick.theta.get("p")).toBe(1);
    expect(quick.beta.get("A")).toBeCloseTo(1.6, 12);
    expect(quick.beta.get("B")).toBeCloseTo(1.6, 12);
    // Fails two levels once each: steps small enough to stay unclipped.
    const slow = fit([play("q", "A", 1, false), play("q", "B", 1, false)], { maxPasses: 1 });
    expect(slow.theta.get("q")).toBeCloseTo(-0.241253034, 8);
    expect(slow.beta.get("A")).toBeCloseTo(2.859954917, 8);
  });

  it("converges on a near-trivial level plus one 300-failure account that plays a second level", () => {
    const histories = [
      ...cohort("p", 20, (name) => [play(name, "easy", 1, true), play(name, "mid", 3, true)]),
      play("grinder", "easy", 300, false),
      play("grinder", "mid", 5, true),
    ];
    const fitted = fit(histories);
    expect(fitted.converged).toBe(true);
    expect(Math.max(...modeSteps(histories, fitted))).toBeLessThan(0.005);
    expect(fitted.beta.get("easy")!).toBeLessThan(fitted.beta.get("mid")!);
    expect(fitted.theta.get("grinder")!).toBeLessThan(fitted.theta.get("p0")!);
    for (const value of [...fitted.theta.values(), ...fitted.beta.values()]) expect(Number.isFinite(value)).toBe(true);
  });

  it("leaves out players with one level, counting versions of a level as one", () => {
    const histories = [play("two", "A", 1, true), play("two", "B", 2, true), play("versions", "A", 3, true, "A"), play("versions", "A", 4, true, "A2")];
    const fitted = fit(histories);
    expect([...fitted.theta.keys()]).toEqual(["two"]);
    expect([...fitted.beta.keys()]).toEqual(["A", "B"]);
  });
});

describe("variances", () => {
  it("V equals the dense inverse of the full joint Hessian", () => {
    const histories = [
      play("p1", "A", 1, true), play("p1", "B", 4, true), play("p1", "C", 12, false),
      play("p2", "A", 2, true), play("p2", "B", 7, false), play("p2", "C", 3, true),
      play("p3", "A", 1, true), play("p3", "C", 30, false),
      play("p4", "B", 2, true), play("p4", "C", 9, true),
      play("p5", "A", 5, false), play("p5", "B", 1, true),
      play("p6", "A", 40, true), play("p6", "C", 6, true),
    ];
    const fitted = fit(histories);
    expect(fitted.converged).toBe(true);
    const reference = ["p1", "p2", "p3", "p4"];
    const v = variances(histories, fitted.theta, fitted.beta, reference)!;
    for (const sha of ["A", "B", "C"]) expect(Math.abs(v.get(sha)! - denseVariance(histories, fitted, reference, sha))).toBeLessThan(1e-9);
  });

  it("coverage: the 90% interval of θ_ref − β covers the truth in 85–95% of simulated catalogues", () => {
    const rng = seeded(20261114);
    const normal = () => Math.sqrt(-2 * Math.log(1 - rng())) * Math.cos(2 * Math.PI * rng());
    // Truth drawn from the priors; 25 players each play 6–12 of 12 levels. With fewer histories per player the joint mode's
    // incidental-parameter bias (estimates lean easier) pulls coverage under 85%: 3–6 of 6 levels gives 83%.
    const levels = Array.from({ length: 12 }, (_, k) => `L${k}`);
    let covered = 0;
    let total = 0;
    for (let catalogue = 0; catalogue < 500; catalogue++) {
      const theta = Array.from({ length: 25 }, () => 1.5 * normal());
      const beta = new Map(levels.map((level) => [level, 2.6 + 2.5 * normal()]));
      const histories = theta.flatMap((skill, i) => {
        const order = [...levels].sort(() => rng() - 0.5);
        return order.slice(0, 6 + Math.floor(rng() * 7)).map((level) => {
          const patience = 1 + Math.floor(rng() * 40);
          let attempt = 1;
          while (attempt <= patience && rng() >= sigmoid(skill - beta.get(level)!)) attempt++;
          return attempt <= patience ? play(`p${i}`, level, attempt, true) : play(`p${i}`, level, patience, false);
        });
      });
      const fitted = fit(histories);
      expect(fitted.converged).toBe(true);
      const reference = theta.map((_, i) => `p${i}`);
      const v = variances(histories, fitted.theta, fitted.beta, reference)!;
      const thetaRef = reference.reduce((sum, id) => sum + fitted.theta.get(id)!, 0) / reference.length;
      const trueRef = theta.reduce((sum, skill) => sum + skill, 0) / theta.length;
      for (const [sha, b] of fitted.beta) {
        total++;
        if (Math.abs(thetaRef - b - (trueRef - beta.get(sha)!)) <= 1.645 * Math.sqrt(v.get(sha)!)) covered++;
      }
    }
    expect(covered / total).toBeGreaterThanOrEqual(0.85);
    expect(covered / total).toBeLessThanOrEqual(0.95);
  });
});

describe("bandOf", () => {
  it("bands P10 at 80, 50 and 20 percent", () => {
    expect([1, 0.8, 0.7999, 0.5, 0.4999, 0.2, 0.1999, 0].map(bandOf)).toEqual(["easy", "easy", "normal", "normal", "hard", "hard", "expert", "expert"]);
  });
});

describe("rate", () => {
  /** Twenty reference players clear L1–L3 on attempt 10; ten others, sharing no level with them, clear L4–L5 on attempt 15. */
  const fixtureA = [
    ...cohort("r", 20, (name) => ["L1", "L2", "L3"].map((level) => play(name, level, 10, true))),
    ...cohort("o", 10, (name) => ["L4", "L5"].map((level) => play(name, level, 15, true))),
  ];

  it("marks fitted=false and every version Estimating after MAX_PASSES without convergence", () => {
    const previous = new Map(["L1", "L2", "L3"].map((sha) => [sha, { rated: "normal" as Difficulty, ratedHigh: null }]));
    const result = rate(fixtureA, previous, NOW, { maxPasses: 1 });
    expect(result.fitted).toBe(false);
    expect(result.versions).toHaveLength(5);
    for (const entry of result.versions) {
      expect(entry).toMatchObject({ beta: null, ratingSd: null, p10Low: null, p10High: null, rated: null, ratedHigh: null, audience: null, clears: entry.starters });
      expect(entry.curve).toHaveLength(30);
    }
    expect(version(result, "L1").starters).toBe(20);
  });

  it("fixture (a): L1–L3 rate normal; L4–L5, unconnected to the reference, stay Estimating", () => {
    const result = rate(fixtureA, new Map(), NOW);
    expect(result.fitted).toBe(true);
    for (const sha of ["L1", "L2", "L3"]) expect(version(result, sha)).toMatchObject({ rated: "normal", ratedHigh: null });
    for (const sha of ["L4", "L5"]) {
      expect(version(result, sha)).toMatchObject({ starters: 10, rated: null, ratedHigh: null });
      expect(version(result, sha).p10High! - version(result, sha).p10Low!).toBeGreaterThan(0.3);
    }
  });

  it("censors histories over 30 attempts as 30 misses", () => {
    const histories = cohort("e", 60, (name) => [play(name, "A", 1, true), play(name, "B", 1, true), play(name, "C", 1, true), play(name, "T", 1000, true)]);
    const target = version(rate(histories, new Map(), NOW), "T");
    expect(target).toMatchObject({ starters: 60, clears: 60, rated: "expert", ratedHigh: null });
    expect(target.p10High!).toBeLessThan(0.025);
  });

  it("owner's caveat: newcomers who fail an easy level never make it Hard or Expert", () => {
    /** 24 reference players on anchors A–C; the first `established` of them also clear T at once; `newcomers` play only T and fail it `failures` times. */
    const catalogue = (established: number, newcomers: number, failures: number) => [
      ...cohort("r", 24, (name, i) => [play(name, "A", 2, true), play(name, "B", 4, true), play(name, "C", 6, true), ...(i < established ? [play(name, "T", 1, true)] : [])]),
      ...cohort("n", newcomers, (name) => [play(name, "T", failures, false)]),
    ];
    const alone = (newcomers: number, failures: number) => [...cohort("q", 10, (name) => [play(name, "T", 1, true)]), ...cohort("n", newcomers, (name) => [play(name, "T", failures, false)])];
    for (const newcomers of [15, 30, 100]) {
      for (const failures of [5, 10, 30]) {
        const results = [rate(alone(newcomers, failures), new Map(), NOW), rate(catalogue(6, newcomers, failures), new Map(), NOW), rate(catalogue(10, newcomers, failures), new Map(), NOW)];
        for (const result of results) {
          for (const entry of result.versions) {
            expect(["hard", "expert"]).not.toContain(entry.rated);
            expect(["hard", "expert"]).not.toContain(entry.ratedHigh);
          }
        }
        const [lonely, six, ten] = results.map((result) => version(result, "T"));
        expect(lonely).toMatchObject({ starters: 10 + newcomers, rated: null, ratedHigh: null, beta: null });
        expect(six).toMatchObject({ starters: 6 + newcomers, rated: null, ratedHigh: null });
        expect(ten).toMatchObject({ starters: 10 + newcomers, rated: "easy", ratedHigh: null });
        // The newcomers' re-estimated skills make the audience weaker than typical.
        expect(ten!.audience!).toBeLessThan(-0.5);
      }
    }
  });

  it("zero clears with 40 starters gives finite numbers and Expert or Estimating", () => {
    const histories = cohort("r", 40, (name, i) => [play(name, "A", 2, true), play(name, "B", 3, true), play(name, "Z", i % 2 ? 20 : 100, false)]);
    const result = rate(histories, new Map(), NOW);
    const zero = version(result, "Z");
    expect(zero).toMatchObject({ starters: 40, clears: 0, notCleared20: 40 });
    for (const value of [zero.beta, zero.ratingSd, zero.p10Low, zero.p10High, zero.audience]) expect(Number.isFinite(value)).toBe(true);
    expect(["expert", null]).toContain(zero.rated);
    for (const entry of result.versions) for (const value of Object.values(entry).flat()) if (typeof value === "number") expect(Number.isFinite(value)).toBe(true);
  });

  it("curve and counts include early quitters and one grinder", () => {
    const histories = [play("a", "V", 1, true), play("b", "V", 3, true), play("c", "V", 2, false), play("d", "V", 25, false), play("grinder", "V", 45, true)];
    const entry = version(rate(histories, new Map(), NOW), "V");
    expect(entry).toMatchObject({ starters: 5, clears: 3, notCleared20: 1, rated: null });
    expect(entry.curve).toEqual([0.2, 0.2, ...new Array<number>(28).fill(0.4)]);
    expect(entry.curve[29]!).toBeLessThan(entry.clears / entry.starters);
  });

  it("drops stale players from the reference", () => {
    const stale = NOW - 181 * 86_400_000;
    const histories = cohort("r", 20, (name, i) => ["L1", "L2", "L3"].map((level) => play(name, level, 10, true, level, i === 0 ? stale : NOW)));
    expect(version(rate(histories, new Map(), NOW), "L1")).toMatchObject({ ratingSd: null, rated: null, audience: null });
    expect(version(rate(histories, new Map(), stale + 1), "L1").rated).toBe("normal");
  });

  it("stability holds a label only while gates pass and the interval overlaps it within 2 points", () => {
    const SCALE: Difficulty[] = ["easy", "normal", "hard", "expert"];
    const EDGES = [0.8, 0.5, 0.2];
    /** 30 reference players on anchors A and B; on T the first `quick` clear at once and the rest at attempt `slow`. */
    const family = (quick: number, slow: number, starters = 30) =>
      cohort("r", 30, (name, i) => [play(name, "A", 2, true), play(name, "B", 5, true), ...(i < starters ? [play(name, "T", i < quick ? 1 : slow, true)] : [])]);
    const candidates = [];
    for (let quick = 0; quick <= 30; quick++) {
      for (let slow = 2; slow <= 20; slow++) {
        const target = version(rate(family(quick, slow), new Map(), NOW), "T");
        if (target.rated) candidates.push({ quick, slow, ...target, low: target.p10Low!, high: target.p10High! });
      }
    }
    const ranges = candidates.filter((c) => c.ratedHigh).map((c) => ({ ...c, edge: EDGES[SCALE.indexOf(c.rated!)]! }));
    // A range that barely reaches below the edge, and one that reaches well past it on both sides.
    const near = ranges.find((c) => c.edge - c.low <= 0.02 && c.high - c.edge > 0.02)!;
    const far = ranges.find((c) => c.edge - c.low > 0.02 && c.high - c.edge > 0.02)!;
    const single = candidates.find((c) => !c.ratedHigh && c.rated === "normal")!;
    expect(near).toBeDefined();
    expect(far).toBeDefined();
    expect(single).toBeDefined();

    const published = (quick: number, slow: number, rated: Difficulty, ratedHigh: Difficulty | null = null, starters = 30) => {
      const { rated: label, ratedHigh: high } = version(rate(family(quick, slow, starters), new Map([["T", { rated, ratedHigh }]]), NOW), "T");
      return [label, high];
    };
    // A single label is held while the interval reaches at most 2 points past its edge.
    expect(published(near.quick, near.slow, near.rated!)).toEqual([near.rated, null]);
    expect(published(near.quick, near.slow, near.ratedHigh!)).toEqual([near.rated, near.ratedHigh]);
    expect(published(far.quick, far.slow, far.rated!)).toEqual([far.rated, far.ratedHigh]);
    expect(published(far.quick, far.slow, far.ratedHigh!)).toEqual([far.rated, far.ratedHigh]);
    // A range is held while the interval stays within it; a label it no longer overlaps is not.
    expect(published(single.quick, single.slow, "normal", "hard")).toEqual(["normal", "hard"]);
    expect(published(single.quick, single.slow, "easy", "normal")).toEqual(["easy", "normal"]);
    expect(published(single.quick, single.slow, "expert")).toEqual(["normal", null]);
    // A gate failure removes a held label at once: nine starters in the fit.
    expect(published(near.quick, near.slow, near.rated!, null, 9)).toEqual([null, null]);
  });
});
