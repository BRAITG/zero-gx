import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
// null deletes; `mode` stages the entry with that git mode (symlink, gitlink); `from` renames an existing file.
type Files = Record<string, Buffer | string | null | { mode: string; content: string } | { from: string }>;

const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

// Builds a repository whose `main` branch holds `before` and whose `pr` branch applies `change` on top;
// `baseAfter` then lands on `main`, leaving `pr` behind it.
function repo(before: Files, change: Files, baseAfter: Files = {}): string {
  const root = mkdtempSync(join(tmpdir(), "zgx-cli-"));
  dirs.push(root);
  const git = (...args: string[]) =>
    execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...args], { cwd: root, stdio: "pipe" }).toString().trim();
  const apply = (files: Files) => {
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      if (content === null) git("rm", "-q", path);
      else if (typeof content === "object" && "from" in content) git("mv", content.from, path);
      else if (typeof content === "object" && "mode" in content) {
        writeFileSync(join(root, path), content.content);
        const sha = content.mode === "160000" ? git("rev-parse", "HEAD") : git("hash-object", "-w", path);
        git("update-index", "--add", "--cacheinfo", `${content.mode},${sha},${path}`);
      } else {
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
  git("checkout", "-q", "-f", "main");
  apply(baseAfter);
  git("commit", "-q", "--allow-empty", "-m", "base moves on");
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
const problems = (before: Files, change: Files, baseAfter: Files = {}) => checkPr(repo(before, change, baseAfter), "main", "pr");
const labelled = (labels: string[], before: Files, change: Files, baseAfter: Files = {}) => checkPr(repo(before, change, baseAfter), "main", "pr", labels);
const tsx = join(import.meta.dirname, "../node_modules/.bin/tsx");
const cli = (...args: string[]) => spawnSync(tsx, ["src/cli.ts", ...args], { cwd: join(import.meta.dirname, ".."), encoding: "utf8" });

describe("check-pr accepts", () => {
  it("a new level", async () => {
    expect(await problems({}, newLevel())).toEqual({ ok: `OK: ${A} v1`, problems: [] });
  });

  it("the next version of an existing level", async () => {
    const change = { [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo };
    expect(await problems(existing, change)).toEqual({ ok: `OK: ${A} v2`, problems: [] });
  });

  it("a branch that is behind base while its version is still latest + 1", async () => {
    const change = { [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo };
    expect(await problems(existing, change, newLevel(B))).toEqual({ ok: `OK: ${A} v2`, problems: [] });
  });

  it("a change to hidden.txt alone", async () => {
    expect(await problems({}, { "hidden.txt": `${A}\n` })).toEqual({ ok: "OK: hidden.txt", problems: [] });
  });
  it("a sketch with its level", async () => {
    expect(await problems({}, { ...newLevel(), [`levels/${A}/v1.sketch.json`]: '{"bounds":[0,0,1,1]}' })).toEqual({ ok: `OK: ${A} v1`, problems: [] });
  });
});

describe("check-pr rejects", () => {
  const fails = async (before: Files, change: Files, sentence: string, baseAfter: Files = {}) => {
    const r = await problems(before, change, baseAfter);
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
  it("a symlink in place of a file", async () => {
    for (const path of [`levels/${A}/meta.json`, `levels/${A}/v1.json`, `proof/${A}/v1.demo.gz`]) {
      await fails({}, { ...newLevel(), [path]: { mode: "120000", content: "../../index.json" } }, "regular file");
    }
    await fails({}, { "hidden.txt": { mode: "120000", content: "index.json" } }, "regular file");
  });
  it("a gitlink", () => fails({}, { ...newLevel(), [`levels/${A}/meta.json`]: { mode: "160000", content: "" } }, "mode 160000"));
  it("an executable file", () => fails({}, { ...newLevel(), [`levels/${A}/meta.json`]: { mode: "100755", content: meta } }, "regular file"));
  it("a rename", () => fails(existing, { [`levels/${A}/v2.json`]: { from: `levels/${A}/v1.json` }, [`proof/${A}/v2.demo.gz`]: demo }, "Only additions"));
  it("a base that already holds the version", () =>
    fails(existing, { [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo }, "next version", {
      [`levels/${A}/v2.json`]: level + " ",
      [`proof/${A}/v2.demo.gz`]: demo,
    }));
  it("hidden.txt lines that are not level ids", async () => {
    for (const bad of ["lvl_short\n", "lvl_abcdefghij lvl_klmnopqrst\n", "../x\n"]) await fails({}, { "hidden.txt": bad }, "hidden.txt line 1");
  });
  it("an oversized hidden.txt", () => fails({}, { "hidden.txt": "\n".repeat(65537) }, "65536"));
  it("an oversized meta.json", () => fails({}, { ...newLevel(), [`levels/${A}/meta.json`]: " ".repeat(1025) + meta }, "1024"));
  it("refs that start with a dash", async () => {
    const root = repo({}, newLevel());
    for (const [base, head] of [["--output=x", "pr"], ["main", "-x"]]) {
      expect((await checkPr(root, base, head)).problems).toEqual(["The refs must not start with a dash."]);
    }
  });
  it("an unknown ref as one sentence", async () => {
    const r = await checkPr(repo({}, newLevel()), "main", "nope");
    expect(r.ok).toBeNull();
    expect(r.problems).toHaveLength(1);
    expect(r.problems[0]).toMatch(/^The check could not be completed: .*\.$/);
  });
  it("accepts a meta.json with based_on", async () => {
    const withBase = JSON.stringify({ author: AUTHOR, based_on: "a".repeat(64) });
    expect((await problems({}, { ...newLevel(), [`levels/${A}/meta.json`]: withBase })).problems).toEqual([]);
  });
  it("proof for the other fixture pair", async () => {
    const r = await problems({}, { ...newLevel(), [`levels/${A}/v1.json`]: otherLevel, [`proof/${A}/v1.demo.gz`]: otherDemo });
    expect(r.problems).toEqual([]);
  });
  it("a sketch without its level", () => fails({}, { [`levels/${A}/v1.sketch.json`]: '{"bounds":[0,0,1,1]}' }, "may only be added together with"));
  it("a sketch of another version", () =>
    fails(existing, { [`levels/${A}/v1.sketch.json`]: '{"bounds":[0,0,1,1]}', [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo }, "wrong version"));
  it("a sketch over 2 KB", () => fails({}, { ...newLevel(), [`levels/${A}/v1.sketch.json`]: `{${" ".repeat(3000)}}` }, "larger than 2 KB"));
  it("a sketch that is not a JSON object", () => fails({}, { ...newLevel(), [`levels/${A}/v1.sketch.json`]: "[]" }, "is not a JSON object"));
});

describe("check-pr with review labels", () => {
  it("refuses a new level without exactly one difficulty label", async () => {
    for (const labels of [[], ["bug", "good first issue"], ["hard"], ["difficulty:legendary"]]) {
      const r = await labelled(labels, {}, newLevel());
      expect(r.ok, JSON.stringify(labels)).toBeNull();
    }
  });

  it("refuses a new level with several difficulty labels", async () => {
    const r = await labelled(["difficulty:easy", "difficulty:hard"], {}, newLevel());
    expect(r.ok).toBeNull();
  });

  it("accepts exactly one difficulty label among unrelated labels", async () => {
    expect(await labelled(["bug", "difficulty:hard", "good first issue"], {}, newLevel())).toEqual({ ok: `OK: ${A} v1`, problems: [] });
  });

  it("requires the label on the next version too", async () => {
    const change = { [`levels/${A}/v2.json`]: level, [`proof/${A}/v2.demo.gz`]: demo };
    expect((await labelled([], existing, change)).ok).toBeNull();
    expect(await labelled(["difficulty:normal"], existing, change)).toEqual({ ok: `OK: ${A} v2`, problems: [] });
  });

  it("exempts hidden.txt-only maintenance, labelled or not", async () => {
    const change = { "hidden.txt": `${A}\n` };
    expect(await labelled([], {}, change)).toEqual({ ok: "OK: hidden.txt", problems: [] });
    expect(await labelled(["bug"], {}, change)).toEqual({ ok: "OK: hidden.txt", problems: [] });
  });
});

describe("cli", () => {
  const run = (root: string) => cli("check-pr", root, "main", "pr");

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

describe("cli --event", () => {
  const scratch = () => {
    const dir = mkdtempSync(join(tmpdir(), "zgx-event-"));
    dirs.push(dir);
    return dir;
  };
  const eventFile = (dir: string, content: string) => {
    const path = join(dir, "event.json");
    writeFileSync(path, content);
    return path;
  };
  /** A `labeled` delivery whose pull request carries exactly these label names. */
  const labels = (...names: string[]) => JSON.stringify({ action: "labeled", pull_request: { number: 1, labels: names.map((name) => ({ name })) } });

  it("accepts a labelled new level", () => {
    const r = cli("check-pr", repo({}, newLevel()), "main", "pr", "--event", eventFile(scratch(), labels("bug", "difficulty:hard")));
    expect([r.status, r.stdout]).toEqual([0, `OK: ${A} v1\n`]);
  });

  it("fails with one sentence unless exactly one difficulty label is present", () => {
    const dir = scratch();
    for (const names of [[], ["difficulty:easy", "difficulty:hard"]]) {
      const r = cli("check-pr", repo({}, newLevel()), "main", "pr", "--event", eventFile(dir, labels(...names)));
      expect([r.status, r.stdout.trim().split("\n").length], JSON.stringify(names)).toEqual([1, 1]);
    }
  });

  it("exempts a hidden.txt-only change without a label", () => {
    const r = cli("check-pr", repo({}, { "hidden.txt": `${A}\n` }), "main", "pr", "--event", eventFile(scratch(), labels()));
    expect([r.status, r.stdout]).toEqual([0, "OK: hidden.txt\n"]);
  });

  it("never executes label text from the event", () => {
    const dir = scratch();
    const marker = join(dir, "pwned");
    const hostile = [`bug"; touch ${marker}; echo "`, `$(touch ${marker})`, `\`touch ${marker}\``, `difficulty:hard\n; touch ${marker}`];
    const r = cli("check-pr", repo({}, newLevel()), "main", "pr", "--event", eventFile(dir, labels(...hostile)));
    expect(existsSync(marker)).toBe(false);
    expect([r.status, r.stdout.trim().split("\n").length]).toEqual([1, 1]);
  });

  it("reads the exact difficulty label past hostile text, and runs none of it", () => {
    const dir = scratch();
    const marker = join(dir, "pwned");
    const r = cli("check-pr", repo({}, newLevel()), "main", "pr", "--event", eventFile(dir, labels(`"; touch ${marker}; "`, "difficulty:hard")));
    expect([r.status, r.stdout]).toEqual([0, `OK: ${A} v1\n`]);
    expect(existsSync(marker)).toBe(false);
  });

  it("exits nonzero with one sentence for an event it cannot read", () => {
    const dir = scratch();
    const root = repo({}, newLevel());
    const unreadable = [
      "{",
      "[]",
      JSON.stringify({ action: "labeled" }),
      JSON.stringify({ pull_request: { labels: "difficulty:hard" } }),
      JSON.stringify({ pull_request: { labels: [{ name: 3 }] } }),
      JSON.stringify({ pull_request: { labels: [null] } }),
    ];
    for (const content of unreadable) {
      const r = cli("check-pr", root, "main", "pr", "--event", eventFile(dir, content));
      expect(r.status, content).not.toBe(0);
      expect(r.stdout.trim().split("\n"), content).toHaveLength(1);
      expect(r.stdout.trim(), content).toMatch(/\.$/);
    }
    const missing = cli("check-pr", root, "main", "pr", "--event", join(dir, "absent.json"));
    expect(missing.status).not.toBe(0);
    expect(missing.stdout.trim().split("\n")).toHaveLength(1);
  });
});
