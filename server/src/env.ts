/**
 * Worker bindings. Secrets are set with `wrangler secret put` and are never in wrangler.toml:
 * - SESSION_KEY: HMAC key for session tokens (any long random string).
 * - GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET: the OAuth web client that Play Games server auth codes are issued for.
 * - PLAY_SERVICE_ACCOUNT: the service-account JSON key (as text) allowed to call the Play Integrity API.
 * - ADMIN_TOKEN: bearer token the release workflow uses to register the official levels.
 * - GITHUB_APP_ID, GITHUB_INSTALLATION_ID: the levels repository's GitHub App and its installation.
 * - GITHUB_APP_KEY: the App's private key as PKCS#8 PEM (GitHub issues PKCS#1; convert with `openssl pkcs8 -topk8 -nocrypt`).
 * - GITHUB_WEBHOOK_SECRET: the secret GitHub signs webhook deliveries with.
 */
export interface Env {
  DB: D1Database;
  DEMOS: R2Bucket;
  /** Rate-limiting binding for the unauthenticated routes; absent in tests and plain local runs, which skips the check. */
  AUTH_LIMITER?: RateLimit;
  LEVELS_REPO: string;
  ALLOW_TEST_VERIFIER: string;
  SESSION_KEY: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  PLAY_SERVICE_ACCOUNT: string;
  ADMIN_TOKEN: string;
  GITHUB_APP_ID: string;
  GITHUB_APP_KEY: string;
  GITHUB_INSTALLATION_ID: string;
  GITHUB_WEBHOOK_SECRET: string;
}
