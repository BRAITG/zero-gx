import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { checkPr } from "../src/cli";

const fixtures = join(import.meta.dirname, "../../fixtures");
const level = readFileSync(join(fixtures, "levels/level_01.json"));
const demo = readFileSync(join(fixtures, "demos/level_01.demo.gz"));
const otherLevel = readFileSync(join(fixtures, "levels/floor.json"));
const otherDemo = readFileSync(join(fixtures, "demos/floor.demo.gz"));
const AUTHOR = "author_name-01";
const meta = JSON.stringify({ author: AUTHOR });

const A = "lvl_abcdefghij";
const B = "lvl_klmnopqrst";
type Files = Record<string, Buffer | string | null>; // null deletes

const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

// Builds a repository whose `base` branch holds `before` and whose `head` branch applies `change` on top.
function repo(before: Files, change: Files): string {
  const root = mkdtempSync(join(tmpdir(), "zgx-cli-"));
  dirs.push(root);
  const git = (...args: string[]) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...args], { cwd: root, stdio: "pipe" });
  const apply = (files: Files) => {
    for (const [path, content] of Object.entries(files)) {
      if (content === null) git("rm", "-q", path);
      else {
        mkdirSync(dirname(join(root, path)), { recursive: true });
        writeFileSync(join(root, path), content);
        git("add", path);
      }
    }
  };
  git("init", "-q", "-b", "main");
  apply({ "index.json": '{"levels": []}\n', "hidden.txt": "", ...before });
  git("commit", "-q", "-m", "base");
  git("checkout", "-q", "-b", "pr");
  apply(change);
  git("commit", "-q", "--allow-empty", "-m", "head");
  return root;
}

const existing: Files = {
  [`levels/${A}/v1.json`]: level,
  [`levels/${A}/meta.json`]: meta,
  [`proof/${A}/v1.demo.gz`]: demo,
};
const newLevel = (id = A): Files => ({
  [`levels/${id}/v1.json`]: level,
  [`levels/${id}/meta.json`]: meta,
  [`proof/${id}/v1.demo.gz`]: demo,
});
const problems = (before: Files, change: Files) => checkPr(repo(before, change), "main", "pr");

describe("check-pr accepts", () => {
  it("a new level", async () => {
    expect(await problems({}, newLevel())).toEqual({ ok: `OK: ${A} v1`, problems: [] });
  });

  it("the next version of an existing level", async () => {
    const change = { [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo };
    expect(await problems(existing, change)).toEqual({ ok: `OK: ${A} v2`, problems: [] });
  });

  it("a change to hidden.txt alone", async () => {
    expect(await problems({}, { "hidden.txt": `${A}\n` })).toEqual({ ok: "OK: hidden.txt", problems: [] });
  });
});

describe("check-pr rejects", () => {
  const fails = async (before: Files, change: Files, sentence: string) => {
    const r = await problems(before, change);
    expect(r.ok).toBeNull();
    expect(r.problems.some((p) => p.includes(sentence)), r.problems.join("\n")).toBe(true);
  };

  it("an empty change", () => fails({}, {}, "no changes"));
  it("editing an existing version", () => fails(existing, { [`levels/${A}/v1.json`]: level + "\n" }, "Only additions"));
  it("deleting a file", () => fails(existing, { [`proof/${A}/v1.demo.gz`]: null }, "Only additions"));
  it("touching two levels", () => fails({}, { ...newLevel(A), ...newLevel(B) }, "more than one level"));
  it("a version that is not latest + 1", () =>
    fails(existing, { [`levels/${A}/v3.json`]: level, [`proof/${A}/v3.demo.gz`]: demo }, "next version"));
  it("a first version that is not v1", () =>
    fails({}, { [`levels/${A}/v2.json`]: level, [`levels/${A}/meta.json`]: meta, [`proof/${A}/v2.demo.gz`]: demo }, "next version"));
  it("a missing proof", () => fails({}, { [`levels/${A}/v1.json`]: level, [`levels/${A}/meta.json`]: meta }, `proof/${A}/v1.demo.gz`));
  it("a missing meta.json on a new level", () =>
    fails({}, { [`levels/${A}/v1.json`]: level, [`proof/${A}/v1.demo.gz`]: demo }, `levels/${A}/meta.json`));
  it("meta.json on a new version", () =>
    fails(existing, { [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo, [`levels/${A}/meta.json`]: meta + " " }, "meta.json"));
  it("a path outside levels and proof", () => fails({}, { ...newLevel(), "notes.txt": "x" }, "notes.txt"));
  it("index.json and workflow changes", async () => {
    await fails({}, { "index.json": "{}\n" }, "index.json");
    await fails({}, { ".github/workflows/x.yml": "x" }, ".github/workflows/x.yml");
  });
  it("a bad level id", () => fails({}, newLevel("lvl_ABCdefghij"), "lvl_ABCdefghij"));
  it("hidden.txt mixed with level files", () => fails({}, { ...newLevel(), "hidden.txt": `${B}\n` }, "hidden.txt"));
  it("an invalid level", () => {
    const bad = Buffer.from(readFileSync(join(fixtures, "levels/invalid.planet_radius.json")));
    return fails({}, { ...newLevel(), [`levels/${A}/v1.json`]: bad }, "is not a valid level");
  });
  it("a level that is not a JSON object", () => fails({}, { ...newLevel(), [`levels/${A}/v1.json`]: "[1]" }, "JSON object"));
  it("an oversized level before parsing", async () => {
    const r = await problems({}, { ...newLevel(), [`levels/${A}/v1.json`]: Buffer.alloc(65537, "x") });
    expect(r.problems.some((p) => p.includes("65536"))).toBe(true);
    expect(r.problems.some((p) => p.includes("JSON"))).toBe(false);
  });
  it("a proof for a different level", () =>
    fails({}, { ...newLevel(), [`levels/${A}/v1.json`]: otherLevel, [`proof/${A}/v1.demo.gz`]: demo }, "different level"));
  it("a proof that fails the check", () =>
    fails({}, { ...newLevel(), [`proof/${A}/v1.demo.gz`]: readFileSync(join(fixtures, "demos/level_01.teleport.demo.gz")) }, "px in one frame"));
  it("a proof that does not decode", () => fails({}, { ...newLevel(), [`proof/${A}/v1.demo.gz`]: "junk" }, "not a valid demo"));
  it("an oversized proof", () => fails({}, { ...newLevel(), [`proof/${A}/v1.demo.gz`]: Buffer.alloc(524289) }, "524288"));
  it("a bad meta.json", async () => {
    for (const bad of ["[]", "{}", '{"author":"short"}', `{"author":"${AUTHOR}","extra":1}`, `{"author":"${AUTHOR}","based_on":"ABC"}`, "nope"]) {
      await fails({}, { ...newLevel(), [`levels/${A}/meta.json`]: bad }, "meta.json");
    }
  });
  it("accepts a meta.json with based_on", async () => {
    const withBase = JSON.stringify({ author: AUTHOR, based_on: "a".repeat(64) });
    expect((await problems({}, { ...newLevel(), [`levels/${A}/meta.json`]: withBase })).problems).toEqual([]);
  });
  it("proof for the other fixture pair", async () => {
    const r = await problems({}, { ...newLevel(), [`levels/${A}/v1.json`]: otherLevel, [`proof/${A}/v1.demo.gz`]: otherDemo });
    expect(r.problems).toEqual([]);
  });
});

describe("cli", () => {
  const run = (root: string) =>
    spawnSync(join(import.meta.dirname, "../node_modules/.bin/tsx"), ["src/cli.ts", "check-pr", root, "main", "pr"], {
      cwd: join(import.meta.dirname, ".."),
      encoding: "utf8",
    });

  it("prints OK and exits 0", () => {
    const r = run(repo({}, newLevel()));
    expect([r.status, r.stdout]).toEqual([0, `OK: ${A} v1\n`]);
  });

  it("prints one sentence per problem and exits 1", () => {
    const r = run(repo({}, { "hidden.txt": null }));
    expect(r.status).toBe(1);
    expect(r.stdout.trim().split("\n")).toHaveLength(1);
  });
});
