import type { Env } from "./env";
import { HttpError, readJson } from "./http";
import { base64url, fromBase64url, randomId } from "./util";
import { type Verifier, verifierFor } from "./verify";

const NONCE_SECONDS = 5 * 60;
const SESSION_SECONDS = 7 * 24 * 60 * 60;

export interface Player {
  id: string;
  name: string;
  banned: number;
  created: number;
}

const now = () => Math.floor(Date.now() / 1000);

/** 429 when the client IP is over the limit of the unauthenticated routes. */
async function limitAuth(request: Request, env: Env): Promise<void> {
  const outcome = await env.AUTH_LIMITER?.limit({ key: request.headers.get("cf-connecting-ip") ?? "unknown" });
  if (outcome && !outcome.success) throw new HttpError(429, "Too many requests; try again in a minute.");
}

export async function getNonce(request: Request, env: Env): Promise<Response> {
  await limitAuth(request, env);
  const nonce = base64url(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.batch([
    env.DB.prepare("DELETE FROM nonces WHERE expires <= ?").bind(now()),
    env.DB.prepare("INSERT INTO nonces (nonce, expires) VALUES (?, ?)").bind(nonce, now() + NONCE_SECONDS),
  ]);
  return Response.json({ nonce });
}

/** Deletes the nonce; false when it is unknown, expired or already used. */
async function consumeNonce(env: Env, nonce: string): Promise<boolean> {
  const result = await env.DB.prepare("DELETE FROM nonces WHERE nonce = ? AND expires > ?").bind(nonce, now()).run();
  return result.meta.changes === 1;
}

async function hmacKey(env: Env, usage: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", new TextEncoder().encode(env.SESSION_KEY), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
}

/** `base64url({pid, exp}).base64url(HMAC-SHA256)`; `exp` is Unix seconds. */
export async function signSession(env: Env, playerId: string, exp = now() + SESSION_SECONDS): Promise<string> {
  const payload = base64url(new TextEncoder().encode(JSON.stringify({ pid: playerId, exp })));
  const signature = await crypto.subtle.sign("HMAC", await hmacKey(env, "sign"), new TextEncoder().encode(payload));
  return `${payload}.${base64url(new Uint8Array(signature))}`;
}

/** The player id of a valid, unexpired token, or null. */
async function verifySession(env: Env, token: string): Promise<string | null> {
  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra !== undefined) return null;
  try {
    const valid = await crypto.subtle.verify("HMAC", await hmacKey(env, "verify"), fromBase64url(signature), new TextEncoder().encode(payload));
    if (!valid) return null;
    const { pid, exp } = JSON.parse(new TextDecoder().decode(fromBase64url(payload)));
    return typeof pid === "string" && typeof exp === "number" && exp > now() ? pid : null;
  } catch {
    return null;
  }
}

/** The signed-in player from `Authorization: Bearer <token>`; 401 when missing, invalid or expired, 403 when banned. */
export async function requirePlayer(request: Request, env: Env): Promise<Player> {
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
  const id = token ? await verifySession(env, token) : null;
  const player = id ? await env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first<Player>() : null;
  if (!player) throw new HttpError(401, "Sign in again.");
  if (player.banned) throw new HttpError(403, "This player is banned.");
  return player;
}

/** Checks the fresh Play Integrity token of `X-Integrity`, bound to the one-time nonce of `X-Nonce`; 403 on any failure. */
export async function requireIntegrity(request: Request, env: Env, verifier: Verifier = verifierFor(env)): Promise<void> {
  const token = request.headers.get("X-Integrity");
  const nonce = request.headers.get("X-Nonce");
  const fail = new HttpError(403, "The integrity check failed.");
  if (!token || !nonce || !(await consumeNonce(env, nonce))) throw fail;
  await verifier.integrity(token, nonce).catch(() => {
    throw fail;
  });
}

export async function postSession(request: Request, env: Env): Promise<Response> {
  await limitAuth(request, env);
  const { authCode, integrityToken, nonce } = await readJson(request);
  if (typeof authCode !== "string" || typeof integrityToken !== "string" || typeof nonce !== "string") {
    throw new HttpError(400, "authCode, integrityToken and nonce are required.");
  }
  if (!(await consumeNonce(env, nonce))) throw new HttpError(401, "The nonce is unknown, expired or already used.");
  const verifier = verifierFor(env);
  await verifier.integrity(integrityToken, nonce).catch(() => {
    throw new HttpError(403, "The integrity check failed.");
  });
  const identity = await verifier.player(authCode).catch(() => {
    throw new HttpError(401, "The sign-in code was not accepted.");
  });

  const account = await env.DB.prepare("SELECT player FROM accounts WHERE provider = 'play_games' AND provider_id = ?").bind(identity.providerId).first<{ player: string }>();
  let id = account?.player;
  if (id) {
    await env.DB.prepare("UPDATE players SET name = ? WHERE id = ?").bind(identity.name, id).run();
  } else {
    id = randomId("p_", 16);
    // Two first sign-ins of one new account racing fail on the accounts key; the app retries.
    await env.DB.batch([
      env.DB.prepare("INSERT INTO players (id, name, created) VALUES (?, ?, ?)").bind(id, identity.name, now()),
      env.DB.prepare("INSERT INTO accounts (provider, provider_id, player) VALUES ('play_games', ?, ?)").bind(identity.providerId, id),
    ]);
  }
  const player = await env.DB.prepare("SELECT banned FROM players WHERE id = ?").bind(id).first<{ banned: number }>();
  if (player?.banned) throw new HttpError(403, "This player is banned.");
  return Response.json({ token: await signSession(env, id), player: { id, name: identity.name } });
}
