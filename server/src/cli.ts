// Pull-request checker for the levels repository: `tsx src/cli.ts check-pr <repo-root> <base-ref> <head-ref> [--event <github-event-json>]`.
// Exits 0 and prints `OK: ...` for a valid submission, else prints one sentence per problem and exits 1.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { checkDemo } from "./core/check";
import { MAX_BYTES, decodeDemo } from "./core/demo";
import { reviewedDifficulty } from "./core/difficulty";
import { MAX_LEVEL_BYTES, sha256Hex, validateLevel } from "./core/level";

const LEVEL_FILE = /^levels\/(lvl_[a-z0-9]{10})\/(meta\.json|v([1-9][0-9]*)\.json)$/;
const PROOF_FILE = /^proof\/(lvl_[a-z0-9]{10})\/v([1-9][0-9]*)\.demo\.gz$/;
const SKETCH_FILE = /^levels\/(lvl_[a-z0-9]{10})\/v([1-9][0-9]*)\.sketch\.json$/;
const AUTHOR = /^[A-Za-z0-9_-]{8,64}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const LEVEL_ID = /^lvl_[a-z0-9]{10}$/;
const MAX_META_BYTES = 1024;
const MAX_SKETCH_BYTES = 2048;
const MAX_HIDDEN_BYTES = 65536;

export interface Result {
  ok: string | null;
  problems: string[];
}

export async function checkPr(root: string, base: string, head: string, reviewLabels?: readonly string[]): Promise<Result> {
  try {
    return await check(root, base, head, reviewLabels);
  } catch (e) {
    // A git or decode failure must read as a verdict, not a stack trace.
    return fail(`The check could not be completed: ${String(e instanceof Error ? e.message : e).split("\n")[0]}.`);
  }
}

async function check(root: string, base: string, head: string, reviewLabels?: readonly string[]): Promise<Result> {
  // A ref starting with "-" would be read by git as an option.
  if (base.startsWith("-") || head.startsWith("-")) return fail("The refs must not start with a dash.");
  const git = (...args: string[]) => execFileSync("git", args, { cwd: root, maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
  // Sizes come from git before any blob is read, so an oversized file is never loaded or parsed.
  const size = (path: string) => Number(git("cat-file", "-s", `${head}:${path}`).toString());
  const show = (path: string) => git("show", `${head}:${path}`);

  // --raw gives the new file mode; `git show` would return a symlink's target text as if it were the file.
  const tokens = git("diff", "--raw", "--no-renames", "-z", `${base}...${head}`).toString("utf8").split("\0");
  const changes: { status: string; mode: string; path: string }[] = [];
  for (let i = 0; i + 1 < tokens.length; i += 2) {
    const [, mode, , , status] = tokens[i].split(" ");
    changes.push({ status, mode, path: tokens[i + 1] });
  }
  if (changes.length === 0) return fail("The pull request has no changes.");

  const problems: string[] = [];
  for (const { status, mode, path } of changes) {
    if (status !== "D" && mode !== "100644") problems.push(`${path} must be a regular file (mode 100644), not mode ${mode}.`);
  }

  if (changes.some((c) => c.path === "hidden.txt")) {
    if (changes.length > 1) problems.push("hidden.txt must be changed on its own, not together with other files.");
    else if (changes[0].status === "D") problems.push("hidden.txt must not be deleted.");
    else if (problems.length === 0) problems.push(...checkHidden(size("hidden.txt"), () => show("hidden.txt")));
    return problems.length > 0 ? { ok: null, problems } : { ok: "OK: hidden.txt", problems };
  }

  const ids = new Set<string>();
  for (const { status, path } of changes) {
    if (status !== "A") problems.push(`Only additions are allowed, but ${path} has status ${status}.`);
    const id = (LEVEL_FILE.exec(path) ?? SKETCH_FILE.exec(path) ?? PROOF_FILE.exec(path))?.[1];
    if (id) ids.add(id);
    else problems.push(`${path} is not an allowed path: expected levels/lvl_<10 lowercase letters or digits>/v<N>.json, v<N>.sketch.json, meta.json or proof/<id>/v<N>.demo.gz.`);
  }
  if (ids.size > 1) problems.push(`The pull request touches more than one level: ${[...ids].join(", ")}.`);
  if (problems.length > 0 || ids.size !== 1) return { ok: null, problems };

  const [id] = ids;
  const atBase = git("ls-tree", "-r", "--name-only", "-z", base, "--", `levels/${id}/`).toString("utf8").split("\0").filter(Boolean);
  const isNew = atBase.length === 0;
  const latest = Math.max(0, ...atBase.map((p) => Number(LEVEL_FILE.exec(p)?.[3] ?? 0)));
  const n = latest + 1;
  const levelPath = `levels/${id}/v${n}.json`;
  const demoPath = `proof/${id}/v${n}.demo.gz`;
  const metaPath = `levels/${id}/meta.json`;
  const sketchPath = `levels/${id}/v${n}.sketch.json`;

  const added = new Set(changes.map((c) => c.path));
  const required = isNew ? [levelPath, demoPath, metaPath] : [levelPath, demoPath];
  for (const path of required) if (!added.has(path)) problems.push(`The pull request must add ${path}.`);
  if (added.has(sketchPath) && !added.has(levelPath)) problems.push(`${sketchPath} may only be added together with ${levelPath}.`);
  for (const path of added) {
    if (required.includes(path) || path === sketchPath) continue;
    problems.push(
      path === metaPath
        ? `${path} may only be added together with a new level.`
        : `${path} has the wrong version: the next version of ${id} is v${n}.`,
    );
  }
  // Exactly one recognised difficulty label; labels left undefined mean a content-only check.
  if (reviewLabels !== undefined && reviewedDifficulty(reviewLabels) === null) {
    problems.push("A level submission needs exactly one moderator label: difficulty:easy, difficulty:normal, difficulty:hard or difficulty:expert.");
  }
  if (problems.length > 0) return { ok: null, problems };

  if (size(levelPath) > MAX_LEVEL_BYTES) problems.push(`${levelPath} is larger than ${MAX_LEVEL_BYTES} bytes.`);
  if (size(demoPath) > MAX_BYTES) problems.push(`${demoPath} is larger than ${MAX_BYTES} bytes.`);
  if (isNew) {
    if (size(metaPath) > MAX_META_BYTES) problems.push(`${metaPath} is larger than ${MAX_META_BYTES} bytes.`);
    else problems.push(...checkMeta(metaPath, show(metaPath)));
  }
  if (added.has(sketchPath)) {
    if (size(sketchPath) > MAX_SKETCH_BYTES) problems.push(`${sketchPath} is larger than 2 KB.`);
    else if (!parseObject(show(sketchPath))) problems.push(`${sketchPath} is not a JSON object.`);
  }
  if (problems.length > 0) return { ok: null, problems };

  const levelBytes = show(levelPath);
  const levelData = parseObject(levelBytes);
  if (!levelData) return fail(`${levelPath} is not a JSON object.`);
  const levelErrors = validateLevel(levelData);
  if (levelErrors.length > 0) return { ok: null, problems: levelErrors.map((e) => `${levelPath} is not a valid level: ${e}.`) };

  const demo = await decodeDemo(show(demoPath));
  if (!demo) return fail(`${demoPath} is not a valid demo.`);
  const demoErrors = checkDemo(levelData, await sha256Hex(levelBytes), demo);
  if (demoErrors.length > 0) return { ok: null, problems: demoErrors.map((e) => `${demoPath} does not prove ${levelPath}: ${e}.`) };

  return { ok: `OK: ${id} v${n}`, problems: [] };
}

function fail(problem: string): Result {
  return { ok: null, problems: [problem] };
}

function parseObject(bytes: Uint8Array): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** The label names of a `pull_request` event file, read as data and never run. Null unless it has a labels list of named labels. */
function eventLabels(path: string): string[] | null {
  let bytes: Buffer;
  try {
    bytes = readFileSync(path);
  } catch {
    return null;
  }
  const pull = parseObject(bytes)?.pull_request;
  if (typeof pull !== "object" || pull === null || !("labels" in pull) || !Array.isArray(pull.labels)) return null;
  const names = pull.labels.map((label: unknown) => (typeof label === "object" && label !== null && "name" in label ? label.name : undefined));
  return names.every((name): name is string => typeof name === "string") ? names : null;
}

function checkMeta(path: string, bytes: Uint8Array): string[] {
  const meta = parseObject(bytes);
  if (!meta) return [`${path} is not a JSON object.`];
  const problems: string[] = [];
  for (const key of Object.keys(meta)) if (key !== "author" && key !== "based_on") problems.push(`${path} has the unknown key "${key}".`);
  if (typeof meta.author !== "string" || !AUTHOR.test(meta.author)) problems.push(`${path} needs an "author" of 8 to 64 letters, digits, "_" or "-".`);
  if ("based_on" in meta && (typeof meta.based_on !== "string" || !SHA256.test(meta.based_on))) {
    problems.push(`${path} "based_on" must be 64 lowercase hex characters.`);
  }
  return problems;
}

function checkHidden(bytes: number, read: () => Uint8Array): string[] {
  if (bytes > MAX_HIDDEN_BYTES) return [`hidden.txt is larger than ${MAX_HIDDEN_BYTES} bytes.`];
  const lines = new TextDecoder().decode(read()).split("\n");
  const bad = lines.findIndex((l) => l !== "" && !LEVEL_ID.test(l));
  return bad < 0 ? [] : [`hidden.txt line ${bad + 1} is not empty or a level id like lvl_abcdefghij.`];
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const args = process.argv.slice(2);
  const at = args.indexOf("--event");
  const [command, root, base, head] = at < 0 ? args : [...args.slice(0, at), ...args.slice(at + 2)];
  const event = at < 0 ? undefined : args[at + 1];
  if (command !== "check-pr" || !root || !base || !head || (at >= 0 && event === undefined)) {
    console.error("usage: cli.ts check-pr <repo-root> <base-ref> <head-ref> [--event <github-event-json>]");
    process.exit(2);
  }
  let result: Result;
  if (event === undefined) result = await checkPr(root, base, head);
  else {
    const labels = eventLabels(event);
    result = labels === null ? fail("The --event file is not a pull request event with a labels list.") : await checkPr(root, base, head, labels);
  }
  console.log(result.ok ?? result.problems.join("\n"));
  process.exit(result.ok ? 0 : 1);
}
