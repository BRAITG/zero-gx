/**
 * Worker bindings. Secrets are set with `wrangler secret put` and are never in wrangler.toml:
 * - SESSION_KEY: HMAC key for session tokens (any long random string).
 * - GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET: the OAuth web client that Play Games server auth codes are issued for.
 * - PLAY_SERVICE_ACCOUNT: the service-account JSON key (as text) allowed to call the Play Integrity API.
 */
export interface Env {
  DB: D1Database;
  DEMOS: R2Bucket;
  LEVELS_REPO: string;
  ALLOW_TEST_VERIFIER: string;
  SESSION_KEY: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  PLAY_SERVICE_ACCOUNT: string;
}
