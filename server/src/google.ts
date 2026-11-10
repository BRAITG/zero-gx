import { base64url, fromBase64url } from "./util";

const TOKEN_URL = "https://oauth2.googleapis.com/token";

export async function serviceAccountAssertion(accountJson: string, scope: string): Promise<string> {
  const { client_email, private_key } = JSON.parse(accountJson);
  const der = fromBase64url(private_key.replace(/-----[A-Z ]+-----|\s/g, "").replace(/\+/g, "-").replace(/\//g, "_"));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const iat = Math.floor(Date.now() / 1000);
  const encode = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned =
    `${encode({ alg: "RS256", typ: "JWT" })}.` +
    encode({ iss: client_email, scope, aud: TOKEN_URL, iat, exp: iat + 3600 });
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(signature))}`;
}
