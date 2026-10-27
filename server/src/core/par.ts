// Pure par rule shared by the Worker and the CLI.
import { MAX_PAR, MIN_PAR } from "./level";

/** A moderator sets a version's par with one `par:<points>` GitHub label. */
const LABEL_PREFIX = "par:";
const POINTS = /^[1-9][0-9]*$/;

/** The label's points: undefined when there is no par label, null when there are several or the value is not a whole number from MIN_PAR to MAX_PAR. */
export function parLabel(labels: readonly string[]): number | null | undefined {
  const [value, ...rest] = labels.filter((label) => label.startsWith(LABEL_PREFIX)).map((label) => label.slice(LABEL_PREFIX.length));
  if (value === undefined) return undefined;
  const points = Number(value);
  return rest.length === 0 && POINTS.test(value) && points >= MIN_PAR && points <= MAX_PAR ? points : null;
}
