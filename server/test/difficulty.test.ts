import { describe, expect, it } from "vitest";
import { type Difficulty, isDifficulty, reviewedDifficulty, upperMedianDifficulty } from "../src/core/difficulty";

/** The vote counts of `labels`, zero for every label not given. */
const tally = (...labels: Difficulty[]): Record<Difficulty, number> => {
  const counts: Record<Difficulty, number> = { easy: 0, normal: 0, hard: 0, expert: 0 };
  for (const label of labels) counts[label] += 1;
  return counts;
};

describe("isDifficulty", () => {
  it("accepts the four wire values and nothing else", () => {
    for (const value of ["easy", "normal", "hard", "expert"]) expect(isDifficulty(value)).toBe(true);
    for (const value of ["Normal", "legendary", "", " hard", null, undefined, 1, "constructor", "toString", "__proto__"]) expect(isDifficulty(value)).toBe(false);
  });
});

describe("reviewedDifficulty", () => {
  it("reads exactly one recognised difficulty label and ignores unrelated labels", () => {
    expect(reviewedDifficulty(["difficulty:hard"])).toBe("hard");
    expect(reviewedDifficulty(["bug", "difficulty:expert", "good first issue"])).toBe("expert");
  });

  it("returns null for no difficulty label, an unrecognised one, or several", () => {
    expect(reviewedDifficulty([])).toBeNull();
    expect(reviewedDifficulty(["bug"])).toBeNull();
    expect(reviewedDifficulty(["hard"])).toBeNull(); // the label carries its prefix
    expect(reviewedDifficulty(["difficulty:legendary"])).toBeNull();
    expect(reviewedDifficulty(["difficulty:constructor"])).toBeNull();
    expect(reviewedDifficulty(["difficulty:easy", "difficulty:hard"])).toBeNull();
  });
});

describe("upperMedianDifficulty", () => {
  it("has no aggregate label below five voters", () => {
    expect(upperMedianDifficulty(tally())).toBeNull();
    expect(upperMedianDifficulty(tally("easy", "normal", "hard", "expert"))).toBeNull();
    expect(upperMedianDifficulty(tally("hard", "hard", "hard", "hard"))).toBeNull();
  });

  it("takes the middle label of five voters", () => {
    expect(upperMedianDifficulty(tally("easy", "normal", "normal", "hard", "expert"))).toBe("normal");
    expect(upperMedianDifficulty(tally("expert", "expert", "expert", "expert", "expert"))).toBe("expert");
  });

  it("takes the harder of the two middle labels for six voters", () => {
    expect(upperMedianDifficulty(tally("easy", "normal", "normal", "hard", "expert", "expert"))).toBe("hard");
    expect(upperMedianDifficulty(tally("easy", "normal", "normal", "normal", "expert", "expert"))).toBe("normal");
    expect(upperMedianDifficulty(tally("easy", "easy", "normal", "hard", "expert", "expert"))).toBe("hard");
  });

  it("takes the middle label of seven voters", () => {
    expect(upperMedianDifficulty(tally("easy", "easy", "normal", "hard", "hard", "expert", "expert"))).toBe("hard");
  });
});
