// Pure difficulty rules shared by the Worker and the CLI. No runtime imports: this module must run in both.

export type Difficulty = "easy" | "normal" | "hard" | "expert";

/** The labels, easiest first. A Record rather than a Set, like the other fixed maps here; `Object.hasOwn` keeps `constructor` out. */
const LABELS: Record<Difficulty, true> = { easy: true, normal: true, hard: true, expert: true };
const SCALE = Object.keys(LABELS) as Difficulty[];

/** A community label needs at least this many voters. */
const MIN_VOTERS = 5;
/** A moderator labels a version with exactly one `difficulty:<label>` GitHub label. */
const LABEL_PREFIX = "difficulty:";

export function isDifficulty(value: unknown): value is Difficulty {
  return typeof value === "string" && Object.hasOwn(LABELS, value);
}

/** The version's reviewed label: the one recognised `difficulty:<label>` among `labels`, else null (none, or several). */
export function reviewedDifficulty(labels: readonly string[]): Difficulty | null {
  const found = labels.flatMap((label) => {
    const value = label.startsWith(LABEL_PREFIX) ? label.slice(LABEL_PREFIX.length) : "";
    return isDifficulty(value) ? [value] : [];
  });
  return found.length === 1 ? found[0]! : null;
}

/** The community label: the vote at the upper median, so with an even count the harder middle vote. Null below five voters. */
export function upperMedianDifficulty(counts: Record<Difficulty, number>): Difficulty | null {
  const total = SCALE.reduce((sum, label) => sum + counts[label], 0);
  if (total < MIN_VOTERS) return null;
  // The vote at index floor(total / 2) of the sorted votes: the first label whose running count passes that index.
  const index = Math.floor(total / 2);
  let seen = 0;
  for (const label of SCALE) {
    seen += counts[label];
    if (seen > index) return label;
  }
  return null;
}
