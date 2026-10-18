import type { Env } from "./env";
import { base64url, fromBase64url } from "./util";

export interface Verifier {
  player(authCode: string): Promise<{ providerId: string; name: string }>;
  /** Resolves when the integrity token is acceptable and bound to `nonce`; rejects otherwise. */
  integrity(token: string, nonce: string): Promise<void>;
}

/** The test verifier is only reachable when the deployment sets ALLOW_TEST_VERIFIER to "1". */
export function verifierFor(env: Env): Verifier {
  return env.ALLOW_TEST_VERIFIER === "1" ? new TestVerifier() : new GoogleVerifier(env);
}

/** Codes are `test:<id>:<name>`, integrity tokens `ok:<nonce>`. */
export class TestVerifier implements Verifier {
  async player(authCode: string) {
    const [prefix, providerId, ...name] = authCode.split(":");
    if (prefix !== "test" || !providerId || name.length === 0) throw new Error("Not a test code.");
    return { providerId, name: name.join(":") };
  }

  async integrity(token: string, nonce: string) {
    if (token !== `ok:${nonce}`) throw new Error("Integrity token is for another nonce.");
  }
}

const PACKAGE = "com.braitg.zerogx";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const MAX_AGE_MS = 5 * 60 * 1000;

type GoogleSecrets = Pick<Env, "GOOGLE_CLIENT_ID" | "GOOGLE_CLIENT_SECRET" | "PLAY_SERVICE_ACCOUNT">;

export class GoogleVerifier implements Verifier {
  constructor(
    private readonly secrets: GoogleSecrets,
    // Looked up per call so tests can replace the global fetch.
    private readonly fetchFn: typeof fetch = (input, init) => fetch(input, init),
  ) {}

  private async json(input: string, init: RequestInit): Promise<any> {
    const response = await this.fetchFn(input, init);
    if (!response.ok) throw new Error(`${input} answered ${response.status}.`);
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

  async integrity(token: string, nonce: string) {
    const accessToken = await this.serviceAccountToken();
    const decoded = await this.json(`https://playintegrity.googleapis.com/v1/${PACKAGE}:decodeIntegrityToken`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ integrity_token: token }),
    });
    const payload = decoded.tokenPayloadExternal;
    const request = payload?.requestDetails;
    if (request?.requestPackageName !== PACKAGE) throw new Error("Token is for another app.");
    if (request.nonce !== nonce) throw new Error("Token is for another nonce.");
    if (!(Math.abs(Date.now() - Number(request.timestampMillis)) <= MAX_AGE_MS)) throw new Error("Token is stale.");
    if (payload.appIntegrity?.appRecognitionVerdict !== "PLAY_RECOGNIZED") throw new Error("App is not recognized by Play.");
    if (!payload.deviceIntegrity?.deviceRecognitionVerdict?.includes("MEETS_BASIC_INTEGRITY")) throw new Error("Device fails basic integrity.");
  }
}
