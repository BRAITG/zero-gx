import type { Env } from "./env";
import { base64url, fromBase64url } from "./util";

/** The device verdict a request needs: "device" for sign-in and submissions, "strong" (hardware-backed) for scores. */
export type DeviceLevel = "device" | "strong";

export interface Verifier {
  player(authCode: string): Promise<{ providerId: string; name: string }>;
  /** Resolves when the integrity token is acceptable, meets `level` and is bound to `nonce`; rejects otherwise. */
  integrity(token: string, nonce: string, level: DeviceLevel): Promise<void>;
}

/** The test verifier is only reachable when the deployment sets ALLOW_TEST_VERIFIER to "1". */
export function verifierFor(env: Env): Verifier {
  return env.ALLOW_TEST_VERIFIER === "1" ? new TestVerifier() : new GoogleVerifier(env);
}

/** Codes are `test:<id>:<name>`; integrity tokens are `ok:<nonce>` (device integrity) or `strong:<nonce>` (strong). */
export class TestVerifier implements Verifier {
  async player(authCode: string) {
    const [prefix, providerId, ...name] = authCode.split(":");
    if (prefix !== "test" || !providerId || name.length === 0) throw new Error("Not a test code.");
    return { providerId, name: name.join(":") };
  }

  async integrity(token: string, nonce: string, level: DeviceLevel) {
    if (token === `strong:${nonce}`) return;
    if (token !== `ok:${nonce}`) throw new Error("Integrity token is for another nonce.");
    if (level === "strong") throw new Error("Device does not meet strong integrity.");
  }
}

const PACKAGE = "dev.braitg.zerogx";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const MAX_AGE_MS = 5 * 60 * 1000;

type GoogleSecrets = Pick<Env, "GOOGLE_CLIENT_ID" | "GOOGLE_CLIENT_SECRET" | "PLAY_SERVICE_ACCOUNT">;

/** Only fixed codes and HTTP status may reach diagnostics, never tokens, keys or Google messages. */
class VerificationFailure extends Error {
  constructor(readonly reason: string, readonly details: { status?: number; googleReason?: string } = {}) {
    super(reason);
  }
}

const GOOGLE_REASONS: Record<string, true> = {
  SERVICE_DISABLED: true, CONSUMER_INVALID: true, IAM_PERMISSION_DENIED: true, BILLING_DISABLED: true,
  ACCESS_TOKEN_SCOPE_INSUFFICIENT: true, PERMISSION_DENIED: true, INVALID_ARGUMENT: true, UNAUTHENTICATED: true,
  invalid_grant: true, invalid_client: true, unauthorized_client: true, invalid_scope: true,
};

export class GoogleVerifier implements Verifier {
  constructor(
    private readonly secrets: GoogleSecrets,
    // Looked up per call so tests can replace the global fetch.
    private readonly fetchFn: typeof fetch = (input, init) => fetch(input, init),
  ) {}

  private async json(input: string, init: RequestInit): Promise<any> {
    const response = await this.fetchFn(input, init);
    if (!response.ok) {
      const body: unknown = await response.json().catch(() => null);
      let reason: unknown;
      if (body && typeof body === "object" && "error" in body) {
        const error = body.error;
        reason = error;
        if (error && typeof error === "object" && "details" in error && Array.isArray(error.details)) {
          const info: unknown = error.details.find((detail: unknown) =>
            detail && typeof detail === "object" && "@type" in detail && detail["@type"] === "type.googleapis.com/google.rpc.ErrorInfo");
          if (info && typeof info === "object" && "reason" in info) reason = info.reason;
        }
      }
      throw new VerificationFailure("google_api", {
        status: response.status,
        googleReason: typeof reason === "string" && Object.hasOwn(GOOGLE_REASONS, reason) ? reason : "unknown",
      });
    }
    return response.json();
  }

  private async token(form: Record<string, string>): Promise<string> {
    const { access_token } = await this.json(TOKEN_URL, { method: "POST", body: new URLSearchParams(form) });
    if (typeof access_token !== "string") throw new Error("No access token.");
    return access_token;
  }

  async player(authCode: string) {
    const accessToken = await this.token({
      grant_type: "authorization_code",
      code: authCode,
      client_id: this.secrets.GOOGLE_CLIENT_ID,
      client_secret: this.secrets.GOOGLE_CLIENT_SECRET,
      redirect_uri: "",
    });
    const me = await this.json("https://games.googleapis.com/games/v1/players/me", { headers: { Authorization: `Bearer ${accessToken}` } });
    if (typeof me.playerId !== "string" || typeof me.displayName !== "string") throw new Error("Unexpected Play Games player.");
    return { providerId: me.playerId, name: me.displayName };
  }

  /** An OAuth access token for the service account, from a JWT signed with its private key. */
  private async serviceAccountToken(): Promise<string> {
    const { client_email, private_key } = JSON.parse(this.secrets.PLAY_SERVICE_ACCOUNT);
    const der = fromBase64url(private_key.replace(/-----[A-Z ]+-----|\s/g, "").replace(/\+/g, "-").replace(/\//g, "_"));
    const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    const iat = Math.floor(Date.now() / 1000);
    const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));
    const unsigned =
      `${encode({ alg: "RS256", typ: "JWT" })}.` +
      encode({ iss: client_email, scope: "https://www.googleapis.com/auth/playintegrity", aud: TOKEN_URL, iat, exp: iat + 3600 });
    const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
    return this.token({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${base64url(new Uint8Array(signature))}` });
  }

  async integrity(token: string, nonce: string, level: DeviceLevel) {
    let stage = "service_account";
    try {
      const accessToken = await this.serviceAccountToken();
      stage = "decode";
      const decoded = await this.json(`https://playintegrity.googleapis.com/v1/${PACKAGE}:decodeIntegrityToken`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ integrity_token: token }),
      });
      stage = "verdict";
      const payload = decoded.tokenPayloadExternal;
      const request = payload?.requestDetails;
      if (request?.requestPackageName !== PACKAGE) throw new VerificationFailure("package_mismatch");
      if (request.nonce !== nonce) throw new VerificationFailure("nonce_mismatch");
      if (!(Math.abs(Date.now() - Number(request.timestampMillis)) <= MAX_AGE_MS)) throw new VerificationFailure("stale");
      if (payload.appIntegrity?.appRecognitionVerdict !== "PLAY_RECOGNIZED") throw new VerificationFailure("app_unrecognized");
      const required = level === "strong" ? "MEETS_STRONG_INTEGRITY" : "MEETS_DEVICE_INTEGRITY";
      if (!payload.deviceIntegrity?.deviceRecognitionVerdict?.includes(required)) throw new VerificationFailure(`device_${level}`);
    } catch (error) {
      const known = error instanceof VerificationFailure;
      console.warn(JSON.stringify({
        event: "integrity_rejected", stage, reason: known ? error.reason : "verification_error",
        ...(known ? error.details : {}),
      }));
      throw error;
    }
  }
}
