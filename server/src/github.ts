import type { Env } from "./env";
import { base64url, fromBase64url } from "./util";

const API = "https://api.github.com";
const DEFAULT_BRANCH = "main";

export class GithubError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

type GithubEnv = Pick<Env, "GITHUB_APP_ID" | "GITHUB_APP_KEY" | "GITHUB_INSTALLATION_ID" | "LEVELS_REPO">;
/** `fetchFn` is the injection point for tests. */
type Fetch = typeof fetch;
type Call = <T>(method: string, path: string, body?: unknown) => Promise<T>;

async function request<T>(fetchFn: Fetch, method: string, path: string, token: string, body?: unknown): Promise<T> {
  const response = await fetchFn(`${API}${path}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "zero-gx",
      Authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw new GithubError(response.status, `GitHub answered ${response.status} to ${method} ${path}.`);
  return (response.status === 204 ? null : await response.json()) as T;
}

/** The App's JWT, valid for 10 minutes at most; the 60 s head start absorbs clock skew. */
async function appJwt(env: GithubEnv): Promise<string> {
  if (env.GITHUB_APP_KEY.includes("BEGIN RSA PRIVATE KEY")) {
    throw new Error("GITHUB_APP_KEY is a PKCS#1 key; convert it with `openssl pkcs8 -topk8 -nocrypt -in key.pem`.");
  }
  const der = fromBase64url(env.GITHUB_APP_KEY.replace(/-----[A-Z ]+-----|\s/g, "").replace(/\+/g, "-").replace(/\//g, "_"));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const iat = Math.floor(Date.now() / 1000);
  const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({ iat: iat - 60, exp: iat + 540, iss: env.GITHUB_APP_ID })}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}

let cached: { identity: string; token: string; refreshAt: number } | undefined;

/** An installation access token, reused until a minute before it expires. */
export async function installationToken(env: GithubEnv, fetchFn: Fetch = fetch): Promise<string> {
  const identity = `${env.GITHUB_APP_ID}\n${env.GITHUB_INSTALLATION_ID}\n${env.GITHUB_APP_KEY}`;
  if (cached?.identity === identity && cached.refreshAt > Date.now()) return cached.token;
  const { token, expires_at } = await request<{ token: string; expires_at: string }>(fetchFn, "POST", `/app/installations/${env.GITHUB_INSTALLATION_ID}/access_tokens`, await appJwt(env));
  cached = { identity, token, refreshAt: Date.parse(expires_at) - 60_000 };
  return token;
}

async function client(env: GithubEnv, fetchFn: Fetch): Promise<{ gh: Call; repo: string }> {
  const token = await installationToken(env, fetchFn);
  return { gh: (method, path, body) => request(fetchFn, method, path, token, body), repo: `/repos/${env.LEVELS_REPO}` };
}

/** Standard base64; chunked because spreading a whole demo into `fromCharCode` overflows the stack. */
function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

export interface Submission {
  id: string;
  version: number;
  /** The level file's text, exactly as received. */
  level: string;
  demo: Uint8Array;
  /** Contents of `meta.json`; null when the level already has one on the default branch. */
  meta: string | null;
  title: string;
  body: string;
  /** The open pull request to update, or null to open one. */
  pullRequest: number | null;
}

/** Commits the submission's files on top of the default branch, on `submission/<id>`, and opens or updates the pull request. */
export async function openOrUpdatePullRequest(env: GithubEnv, fetchFn: Fetch, submission: Submission): Promise<{ pullRequest: number; branch: string }> {
  const { gh, repo } = await client(env, fetchFn);
  const { id, version } = submission;
  const branch = `submission/${id}`;
  const base = (await gh<{ object: { sha: string } }>("GET", `${repo}/git/ref/heads/${DEFAULT_BRANCH}`)).object.sha;
  const baseCommit = await gh<{ tree: { sha: string } }>("GET", `${repo}/git/commits/${base}`);
  const blob = async (path: string, content: string, encoding: "utf-8" | "base64") => ({
    path,
    mode: "100644",
    type: "blob",
    sha: (await gh<{ sha: string }>("POST", `${repo}/git/blobs`, { content, encoding })).sha,
  });
  const entries = [
    await blob(`levels/${id}/v${version}.json`, submission.level, "utf-8"),
    await blob(`proof/${id}/v${version}.demo.gz`, base64(submission.demo), "base64"),
  ];
  if (submission.meta !== null) entries.push(await blob(`levels/${id}/meta.json`, submission.meta, "utf-8"));
  const tree = await gh<{ sha: string }>("POST", `${repo}/git/trees`, { base_tree: baseCommit.tree.sha, tree: entries });
  const commit = await gh<{ sha: string }>("POST", `${repo}/git/commits`, { message: `Submit ${id} v${version}`, tree: tree.sha, parents: [base] });

  const moveBranch = () => gh("PATCH", `${repo}/git/refs/heads/${branch}`, { sha: commit.sha, force: true });
  if (submission.pullRequest !== null) await moveBranch();
  else {
    // A rejected submission leaves its branch behind; the next one reuses it.
    await gh("POST", `${repo}/git/refs`, { ref: `refs/heads/${branch}`, sha: commit.sha }).catch((error) => {
      if (error instanceof GithubError && error.status === 422) return moveBranch();
      throw error;
    });
  }

  if (submission.pullRequest !== null) {
    await gh("PATCH", `${repo}/pulls/${submission.pullRequest}`, { title: submission.title, body: submission.body });
    return { pullRequest: submission.pullRequest, branch };
  }
  const pull = await gh<{ number: number }>("POST", `${repo}/pulls`, { title: submission.title, head: branch, base: DEFAULT_BRANCH, body: submission.body });
  return { pullRequest: pull.number, branch };
}

/** A file's text and blob sha on the default branch; null when it does not exist. */
export async function getFile(env: GithubEnv, fetchFn: Fetch, path: string): Promise<{ text: string; sha: string } | null> {
  const { gh, repo } = await client(env, fetchFn);
  const file = await gh<{ content: string; sha: string } | null>("GET", `${repo}/contents/${path}?ref=${DEFAULT_BRANCH}`).catch((error) => {
    if (error instanceof GithubError && error.status === 404) return null;
    throw error;
  });
  // GitHub wraps the base64 content in newlines, which atob ignores.
  return file && { text: new TextDecoder().decode(Uint8Array.from(atob(file.content), (c) => c.charCodeAt(0))), sha: file.sha };
}

/** Writes `index.json` on the default branch unless it already holds `content`; refetches once on a conflicting write. */
export async function commitIndex(env: GithubEnv, fetchFn: Fetch, content: string): Promise<void> {
  const { gh, repo } = await client(env, fetchFn);
  for (let attempt = 0; ; attempt++) {
    const current = await getFile(env, fetchFn, "index.json");
    if (current?.text === content) return;
    try {
      await gh("PUT", `${repo}/contents/index.json`, { message: "Update index", content: base64(new TextEncoder().encode(content)), sha: current?.sha, branch: DEFAULT_BRANCH });
      return;
    } catch (error) {
      if (attempt > 0 || !(error instanceof GithubError && error.status === 409)) throw error;
    }
  }
}

/** Body of the pull request's most recent comment, or null. Only the first 100 comments are read. */
export async function lastComment(env: GithubEnv, fetchFn: Fetch, pullRequest: number): Promise<string | null> {
  const { gh, repo } = await client(env, fetchFn);
  const comments: { body?: string }[] = await gh("GET", `${repo}/issues/${pullRequest}/comments?per_page=100`);
  return comments.at(-1)?.body ?? null;
}
