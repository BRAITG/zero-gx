// Pull-request checker for the levels repository: `tsx src/cli.ts check-pr <repo-root> <base-ref> <head-ref>`.
// Exits 0 and prints `OK: ...` for a valid submission, else prints one sentence per problem and exits 1.
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { checkDemo } from "./core/check";
import { MAX_BYTES, decodeDemo } from "./core/demo";
import { MAX_LEVEL_BYTES, sha256Hex, validateLevel } from "./core/level";

const LEVEL_FILE = /^levels\/(lvl_[a-z0-9]{10})\/(meta\.json|v([1-9][0-9]*)\.json)$/;
const PROOF_FILE = /^proof\/(lvl_[a-z0-9]{10})\/v([1-9][0-9]*)\.demo\.gz$/;
const AUTHOR = /^[A-Za-z0-9_-]{8,64}$/;
const SHA256 = /^[0-9a-f]{64}$/;

export interface Result {
  ok: string | null;
  problems: string[];
}

export async function checkPr(root: string, base: string, head: string): Promise<Result> {
  // A ref starting with "-" would be read by git as an option.
  if (base.startsWith("-") || head.startsWith("-")) return fail("The refs must not start with a dash.");
  const git = (...args: string[]) => execFileSync("git", args, { cwd: root, maxBuffer: 64 * 1024 * 1024 });

  const tokens = git("diff", "--name-status", "--no-renames", "-z", `${base}...${head}`).toString("utf8").split("\0");
  const changes: { status: string; path: string }[] = [];
  for (let i = 0; i + 1 < tokens.length; i += 2) changes.push({ status: tokens[i], path: tokens[i + 1] });
  if (changes.length === 0) return fail("The pull request has no changes.");

  if (changes.some((c) => c.path === "hidden.txt")) {
    if (changes.length > 1) return fail("hidden.txt must be changed on its own, not together with other files.");
    return changes[0].status === "A" || changes[0].status === "M" ? { ok: "OK: hidden.txt", problems: [] } : fail("hidden.txt must not be deleted.");
  }

  const problems: string[] = [];
  const ids = new Set<string>();
  for (const { status, path } of changes) {
    if (status !== "A") problems.push(`Only additions are allowed, but ${path} has status ${status}.`);
    const id = (LEVEL_FILE.exec(path) ?? PROOF_FILE.exec(path))?.[1];
    if (id) ids.add(id);
    else problems.push(`${path} is not an allowed path: expected levels/lvl_<10 lowercase letters or digits>/v<N>.json, meta.json or proof/<id>/v<N>.demo.gz.`);
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

  const added = new Set(changes.map((c) => c.path));
  const required = isNew ? [levelPath, demoPath, metaPath] : [levelPath, demoPath];
  for (const path of required) if (!added.has(path)) problems.push(`The pull request must add ${path}.`);
  for (const path of added) {
    if (required.includes(path)) continue;
    problems.push(
      path === metaPath
        ? `${path} may only be added together with a new level.`
        : `${path} has the wrong version: the next version of ${id} is v${n}.`,
    );
  }
  if (problems.length > 0) return { ok: null, problems };

  // Sizes come from git before any blob is read, so an oversized file is never loaded or parsed.
  const size = (path: string) => Number(git("cat-file", "-s", `${head}:${path}`).toString());
  const show = (path: string) => git("show", `${head}:${path}`);
  if (size(levelPath) > MAX_LEVEL_BYTES) problems.push(`${levelPath} is larger than ${MAX_LEVEL_BYTES} bytes.`);
  if (size(demoPath) > MAX_BYTES) problems.push(`${demoPath} is larger than ${MAX_BYTES} bytes.`);
  if (isNew) problems.push(...checkMeta(metaPath, show(metaPath)));
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

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const [command, root, base, head] = process.argv.slice(2);
  if (command !== "check-pr" || !root || !base || !head) {
    console.error("usage: cli.ts check-pr <repo-root> <base-ref> <head-ref>");
    process.exit(2);
  }
  const { ok, problems } = await checkPr(root, base, head);
  console.log(ok ?? problems.join("\n"));
  process.exit(ok ? 0 : 1);
}
