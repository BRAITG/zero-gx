// Pure par rule shared by the Worker and the CLI. No runtime imports: this module must run in both.

/** A moderator sets a version's par with one `par:<points>` GitHub label. */
const LABEL_PREFIX = "par:";
const POINTS = /^[1-9][0-9]*$/;

/** The label's points: undefined when there is no par label, null when there are several or the value is not a positive whole number. */
export function parLabel(labels: readonly string[]): number | null | undefined {
  const [value, ...rest] = labels.filter((label) => label.startsWith(LABEL_PREFIX)).map((label) => label.slice(LABEL_PREFIX.length));
  if (value === undefined) return undefined;
  const points = Number(value);
  return rest.length === 0 && POINTS.test(value) && Number.isSafeInteger(points) ? points : null;
}
