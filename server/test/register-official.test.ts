import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { runInNewContext } from "node:vm";
import { afterEach, beforeEach, expect, it } from "vitest";

const token = "registration-test-secret-never-log";
const databaseId = "12345678-1234-1234-1234-123456789abc";
let root: string;
let levels: string;
let server: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "official-registration-"));
  levels = join(root, "levels");
  server = join(root, "server");
  mkdirSync(levels);
  mkdirSync(join(server, "scripts"), { recursive: true });
  mkdirSync(join(root, "bin"));
  cpSync(join(import.meta.dirname, "../scripts/register-official.sh"), join(server, "scripts/register-official.sh"));
  writeFileSync(join(levels, "level_01.json"), "{\n  \"fixture\": 1\n}\n");
  writeFileSync(join(levels, "level_02.json"), "{\n  \"fixture\": 2\n}\n");
  // Only the authenticated Wrangler boundary is replaced; validation, hashing and SQL are real.
  writeFileSync(join(root, "bin/npx"), `#!/usr/bin/env node
const fs = require("node:fs");
const args = process.argv.slice(2);
const stage = args.includes("list") ? "list" : "execute";
fs.appendFileSync(process.env.CAPTURE + ".calls", JSON.stringify({args, authenticated: !!process.env.CLOUDFLARE_API_TOKEN}) + "\\n");
if (process.env.FAIL_STAGE === stage) {
  console.error(process.env.CLOUDFLARE_API_TOKEN);
  console.log(process.env.CLOUDFLARE_API_TOKEN);
  process.exit(1);
}
if (stage === "list") {
  console.log(JSON.stringify(process.env.NO_DATABASE ? [] : [{name: "unrelated", uuid: "wrong"}, {name: "zero-gx", uuid: "${databaseId}"}]));
} else {
  fs.copyFileSync(args[args.indexOf("--file") + 1], process.env.CAPTURE + ".sql");
  fs.copyFileSync(args[args.indexOf("--config") + 1], process.env.CAPTURE + ".toml");
}
`, { mode: 0o755 });
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

function run(release = "prototype-r150", env: Record<string, string> = {}) {
  return spawnSync("bash", ["-x", "scripts/register-official.sh", release], {
    cwd: server,
    encoding: "utf8",
    env: { ...process.env, PATH: `${join(root, "bin")}:${process.env.PATH}`, CLOUDFLARE_API_TOKEN: token, CLOUDFLARE_ACCOUNT_ID: "test-account", CAPTURE: join(root, "capture"), ...env },
  });
}
const calls = () => readFileSync(join(root, "capture.calls"), "utf8").trim().split("\n").map((line) => JSON.parse(line) as { args: string[]; authenticated: boolean });
const sql = () => readFileSync(join(root, "capture.sql"), "utf8");
const hash = (name: string) => createHash("sha256").update(readFileSync(join(levels, name))).digest("hex");

it("skips visibly without the deployment credential and never contacts Cloudflare", () => {
  const result = run("prototype-r150", { CLOUDFLARE_API_TOKEN: "" });
  expect(result.status).toBe(0);
  expect(result.stdout).toContain("::notice::");
  expect(result.stdout).toContain("CLOUDFLARE_API_TOKEN");
  expect(readdirSync(root)).not.toContain("capture.calls");
});

it("resolves the real database and upserts the canonical bytes, preserving old hashes and idempotency", () => {
  const result = run();
  expect(result.status, result.stderr).toBe(0);
  expect(calls().map((call) => call.authenticated)).toEqual([true, true]);
  expect(calls()[0]!.args).toEqual(["--no-install", "wrangler", "d1", "list", "--json"]);
  expect(calls()[1]!.args).toContain("--remote");
  expect(readFileSync(join(root, "capture.toml"), "utf8")).toContain(`database_id = "${databaseId}"`);
  const db = new DatabaseSync(":memory:");
  try {
    db.exec("CREATE TABLE official_levels (sha256 TEXT PRIMARY KEY, name TEXT NOT NULL, release TEXT NOT NULL)");
    db.prepare("INSERT INTO official_levels VALUES (?, ?, ?)").run("a".repeat(64), "level_01", "old-release");
    db.prepare("INSERT INTO official_levels VALUES (?, ?, ?)").run(hash("level_01.json"), "level_99", "earlier-release");
    db.exec(sql());
    db.exec(sql());
    expect(db.prepare("SELECT * FROM official_levels ORDER BY name, release").all().map((row) => ({ ...row }))).toEqual([
      { sha256: "a".repeat(64), name: "level_01", release: "old-release" },
      { sha256: hash("level_01.json"), name: "level_01", release: "prototype-r150" },
      { sha256: hash("level_02.json"), name: "level_02", release: "prototype-r150" },
    ]);
  } finally {
    db.close();
  }
  expect(result.stdout + result.stderr + JSON.stringify(calls())).not.toContain(token);
});

it.each(["", "bad'release", "bad/release", "x".repeat(65), "release\nDROP TABLE official_levels", "release\n"])("rejects invalid release %j before network access", (release) => {
  const result = run(release);
  expect(result.status).not.toBe(0);
  expect(readdirSync(root)).not.toContain("capture.calls");
});
it.each(["level_1.json", "level_001.json", "level_03';DROP.json", "unexpected.json"])("rejects invalid level name %j before network access", (name) => {
  writeFileSync(join(levels, name), "{}");
  expect(run().status).not.toBe(0);
  expect(readdirSync(root)).not.toContain("capture.calls");
});

it("refuses symlinked levels before network access", () => {
  symlinkSync(join(levels, "level_01.json"), join(levels, "level_03.json"));
  expect(run().status).not.toBe(0);
  expect(readdirSync(root)).not.toContain("capture.calls");
});

it("refuses an empty bundle before network access", () => {
  rmSync(levels, { recursive: true });
  mkdirSync(levels);
  expect(run().status).not.toBe(0);
  expect(readdirSync(root)).not.toContain("capture.calls");
});

it("refuses more than 200 bundle files before network access", () => {
  for (let i = 0; i < 201; i++) writeFileSync(join(levels, `level_${i}.json`), "{}");
  expect(run().status).not.toBe(0);
  expect(readdirSync(root)).not.toContain("capture.calls");
});

it.each(["list", "execute"])("makes a remote %s failure explicit and nonzero without leaking credential output", (stage) => {
  const result = run("prototype-r150", { FAIL_STAGE: stage });
  expect(result.status).not.toBe(0);
  expect(result.stderr).toContain("::error::");
  expect(result.stdout + result.stderr + JSON.stringify(calls())).not.toContain(token);
});

it("refuses to write when the named database has not been deployed", () => {
  expect(run("prototype-r150", { NO_DATABASE: "1" }).status).not.toBe(0);
  expect(calls()).toHaveLength(1);
});

it("wires registration after release and deployment, only for published trusted master runs", () => {
  const workflow = readFileSync(join(import.meta.dirname, "../../.github/workflows/build.yml"), "utf8");
  const job = workflow.split(/^  (?=\S)/m).find((block) => block.startsWith("register-official:\n"))!;
  expect(job, "registration job").toBeDefined();
  const needs = job.match(/^    needs:\s*\[([^\]]+)\]/m)![1]!.split(",").map((name) => name.trim());
  expect(needs.sort()).toEqual(["apk", "deploy-server"]);
  const guard = job.match(/^    if:\s*(.+)$/m)![1]!;
  for (const [event, ref, publish, allowed] of [
    ["push", "refs/heads/master", false, true],
    ["pull_request", "refs/heads/master", true, false],
    ["workflow_dispatch", "refs/heads/untrusted", true, false],
    ["workflow_dispatch", "refs/heads/master", false, false],
    ["workflow_dispatch", "refs/heads/master", true, true],
  ] as const) {
    expect(runInNewContext(guard, { github: { event_name: event, ref }, inputs: { publish } }), `${event}/${ref}/${publish}`).toBe(allowed);
  }
  expect(job).not.toMatch(/^\s+continue-on-error:\s*true\s*$/m);
  expect(job).not.toMatch(/^    env:/m); // The credential belongs to the registration step, not the whole job.

  const step = job.split(/^      - /m).find((block) => block.startsWith("name: Register official levels\n"))!;
  const command = step.match(/^        run:\s*(.+)$/m)![1]!;
  const argsFile = join(root, "workflow-registration.args");
  writeFileSync(join(server, "scripts/register-official.sh"), '#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$REGISTER_ARGS"\nexit 42\n');
  const result = spawnSync("bash", ["--noprofile", "--norc", "-e", "-o", "pipefail", "-c", command], {
    cwd: server,
    encoding: "utf8",
    env: { ...process.env, GITHUB_RUN_NUMBER: "151", REGISTER_ARGS: argsFile },
  });
  expect(result.status, result.stdout + result.stderr).toBe(42);
  expect(readFileSync(argsFile, "utf8")).toBe("prototype-r151\n");
});
