import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { sha256Hex, validateLevel } from "../src/core/level";

const root = join(import.meta.dirname, "../..");
const expected = JSON.parse(readFileSync(join(root, "fixtures/expected.json"), "utf8")) as {
  levels: Record<string, string[]>;
  official_hashes: Record<string, string>;
};

describe("fixture levels", () => {
  for (const [file, substrings] of Object.entries(expected.levels)) {
    it(file, () => {
      const errors = validateLevel(JSON.parse(readFileSync(join(root, "fixtures/levels", file), "utf8")));
      for (const error of errors) expect(substrings.some((s) => error.includes(s)), error).toBe(true);
      for (const s of substrings) expect(errors.some((e) => e.includes(s)), s).toBe(true);
    });
  }
});

describe("game levels", () => {
  const files = ["levels", "tutorials"].flatMap((dir) =>
    readdirSync(join(root, dir))
      .filter((f) => f.endsWith(".json"))
      .map((f) => join(dir, f)),
  );
  for (const file of files) {
    it(`${file} is valid`, () => {
      expect(validateLevel(JSON.parse(readFileSync(join(root, file), "utf8")))).toEqual([]);
    });
  }
});

describe("hashes", () => {
  for (const [name, hash] of Object.entries(expected.official_hashes)) {
    it(name, async () => {
      expect(await sha256Hex(readFileSync(join(root, "levels", `${name}.json`)))).toBe(hash);
    });
  }
});

describe("validateLevel edge cases", () => {
  const base = () => JSON.parse(readFileSync(join(root, "levels/level_01.json"), "utf8"));
  it("rejects non-objects", () => {
    for (const bad of [null, [], "x", 3]) expect(validateLevel(bad)).toEqual(["not a zero-gx-level version 1 file"]);
  });
  it("rejects a ship starting inside a body", () => {
    const level = base();
    level.bodies = [{ kind: "planet", position: level.ship.position }];
    expect(validateLevel(level)).toContain("the ship starts inside body 0");
  });
  it("counts title characters, not UTF-16 units", () => {
    const level = base();
    level.title = "🚀".repeat(40);
    expect(validateLevel(level)).toEqual([]);
  });
  it("accepts a whole par of at least 100 points and refuses the rest", () => {
    const level = base();
    level.par = 1200;
    expect(validateLevel(level)).toEqual([]);
    for (const bad of [99, 12.5, "x"]) {
      level.par = bad;
      expect(validateLevel(level)).toContain("par must be a whole number of at least 100 points");
    }
  });
});
