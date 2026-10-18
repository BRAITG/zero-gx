import { checkDemo } from "./core/check";
import { MAX_BYTES, decodeDemo } from "./core/demo";
import { MAX_LEVEL_BYTES, sha256Hex, validateLevel } from "./core/level";
import type { Env } from "./env";
import { commitIndex, getFile, lastComment, openOrUpdatePullRequest, pullRequestState } from "./github";
import { HttpError, readBytes } from "./http";
import { requireIntegrity, requirePlayer } from "./session";
import { randomId } from "./util";

const MAX_BODY_BYTES = 600_000;
const MAX_OPEN = 3;
/** A submission whose pull request is still unrecorded after this long was abandoned by its request. */
const STALE_SECONDS = 120;
const RECORD_ATTEMPTS = 3;
const MAX_PER_DAY = 5;
const MAX_WEBHOOK_BYTES = 1_000_000;
const MAX_COMMENT = 500;
const LEVEL_ID = /^lvl_[a-z0-9]{10}$/;
const SHA256 = /^[0-9a-f]{64}$/;

const now = () => Math.floor(Date.now() / 1000);

interface LevelRow {
  id: string;
  owner: string;
  based_on: string | null;
  latest: number;
  hidden: number;
  /** 1 when the level is listed in hidden.txt. */
  listed: number;
}

interface SubmissionRow {
  id: number;
  level: string;
  version: number;
  pull_request: number | null;
  status: "open" | "approved" | "rejected";
  title: string | null;
  sha256: string | null;
  created: number;
}

const selectOpen = (env: Env, level: string) => env.DB.prepare("SELECT * FROM submissions WHERE level = ? AND status = 'open'").bind(level).first<SubmissionRow>();

/** An optional text field; empty counts as absent. */
function field(form: FormData, name: string): string | null {
  const value = form.get(name);
  if (value === null || value === "") return null;
  if (typeof value !== "string") throw new HttpError(400, `${name} must be text.`);
  return value;
}

/** `fetchFn` is the injection point for tests. */
export async function postSubmission(request: Request, env: Env, _params: Record<string, string>, fetchFn: typeof fetch = fetch): Promise<Response> {
  const player = await requirePlayer(request, env);
  await requireIntegrity(request, env);
  const body = await readBytes(request, MAX_BODY_BYTES);
  const form = await new Request(request.url, { method: "POST", headers: { "Content-Type": request.headers.get("Content-Type") ?? "" }, body }).formData().catch(() => null);
  const levelFile = form?.get("level");
  const demoFile = form?.get("demo");
  if (!form || !(levelFile instanceof File) || !(demoFile instanceof File)) throw new HttpError(400, "A multipart form with the files level and demo is required.");
  if (levelFile.size > MAX_LEVEL_BYTES) throw new HttpError(413, `The level is over ${MAX_LEVEL_BYTES} bytes.`);
  if (demoFile.size > MAX_BYTES) throw new HttpError(413, `The demo is over ${MAX_BYTES} bytes.`);
  const levelId = field(form, "level_id");
  const basedOn = field(form, "based_on");
  if (levelId !== null && !LEVEL_ID.test(levelId)) throw new HttpError(400, "level_id must look like lvl_abcdefghij.");
  if (basedOn !== null && !SHA256.test(basedOn)) throw new HttpError(400, "based_on must be a lowercase 64-digit hex sha256.");

  // Everything below up to the limits is validation: nothing reaches GitHub before it passes.
  const levelBytes = new Uint8Array(await levelFile.arrayBuffer());
  let levelText: string;
  let level: unknown;
  try {
    // Fatal and BOM-preserving, so that the text re-encodes to exactly the bytes whose hash the demo is bound to.
    levelText = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(levelBytes);
    level = JSON.parse(levelText);
  } catch {
    throw new HttpError(400, "The level is not valid UTF-8 JSON.");
  }
  const levelErrors = validateLevel(level);
  if (levelErrors.length > 0) throw new HttpError(400, levelErrors[0]!);
  const checked = level as { title: string }; // validateLevel guarantees the title
  const demoBytes = new Uint8Array(await demoFile.arrayBuffer());
  const demo = await decodeDemo(demoBytes);
  if (!demo) throw new HttpError(400, "The demo could not be read.");
  const sha256 = await sha256Hex(levelBytes);
  const demoErrors = checkDemo(level, sha256, demo);
  if (demoErrors.length > 0) throw new HttpError(400, demoErrors[0]!);

  const known = (hash: string) =>
    env.DB.prepare("SELECT 1 AS found FROM versions WHERE sha256 = ?1 UNION ALL SELECT 1 FROM official_levels WHERE sha256 = ?1").bind(hash).first();
  if (basedOn !== null && !(await known(basedOn))) throw new HttpError(400, "based_on is not the hash of a published level.");
  // versions.sha256 is unique: an unchanged resubmission could never be recorded as a version.
  if (await known(sha256)) throw new HttpError(409, "This exact level is already published.");

  let row: LevelRow | null = null;
  let open: SubmissionRow | null = null;
  if (levelId !== null) {
    row = await env.DB.prepare("SELECT *, id IN (SELECT level FROM hidden_levels) AS listed FROM levels WHERE id = ?").bind(levelId).first<LevelRow>();
    if (!row) throw new HttpError(404, "Not found.");
    if (row.owner !== player.id) throw new HttpError(403, "This level belongs to another player.");
    if (row.hidden || row.listed) throw new HttpError(403, "This level is hidden.");
    open = await selectOpen(env, levelId);
  }
  // Another open submission already carries these exact bytes: only one of them could ever be recorded as a version.
  const duplicate = await env.DB.prepare("SELECT 1 AS found FROM submissions WHERE sha256 = ? AND status = 'open' AND level != ?").bind(sha256, levelId ?? "").first();
  if (duplicate) throw new HttpError(409, "Another open submission already carries this exact level.");
  const opening = new HttpError(409, "This level's submission is still being opened; try again in a moment.");
  if (open && open.pull_request === null && open.created > now() - STALE_SECONDS) throw opening;

  const today = await env.DB.prepare(
    `INSERT INTO rate (player, action, "window", count) VALUES (?, 'submit', ?, 1)
     ON CONFLICT (player, action, "window") DO UPDATE SET count = count + 1 RETURNING count`,
  )
    .bind(player.id, Math.floor(now() / 86400))
    .first<{ count: number }>();
  if (today!.count > MAX_PER_DAY) throw new HttpError(429, `At most ${MAX_PER_DAY} submissions are accepted per day.`);

  const isNewLevel = row === null;
  const level_id = row?.id ?? randomId("lvl_", 10);
  const version = open?.version ?? (row?.latest ?? 0) + 1;
  const unavailable = () => new HttpError(502, "GitHub did not accept the submission; try again later.");
  let reserved = false;
  if (open && open.pull_request === null) {
    // The request that created this row died before recording its pull request. Claiming it by its timestamp lets only one request take it over.
    const claimed = await env.DB.prepare("UPDATE submissions SET created = ? WHERE id = ? AND pull_request IS NULL AND created = ?").bind(now(), open.id, open.created).run();
    if (claimed.meta.changes === 0) throw opening;
  } else if (open) {
    const state = await pullRequestState(env, fetchFn, open.pull_request!).catch((error) => {
      console.error(error);
      throw unavailable();
    });
    if (state !== "open") throw new HttpError(409, `Pull request #${open.pull_request} is already ${state}; the review outcome has not reached the server yet.`);
  } else {
    // The limit is part of the insert, so concurrent requests cannot both take the last slot. Submissions
    // whose pull request was never recorded and that are past STALE_SECONDS can be taken over, so they do not count.
    const room = `(SELECT COUNT(*) FROM submissions WHERE player = ? AND status = 'open' AND (pull_request IS NOT NULL OR created >= ?)) < ${MAX_OPEN}`;
    const roomBinds = [player.id, now() - STALE_SECONDS];
    const insert = env.DB.prepare(`INSERT INTO submissions (level, version, player, status, created, sha256, title) SELECT ?, ?, ?, 'open', ?, ?, ? WHERE ${room}`).bind(
      level_id, version, player.id, now(), sha256, checked.title, ...roomBinds,
    );
    let changes: number;
    try {
      const results = isNewLevel
        ? await env.DB.batch([env.DB.prepare(`INSERT INTO levels (id, owner, based_on, created) SELECT ?, ?, ?, ? WHERE ${room}`).bind(level_id, player.id, basedOn, now(), ...roomBinds), insert])
        : [await insert.run()];
      changes = results.at(-1)!.meta.changes;
    } catch (error) {
      // one_open_per_level: a concurrent request opened this level first.
      if (isNewLevel || !(await selectOpen(env, level_id))) throw error;
      throw opening;
    }
    if (changes === 0) throw new HttpError(429, `At most ${MAX_OPEN} submissions can be open at once.`);
    reserved = true;
    open = await selectOpen(env, level_id);
  }

  const author = row?.owner ?? player.id;
  const parent = row ? row.based_on : basedOn;
  const published = (row?.latest ?? 0) > 0;
  let result: { pullRequest: number; branch: string };
  try {
    result = await openOrUpdatePullRequest(env, fetchFn, {
      id: level_id,
      version,
      level: levelText,
      demo: demoBytes,
      // Every version's commit starts from the default branch, so meta.json is needed until a version has been merged.
      meta: published ? null : `${JSON.stringify({ author, ...(parent ? { based_on: parent } : {}) })}\n`,
      title: `${checked.title} (${level_id} v${version})`,
      body: `Version ${version} of ${level_id}\nAuthor: ${author}${parent ? `\nBased on: ${parent}` : ""}`,
      pullRequest: open!.pull_request,
    });
  } catch (error) {
    console.error(error);
    // Nothing is published yet: a row this request reserved must not block the level, so release it.
    if (reserved) {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM submissions WHERE id = ?").bind(open!.id),
        ...(isNewLevel ? [env.DB.prepare("DELETE FROM levels WHERE id = ?").bind(level_id)] : []),
      ]);
    }
    throw unavailable();
  }

  // The pull request exists from here on, so the row is never deleted: the webhook links it by branch if recording fails.
  for (let attempt = 1; ; attempt++) {
    try {
      await env.DB.prepare("UPDATE submissions SET pull_request = ?, branch = ?, sha256 = ?, title = ? WHERE id = ?").bind(result.pullRequest, result.branch, sha256, checked.title, open!.id).run();
      break;
    } catch (error) {
      console.error(error);
      if (attempt === RECORD_ATTEMPTS) throw new HttpError(502, `Pull request #${result.pullRequest} was opened but could not be recorded; it will be linked when GitHub reports on it.`);
    }
  }
  return Response.json({ level_id, version, pull_request: result.pullRequest }, { status: open!.pull_request === null ? 201 : 200 });
}

export async function getMySubmissions(request: Request, env: Env): Promise<Response> {
  const player = await requirePlayer(request, env);
  const { results } = await env.DB.prepare(
    "SELECT level AS level_id, version, status, comment, pull_request, title FROM submissions WHERE player = ? ORDER BY id DESC",
  )
    .bind(player.id)
    .all();
  return Response.json(results);
}

/** `index.json` as the bot publishes it: levels that are listed and have an approved version. */
async function buildIndex(env: Env): Promise<string> {
  const [levels, versions] = await env.DB.batch<{ id: string; title: string; author: string; latest: number; level: string; version: number; sha256: string }>([
    env.DB.prepare(
      `SELECT l.id, l.title, p.name AS author, l.latest FROM levels l JOIN players p ON p.id = l.owner
       WHERE l.hidden = 0 AND l.id NOT IN (SELECT level FROM hidden_levels) AND l.latest > 0 ORDER BY l.id`,
    ),
    env.DB.prepare("SELECT level, version, sha256 FROM versions ORDER BY level, version"),
  ]);
  const entries = levels!.results.map(({ id, title, author, latest }) => ({
    id,
    title,
    author,
    latest,
    versions: versions!.results.filter((v) => v.level === id).map(({ version, sha256 }) => ({ version, sha256 })),
  }));
  return `${JSON.stringify({ levels: entries }, null, 2)}\n`;
}

export const rebuildIndex = (env: Env, fetchFn: typeof fetch) => commitIndex(env, fetchFn, () => buildIndex(env));

/** HMAC-SHA-256 of the raw body under the webhook secret; `verify` compares in constant time. */
async function validSignature(env: Env, body: Uint8Array<ArrayBuffer>, header: string | null): Promise<boolean> {
  const hex = header?.match(/^sha256=([0-9a-f]{64})$/)?.[1];
  if (!hex || !env.GITHUB_WEBHOOK_SECRET) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.GITHUB_WEBHOOK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  return crypto.subtle.verify("HMAC", key, Uint8Array.from(hex.match(/../g)!, (byte) => parseInt(byte, 16)), body);
}

/** The submission of a pull request: by number, else by its `submission/<id>` branch when the request that opened it never recorded the number. A fork's branch of that name does not count. */
async function findSubmission(env: Env, pull: PullRequest): Promise<SubmissionRow | null> {
  const byNumber = await env.DB.prepare("SELECT * FROM submissions WHERE pull_request = ?").bind(pull.number).first<SubmissionRow>();
  if (byNumber) return byNumber;
  const level = pull.head?.repo?.full_name === env.LEVELS_REPO ? pull.head.ref?.match(/^submission\/(lvl_[a-z0-9]{10})$/)?.[1] : undefined;
  const byBranch = level ? await env.DB.prepare("SELECT * FROM submissions WHERE level = ? AND pull_request IS NULL ORDER BY id DESC").bind(level).first<SubmissionRow>() : null;
  if (!byBranch) return null;
  await env.DB.prepare("UPDATE submissions SET pull_request = ?, branch = ? WHERE id = ? AND pull_request IS NULL").bind(pull.number, pull.head!.ref, byBranch.id).run();
  return { ...byBranch, pull_request: pull.number };
}

async function closePullRequest(env: Env, fetchFn: typeof fetch, pull: PullRequest): Promise<boolean> {
  const row = await findSubmission(env, pull);
  if (!row) return false;
  if (pull.merged) {
    if (row.status !== "approved") {
      // The version's hash is the merged file's, not what the player uploaded.
      const path = `levels/${row.level}/v${row.version}.json`;
      const file = await getFile(env, fetchFn, path);
      if (!file) throw new Error(`${path} is missing on the default branch of a merged pull request.`);
      const sha256 = await sha256Hex(file.bytes);
      // One transaction, each statement guarded by the submission not being decided yet: a repeated delivery changes nothing.
      // A hash that is already published makes the versions insert fail and roll everything back, leaving the submission undecided.
      const undecided = "(SELECT status FROM submissions WHERE id = ?1) IN ('open', 'rejected')";
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO versions (level, version, sha256, approved) SELECT level, version, ?3, ?2 FROM submissions WHERE id = ?1 AND ${undecided}`).bind(row.id, now(), sha256),
        env.DB.prepare(
          `UPDATE levels SET latest = (SELECT version FROM submissions WHERE id = ?1), title = (SELECT title FROM submissions WHERE id = ?1)
           WHERE id = (SELECT level FROM submissions WHERE id = ?1) AND ${undecided}`,
        ).bind(row.id),
        env.DB.prepare(`UPDATE submissions SET status = 'approved', decided = ?2, comment = NULL, sha256 = ?3 WHERE id = ?1 AND status IN ('open', 'rejected')`).bind(row.id, now(), sha256),
      ]);
    }
    // Also on a repeated delivery: it completes an index commit that failed the first time, and is a no-op otherwise.
    await rebuildIndex(env, fetchFn);
  } else if (row.status === "open") {
    const comment = (await lastComment(env, fetchFn, pull.number))?.slice(0, MAX_COMMENT) ?? null;
    await env.DB.prepare("UPDATE submissions SET status = 'rejected', decided = ?, comment = ? WHERE id = ? AND status = 'open'").bind(now(), comment, row.id).run();
  }
  return true;
}

/** A closed pull request that is reopened is under review again, unless the level has meanwhile been submitted anew. */
async function reopenPullRequest(env: Env, pull: PullRequest): Promise<boolean> {
  const row = await findSubmission(env, pull);
  if (!row) return false;
  await env.DB.prepare(
    `UPDATE submissions SET status = 'open', decided = NULL, comment = NULL
     WHERE id = ?1 AND status = 'rejected' AND NOT EXISTS (SELECT 1 FROM submissions WHERE level = ?2 AND status = 'open')`,
  )
    .bind(row.id, row.level)
    .run();
  return true;
}

async function refreshHidden(env: Env, fetchFn: typeof fetch): Promise<void> {
  const file = await getFile(env, fetchFn, "hidden.txt");
  const ids = new Set((file?.text ?? "").split("\n").map((line) => line.trim()).filter((line) => LEVEL_ID.test(line)));
  await env.DB.batch([
    env.DB.prepare("DELETE FROM hidden_levels"),
    ...[...ids].map((id) => env.DB.prepare("INSERT INTO hidden_levels (level) VALUES (?)").bind(id)),
    env.DB.prepare("UPDATE levels SET hidden = id IN (SELECT level FROM hidden_levels)"),
  ]);
  await rebuildIndex(env, fetchFn);
}

interface PullRequest {
  number: number;
  merged: boolean;
  head?: { ref?: string; repo?: { full_name?: string } };
}

/** The parts of a delivery this server reads. */
interface WebhookPayload {
  action?: string;
  ref?: string;
  repository?: { full_name?: string };
  pull_request?: { number?: number; merged?: boolean; head?: { ref?: string; repo?: { full_name?: string } } };
  commits?: { added?: string[]; modified?: string[]; removed?: string[] }[];
}

/** GitHub webhook: records pull request outcomes and `hidden.txt` changes. `fetchFn` is the injection point for tests. */
export async function postGithub(request: Request, env: Env, _params: Record<string, string>, fetchFn: typeof fetch = fetch): Promise<Response> {
  const body = await readBytes(request, MAX_WEBHOOK_BYTES);
  if (!(await validSignature(env, body, request.headers.get("X-Hub-Signature-256")))) throw new HttpError(401, "The webhook signature was not accepted.");
  const event = request.headers.get("X-GitHub-Event");
  if (event === "ping") return Response.json({ ok: true });
  let payload: WebhookPayload | null;
  try {
    payload = JSON.parse(new TextDecoder().decode(body));
  } catch {
    throw new HttpError(400, "The request body is not valid JSON.");
  }
  // The App may be installed on other repositories; only the levels repository counts.
  if (payload?.repository?.full_name !== env.LEVELS_REPO) return new Response(null, { status: 204 });

  let handled = false;
  const number = payload.pull_request?.number;
  if (event === "pull_request" && typeof number === "number" && (payload.action === "closed" || payload.action === "reopened")) {
    const pull = { number, merged: payload.pull_request?.merged === true, head: payload.pull_request?.head };
    handled = payload.action === "closed" ? await closePullRequest(env, fetchFn, pull) : await reopenPullRequest(env, pull);
  } else if (event === "push" && payload.ref === "refs/heads/main") {
    const touched = (payload.commits ?? []).some((commit) => [commit.added, commit.modified, commit.removed].some((files) => files?.includes("hidden.txt")));
    if (touched) {
      await refreshHidden(env, fetchFn);
      handled = true;
    }
  }
  return handled ? Response.json({ ok: true }) : new Response(null, { status: 204 });
}
