// The Rated difficulty: a skill-adjusted rating fitted from first-clear histories, plus each version's raw curve and counts.
// Pure, no runtime imports. Per-player skills exist only inside one call and are never returned by `rate`.

import { type Difficulty, SCALE } from "./difficulty";

export type Label = Difficulty;

/** One `play_summaries` row: a player's counted attempts on one version, up to their first clear. `level` is the stable level id. */
export interface History {
  player: string;
  level: string;
  sha256: string;
  attempts: number;
  cleared: boolean;
  lastMs: number;
}

/** One version's statistics and Rated label. The model fields are null whenever this run publishes no rating for the version. */
export interface VersionRating {
  sha256: string;
  starters: number;
  clears: number;
  /** Starters without a clear after 20 or more attempts. */
  notCleared20: number;
  /** Share of starters who cleared on or before attempt t, for t = 1…30. */
  curve: number[];
  beta: number | null;
  /** sd of θ_ref − β. */
  ratingSd: number | null;
  p10Low: number | null;
  p10High: number | null;
  rated: Label | null;
  /** The harder label of a two-band range. */
  ratedHigh: Label | null;
  /** Mean skill of all starters minus θ_ref. */
  audience: number | null;
}

type Published = { rated: Label | null; ratedHigh: Label | null };

// Product thresholds, to be retuned once real data exists.
/** The reference player's attempt budget: P10 is the chance to clear within this many attempts. */
const BUDGET = 10;
/** In the fit, a history past this many attempts counts as this many misses and no clear. */
const CAP = 30;
/** Lowest P10 of Easy, Normal and Hard; Expert is below the last. */
const BANDS = [0.8, 0.5, 0.2];
/** Gate 1: distinct starters in the fit. */
const MIN_FIT_STARTERS = 10;
/** Fewer reference players than this means no reference. */
const MIN_REFERENCE = 20;
const REFERENCE_LEVELS = 3;
const REFERENCE_DAYS = 180;
/** How far past a held label's outer edge the new interval may reach. */
const HOLD_POINTS = 0.02;
const MAX_PASSES = 200;
const TOLERANCE = 0.001;
const STEP_CLIP = 1;
const THETA_PRIOR = { mean: 0, sd: 1.5 };
const BETA_PRIOR = { mean: 2.6, sd: 2.5 };
const Z90 = 1.645;

const DAY_MS = 86_400_000;

/** A history as the fit counts it, by index. `cleared` is 1 or 0. */
interface Row {
  player: number;
  version: number;
  attempts: number;
  cleared: number;
}

interface Model {
  /** Every player's distinct levels, fit or not. */
  levels: Map<string, Set<string>>;
  /** Fit players and versions, each to its index. */
  players: Map<string, number>;
  versions: Map<string, number>;
  byPlayer: Row[][];
  byVersion: Row[][];
}

const sigmoid = (x: number) => 1 / (1 + Math.exp(-x));

/** The reference player's chance to clear within BUDGET attempts at skill-minus-difficulty `x`. */
const p10 = (x: number) => 1 - (1 - sigmoid(x)) ** BUDGET;

const row = (h: History, player: number, version: number): Row =>
  h.attempts > CAP ? { player, version, attempts: CAP, cleared: 0 } : { player, version, attempts: h.attempts, cleared: h.cleared ? 1 : 0 };

/** The fit's data. A player with attempts on only one level (versions of a level count as one) is left out. */
function model(histories: History[]): Model {
  const levels = new Map<string, Set<string>>();
  for (const h of histories) levels.set(h.player, (levels.get(h.player) ?? new Set<string>()).add(h.level));
  const m: Model = { levels, players: new Map(), versions: new Map(), byPlayer: [], byVersion: [] };
  for (const h of histories) {
    if (levels.get(h.player)!.size < 2) continue;
    if (!m.players.has(h.player)) {
      m.players.set(h.player, m.players.size);
      m.byPlayer.push([]);
    }
    if (!m.versions.has(h.sha256)) {
      m.versions.set(h.sha256, m.versions.size);
      m.byVersion.push([]);
    }
    const r = row(h, m.players.get(h.player)!, m.versions.get(h.sha256)!);
    m.byPlayer[r.player]!.push(r);
    m.byVersion[r.version]!.push(r);
  }
  return m;
}

/** One Newton step on a parameter's own 1-D negative log posterior, clipped to ±STEP_CLIP. `sign` is +1 for a skill, −1 for a difficulty. */
function step(value: number, prior: { mean: number; sd: number }, rows: Row[], sign: number, theta: Float64Array, beta: Float64Array): number {
  let slope = (value - prior.mean) / prior.sd ** 2;
  let curvature = 1 / prior.sd ** 2;
  for (const r of rows) {
    const p = sigmoid(theta[r.player]! - beta[r.version]!);
    slope -= sign * (r.cleared - r.attempts * p);
    curvature += r.attempts * p * (1 - p);
  }
  return Math.max(-STEP_CLIP, Math.min(STEP_CLIP, -slope / curvature));
}

/** Alternating clipped Newton passes from the cold start until no value moves more than TOLERANCE. */
function solve(m: Model, maxPasses: number): { theta: Float64Array; beta: Float64Array; converged: boolean } {
  const theta = new Float64Array(m.players.size).fill(THETA_PRIOR.mean);
  const beta = new Float64Array(m.versions.size).fill(BETA_PRIOR.mean);
  for (let pass = 0; pass < maxPasses; pass++) {
    let moved = 0;
    m.byPlayer.forEach((rows, i) => {
      const s = step(theta[i]!, THETA_PRIOR, rows, 1, theta, beta);
      theta[i]! += s;
      moved = Math.max(moved, Math.abs(s));
    });
    m.byVersion.forEach((rows, j) => {
      const s = step(beta[j]!, BETA_PRIOR, rows, -1, theta, beta);
      beta[j]! += s;
      moved = Math.max(moved, Math.abs(s));
    });
    if (moved <= TOLERANCE) return { theta, beta, converged: true };
  }
  return { theta, beta, converged: false };
}

/**
 * S⁻¹ by Gauss–Jordan without pivoting, consuming `s`; null when S is not positive definite.
 * S is symmetric, so its pivots are all positive exactly when it is positive definite.
 */
// shortcut: dense inverse of S; switch to a sparse solver past ~1,500 versions
function invert(s: Float64Array[]): Float64Array[] | null {
  const n = s.length;
  const inverse = Array.from({ length: n }, (_, k) => {
    const r = new Float64Array(n);
    r[k] = 1;
    return r;
  });
  for (let k = 0; k < n; k++) {
    const pivot = s[k]![k]!;
    if (!(pivot > 0)) return null;
    for (let c = 0; c < n; c++) {
      s[k]![c]! /= pivot;
      inverse[k]![c]! /= pivot;
    }
    for (let r = 0; r < n; r++) {
      const factor = s[r]![k]!;
      if (r === k || factor === 0) continue;
      for (let c = 0; c < n; c++) {
        s[r]![c]! -= factor * s[k]![c]!;
        inverse[r]![c]! -= factor * inverse[k]![c]!;
      }
    }
  }
  return inverse;
}

/**
 * Vⱼ = Var(θ_ref − βⱼ) for every fit version, from the joint Hessian at the fitted values through the Schur complement
 * S = H_ββ − H_βθ D⁻¹ H_θβ; null when S is not positive definite or some Vⱼ is not positive.
 */
function variance(m: Model, theta: Float64Array, beta: Float64Array, reference: number[]): Float64Array | null {
  const n = m.versions.size;
  // Each history adds h = a·p(1−p) to its player's and its version's diagonal and −h to their H_βθ entry.
  const terms = m.byPlayer.map((rows) =>
    rows.map((r) => {
      const p = sigmoid(theta[r.player]! - beta[r.version]!);
      return { version: r.version, h: r.attempts * p * (1 - p) };
    }),
  );
  const d = Float64Array.from(terms, (own) => own.reduce((sum, t) => sum + t.h, 1 / THETA_PRIOR.sd ** 2));
  const s = Array.from({ length: n }, (_, j) => {
    const r = new Float64Array(n);
    r[j] = 1 / BETA_PRIOR.sd ** 2;
    return r;
  });
  terms.forEach((own, i) => {
    for (const a of own) {
      s[a.version]![a.version]! += a.h;
      for (const b of own) s[a.version]![b.version]! -= (a.h * b.h) / d[i]!;
    }
  });
  // g = H_βθ D⁻¹ w, with w = 1/n on each reference player.
  const w = 1 / reference.length;
  const g = new Float64Array(n);
  let wdw = 0;
  for (const i of reference) {
    wdw += (w * w) / d[i]!;
    for (const t of terms[i]!) g[t.version]! -= (t.h * w) / d[i]!;
  }
  const sigma = invert(s);
  if (!sigma) return null;
  const sg = sigma.map((r) => r.reduce((sum, value, k) => sum + value * g[k]!, 0));
  const gsg = sg.reduce((sum, value, k) => sum + value * g[k]!, 0);
  const v = Float64Array.from(sigma, (r, j) => wdw + gsg + 2 * sg[j]! + r[j]!);
  return v.every((value) => value > 0) ? v : null;
}

/** A left-out player's skill from their own histories, every β held fixed. */
function skillWithBetaFixed(own: Row[], beta: Float64Array): number {
  const theta = new Float64Array(1).fill(THETA_PRIOR.mean);
  for (let pass = 0; pass < MAX_PASSES; pass++) {
    const s = step(theta[0]!, THETA_PRIOR, own, 1, theta, beta);
    theta[0]! += s;
    if (Math.abs(s) <= TOLERANCE) break;
  }
  return theta[0]!;
}

export function bandOf(p10: number): Label {
  const k = BANDS.findIndex((edge) => p10 >= edge);
  return SCALE[k === -1 ? BANDS.length : k]!;
}

/** The label to publish once both gates pass, per "Stability": the previous label while the interval overlaps it within HOLD_POINTS, else the gates' label. */
function publish(previous: Published | undefined, low: number, high: number, current: Published): Published {
  if (!previous?.rated) return current;
  const top = BANDS[SCALE.indexOf(previous.rated) - 1] ?? 1;
  const bottom = BANDS[SCALE.indexOf(previous.ratedHigh ?? previous.rated)] ?? 0;
  const holds = low <= top && high >= bottom && low >= bottom - HOLD_POINTS && high <= top + HOLD_POINTS;
  return holds ? { rated: previous.rated, ratedHigh: previous.ratedHigh } : current;
}

/** The fitted skills and difficulties, by player and sha256. Exported for tests. */
export function fit(histories: History[], options?: { maxPasses?: number }): { theta: Map<string, number>; beta: Map<string, number>; converged: boolean } {
  const m = model(histories);
  const { theta, beta, converged } = solve(m, options?.maxPasses ?? MAX_PASSES);
  return { theta: new Map([...m.players].map(([id, i]) => [id, theta[i]!])), beta: new Map([...m.versions].map(([sha, j]) => [sha, beta[j]!])), converged };
}

/** Var(θ_ref − βⱼ) for every fit version at the given values and reference players, or null as in `rate`. Exported for tests. */
export function variances(histories: History[], theta: Map<string, number>, beta: Map<string, number>, reference: string[]): Map<string, number> | null {
  const m = model(histories);
  const v = variance(
    m,
    Float64Array.from(m.players.keys(), (id) => theta.get(id)!),
    Float64Array.from(m.versions.keys(), (sha) => beta.get(sha)!),
    reference.map((id) => m.players.get(id)!),
  );
  return v && new Map([...m.versions.keys()].map((sha, j) => [sha, v[j]!]));
}

/**
 * Every version's statistics and Rated label. `previous` holds each sha256's label from the last run.
 * `fitted` is false when the fit did not converge or its uncertainty is unusable; the caller logs that. The raw statistics are filled regardless.
 */
export function rate(
  histories: History[],
  previous: Map<string, Published>,
  nowMs: number,
  options?: { maxPasses?: number },
): { versions: VersionRating[]; fitted: boolean } {
  const m = model(histories);
  const solved = solve(m, options?.maxPasses ?? MAX_PASSES);
  const latest = new Map<string, number>();
  for (const h of histories) latest.set(h.player, Math.max(latest.get(h.player) ?? -Infinity, h.lastMs));
  const since = nowMs - REFERENCE_DAYS * DAY_MS;
  const reference = [...m.players].flatMap(([id, i]) => (m.levels.get(id)!.size >= REFERENCE_LEVELS && latest.get(id)! >= since ? [i] : []));
  const hasReference = reference.length >= MIN_REFERENCE;
  const v = solved.converged && hasReference ? variance(m, solved.theta, solved.beta, reference) : null;
  const fitted = solved.converged && (!hasReference || v !== null);
  const thetaRef = v ? reference.reduce((sum, i) => sum + solved.theta[i]!, 0) / reference.length : null;

  // Skills of every starter, for the audience: fitted, or re-estimated with β fixed for players left out of the fit.
  const skill = new Map([...m.players].map(([id, i]) => [id, solved.theta[i]!]));
  if (thetaRef !== null) {
    const leftOut = new Map<string, Row[]>();
    for (const h of histories) {
      const j = m.versions.get(h.sha256);
      if (m.players.has(h.player) || j === undefined) continue;
      const own = leftOut.get(h.player) ?? [];
      own.push(row(h, 0, j));
      leftOut.set(h.player, own);
    }
    for (const [id, own] of leftOut) skill.set(id, skillWithBetaFixed(own, solved.beta));
  }

  const bySha = new Map<string, History[]>();
  for (const h of histories) {
    const starters = bySha.get(h.sha256) ?? [];
    starters.push(h);
    bySha.set(h.sha256, starters);
  }
  const versions = [...bySha].map(([sha256, starters]): VersionRating => {
    const stats = {
      sha256,
      starters: starters.length,
      clears: starters.filter((h) => h.cleared).length,
      notCleared20: starters.filter((h) => !h.cleared && h.attempts >= 20).length,
      curve: Array.from({ length: 30 }, (_, t) => starters.filter((h) => h.cleared && h.attempts <= t + 1).length / starters.length),
    };
    const estimating = { beta: null, ratingSd: null, p10Low: null, p10High: null, rated: null, ratedHigh: null, audience: null };
    const j = m.versions.get(sha256);
    if (!fitted || j === undefined) return { ...stats, ...estimating };
    const beta = solved.beta[j]!;
    if (thetaRef === null) return { ...stats, ...estimating, beta };
    const x = thetaRef - beta;
    const ratingSd = Math.sqrt(v![j]!);
    const p10Low = p10(x - Z90 * ratingSd);
    const p10High = p10(x + Z90 * ratingSd);
    const audience = starters.reduce((sum, h) => sum + skill.get(h.player)!, 0) / starters.length - thetaRef;
    // Gates: enough starters in the fit, and an interval within one band or two adjacent ones.
    const easier = SCALE.indexOf(bandOf(p10High));
    const harder = SCALE.indexOf(bandOf(p10Low));
    const gated = m.byVersion[j]!.length >= MIN_FIT_STARTERS && harder - easier <= 1;
    const current = { rated: SCALE[easier]!, ratedHigh: harder > easier ? SCALE[harder]! : null };
    const label = gated ? publish(previous.get(sha256), p10Low, p10High, current) : { rated: null, ratedHigh: null };
    return { ...stats, beta, ratingSd, p10Low, p10High, ...label, audience };
  });
  return { versions, fitted };
}
