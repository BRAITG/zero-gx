import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../../src/env";
import worker from "../../src/worker";

const PACKAGE = "dev.braitg.zerogx";
const PRODUCT = "remove_ads";
const TOKEN = "test-purchase-token";
const OAUTH_URL = "https://oauth2.googleapis.com/token";
const PUBLISHER_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3";
const PURCHASE_URL = `${PUBLISHER_ROOT}/applications/${PACKAGE}/purchases/productsv2/tokens/${encodeURIComponent(TOKEN)}`;
const ACK_URL = `${PUBLISHER_ROOT}/applications/${PACKAGE}/purchases/products/${PRODUCT}/tokens/${encodeURIComponent(TOKEN)}:acknowledge`;
const PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const GOOGLE_ERROR_BODY = "sensitive-google-error-body";

type FetchCall = { url: string; init?: RequestInit };
type FetchHandler = (call: FetchCall) => Response | Promise<Response>;

let accountFixture: { json: string; privateKeyPem: string; publicKey: CryptoKey } | undefined;

async function serviceAccount() {
  if (!accountFixture) {
    const pair = await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    );
    const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const privateKeyPem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der)).replace(/.{64}/g, "$&\n")}\n-----END PRIVATE KEY-----\n`;
    accountFixture = {
      json: JSON.stringify({ client_email: "purchase-test@example.iam.gserviceaccount.com", private_key: privateKeyPem }),
      privateKeyPem,
      publicKey: pair.publicKey,
    };
  }
  return accountFixture;
}

async function testEnv(patch: Partial<Env> = {}): Promise<Env> {
  return {
    ...env,
    ALLOW_TEST_VERIFIER: "1",
    PLAY_SERVICE_ACCOUNT: (await serviceAccount()).json,
    ...patch,
  };
}

function fakeGoogle(publisher: FetchHandler, oauth: FetchHandler = () => Response.json({ access_token: "test-access-token" })) {
  const calls: FetchCall[] = [];
  vi.stubGlobal("fetch", (async (input: RequestInfo | URL, init?: RequestInit) => {
    const call = { url: String(input), init };
    calls.push(call);
    if (call.url === OAUTH_URL) return oauth(call);
    if (call.url.startsWith(PUBLISHER_ROOT)) return publisher(call);
    return new Response("unexpected upstream URL", { status: 500 });
  }) as typeof fetch);
  return { calls };
}

function purchase(options: {
  state?: string;
  acknowledgement?: string;
  lineItem?: Record<string, unknown>;
  lineItems?: unknown;
} = {}) {
  const lineItem = options.lineItem ?? {
    productId: PRODUCT,
    productOfferDetails: {
      purchaseOptionId: "buy",
      quantity: 1,
      refundableQuantity: 1,
      consumptionState: "CONSUMPTION_STATE_YET_TO_BE_CONSUMED",
    },
  };
  return {
    purchaseStateContext: { purchaseState: options.state ?? "PURCHASED" },
    acknowledgementState: options.acknowledgement ?? "ACKNOWLEDGEMENT_STATE_PENDING",
    productLineItem: options.lineItems ?? [lineItem],
  };
}

function minimalPurchase(state: "PENDING" | "CANCELLED", productId = PRODUCT) {
  return { purchaseStateContext: { purchaseState: state }, productLineItem: [{ productId }] };
}

const method = (call: FetchCall) => call.init?.method ?? "GET";
const publisherCalls = (calls: FetchCall[]) => calls.filter(({ url }) => url.startsWith(PUBLISHER_ROOT));
const acknowledgements = (calls: FetchCall[]) => publisherCalls(calls).filter(({ url }) => url.endsWith(":acknowledge"));
const consumptions = (calls: FetchCall[]) => publisherCalls(calls).filter(({ url }) => url.includes("/consume") || url.endsWith(":consume"));

function postPurchase(body: unknown, e: Env): Promise<Response> {
  return worker.fetch(new Request("https://example.com/purchases/ad-free", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  }), e);
}

async function expectError(response: Response, status: number, code?: string) {
  expect(response.status).toBe(status);
  const body = await response.json() as Record<string, unknown>;
  expect(typeof body.error).toBe("string");
  if (code) expect(body.code).toBe(code);
  else expect(body).not.toHaveProperty("code");
  return body;
}

function decodeBase64url(part: string): Uint8Array<ArrayBuffer> {
  const base64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - base64.length % 4) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("POST /purchases/ad-free", () => {
  it("acknowledges a completed permanent purchase", async () => {
    const { calls } = fakeGoogle((call) => method(call) === "GET" ? Response.json(purchase()) : Response.json({}));
    const response = await postPurchase({ purchaseToken: TOKEN }, await testEnv());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ad_free: true });
    expect(publisherCalls(calls)[0]?.url).toBe(PURCHASE_URL);
    expect(acknowledgements(calls)).toHaveLength(1);
    expect(acknowledgements(calls)[0]?.url).toBe(ACK_URL);
    expect(method(acknowledgements(calls)[0]!)).toBe("POST");
    expect(consumptions(calls)).toHaveLength(0);
  });

  it("restores an already acknowledged purchase", async () => {
    const { calls } = fakeGoogle(() => Response.json(purchase({ acknowledgement: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" })));
    const response = await postPurchase({ purchaseToken: TOKEN }, await testEnv());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ad_free: true });
    expect(acknowledgements(calls)).toHaveLength(0);
    expect(consumptions(calls)).toHaveLength(0);
  });

  it("does not grant pending or revoked purchases", async () => {
    const pendingCalls = fakeGoogle(() => Response.json(purchase({ state: "PENDING" })));
    const pending = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    expect(pending.status).toBe(202);
    expect(await pending.json()).toEqual({ pending: true });
    expect(acknowledgements(pendingCalls.calls)).toHaveLength(0);
    expect(consumptions(pendingCalls.calls)).toHaveLength(0);

    const pendingMinimalCalls = fakeGoogle(() => Response.json(minimalPurchase("PENDING")));
    const pendingMinimal = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    expect(pendingMinimal.status).toBe(202);
    expect(await pendingMinimal.json()).toEqual({ pending: true });
    expect(acknowledgements(pendingMinimalCalls.calls)).toHaveLength(0);
    expect(consumptions(pendingMinimalCalls.calls)).toHaveLength(0);

    const pendingWrongProductCalls = fakeGoogle(() => Response.json(minimalPurchase("PENDING", "other_product")));
    await expectError(await postPurchase({ purchaseToken: TOKEN }, await testEnv()), 404, "purchase_invalid");
    expect(acknowledgements(pendingWrongProductCalls.calls)).toHaveLength(0);
    expect(consumptions(pendingWrongProductCalls.calls)).toHaveLength(0);

    const cancelledCalls = fakeGoogle(() => Response.json(purchase({ state: "CANCELLED" })));
    await expectError(await postPurchase({ purchaseToken: TOKEN }, await testEnv()), 409, "purchase_inactive");
    expect(acknowledgements(cancelledCalls.calls)).toHaveLength(0);
    expect(consumptions(cancelledCalls.calls)).toHaveLength(0);

    const cancelledMinimalCalls = fakeGoogle(() => Response.json(minimalPurchase("CANCELLED")));
    await expectError(await postPurchase({ purchaseToken: TOKEN }, await testEnv()), 409, "purchase_inactive");
    expect(acknowledgements(cancelledMinimalCalls.calls)).toHaveLength(0);
    expect(consumptions(cancelledMinimalCalls.calls)).toHaveLength(0);

    const cancelledWrongProductCalls = fakeGoogle(() => Response.json(minimalPurchase("CANCELLED", "other_product")));
    await expectError(await postPurchase({ purchaseToken: TOKEN }, await testEnv()), 404, "purchase_invalid");
    expect(acknowledgements(cancelledWrongProductCalls.calls)).toHaveLength(0);
    expect(consumptions(cancelledWrongProductCalls.calls)).toHaveLength(0);

    const cancelledMissingIdentityCalls = fakeGoogle(() => Response.json({ purchaseStateContext: { purchaseState: "CANCELLED" } }));
    await expectError(await postPurchase({ purchaseToken: TOKEN }, await testEnv()), 503);
    expect(acknowledgements(cancelledMissingIdentityCalls.calls)).toHaveLength(0);
    expect(consumptions(cancelledMissingIdentityCalls.calls)).toHaveLength(0);
  });

  it("refuses wrong products, rentals, preorders, consumed or quantity-two items, refunds, malformed data, and generic NOT_FOUND", async () => {
    const item = (patch: Record<string, unknown> = {}) => ({
      productId: PRODUCT,
      productOfferDetails: {
        purchaseOptionId: "buy",
        quantity: 1,
        refundableQuantity: 1,
        consumptionState: "CONSUMPTION_STATE_YET_TO_BE_CONSUMED",
        ...patch,
      },
    });
    const cases: { name: string; response: (call: FetchCall) => Response; status: number; code?: string }[] = [
      { name: "another product", response: () => Response.json(purchase({ lineItem: { ...item(), productId: "other_product" } })), status: 404, code: "purchase_invalid" },
      { name: "a rental", response: () => Response.json(purchase({ lineItem: item({ rentOfferDetails: {} }) })), status: 404, code: "purchase_invalid" },
      { name: "a preorder", response: () => Response.json(purchase({ lineItem: item({ preorderOfferDetails: { preorderReleaseTime: "2026-12-01T00:00:00Z" } }) })), status: 404, code: "purchase_invalid" },
      { name: "a consumed item", response: () => Response.json(purchase({ lineItem: item({ consumptionState: "CONSUMPTION_STATE_CONSUMED" }) })), status: 404, code: "purchase_invalid" },
      { name: "quantity and refundable quantity two", response: () => Response.json(purchase({ lineItem: item({ quantity: 2, refundableQuantity: 2 }) })), status: 404, code: "purchase_invalid" },
      { name: "zero refundable quantity", response: () => Response.json(purchase({ lineItem: item({ refundableQuantity: 0 }) })), status: 409, code: "purchase_inactive" },
      { name: "a malformed Google shape", response: () => Response.json(purchase({ lineItems: [] })), status: 503 },
      { name: "a generic structured NOT_FOUND", response: () => Response.json({ error: { code: 404, status: "NOT_FOUND", message: "Requested entity was not found." } }, { status: 404 }), status: 503 },
    ];

    for (const scenario of cases) {
      const { calls } = fakeGoogle(scenario.response);
      const response = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
      const body = await expectError(response, scenario.status, scenario.code);
      expect(body).not.toEqual({ ad_free: true });
      expect(acknowledgements(calls)).toHaveLength(0);
      expect(consumptions(calls)).toHaveLength(0);
    }
  });

  it("treats a generic upstream HTML 404 as unavailable", async () => {
    const { calls } = fakeGoogle(() => new Response("<html>gateway not found</html>", { status: 404 }));
    await expectError(await postPurchase({ purchaseToken: TOKEN }, await testEnv()), 503);
    expect(publisherCalls(calls)).toHaveLength(1);
    expect(acknowledgements(calls)).toHaveLength(0);
    expect(consumptions(calls)).toHaveLength(0);
  });

  it("resolves ambiguous or concurrent acknowledgement by re-reading", async () => {
    let lostResponseReads = 0;
    const recoveredCalls = fakeGoogle((call) => {
      if (method(call) === "GET") {
        lostResponseReads += 1;
        return Response.json(purchase({
          acknowledgement: lostResponseReads === 1 ? "ACKNOWLEDGEMENT_STATE_PENDING" : "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        }));
      }
      throw new Error("acknowledgement response lost");
    });
    const recovered = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    expect(recovered.status).toBe(200);
    expect(await recovered.json()).toEqual({ ad_free: true });
    expect(lostResponseReads).toBe(2);
    expect(acknowledgements(recoveredCalls.calls)).toHaveLength(1);
    expect(consumptions(recoveredCalls.calls)).toHaveLength(0);

    let unresolvedReads = 0;
    const unresolvedCalls = fakeGoogle((call) => {
      if (method(call) === "GET") {
        unresolvedReads += 1;
        return Response.json(purchase());
      }
      return Response.json({ error: "concurrent acknowledgement" }, { status: 409 });
    });
    const unresolved = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    await expectError(unresolved, 503);
    expect(unresolvedReads).toBe(2);
    expect(acknowledgements(unresolvedCalls.calls)).toHaveLength(1);
    expect(consumptions(unresolvedCalls.calls)).toHaveLength(0);
  });

  it("bounds unauthenticated input and rate limits", async () => {
    const { calls } = fakeGoogle(() => Response.json(purchase()));
    const e = await testEnv();
    for (const invalid of ["{", "", "{}", JSON.stringify({ purchaseToken: "" }), JSON.stringify({ purchaseToken: 3 }), JSON.stringify({ purchaseToken: "x".repeat(2049) })]) {
      await expectError(await postPurchase(invalid, e), 400);
    }
    const oversized = JSON.stringify({ purchaseToken: TOKEN, padding: "x".repeat(4096) });
    await expectError(await postPurchase(oversized, e), 413);
    const multibyteBody = JSON.stringify({ purchaseToken: "é".repeat(2048) });
    expect(multibyteBody.length).toBeLessThan(4096);
    expect(new TextEncoder().encode(multibyteBody).byteLength).toBeGreaterThan(4096);
    await expectError(await postPurchase(multibyteBody, e), 413);
    expect(calls).toHaveLength(0);

    const limitedEnv = await testEnv({ AUTH_LIMITER: { limit: async () => ({ success: false }) } });
    await expectError(await postPurchase({ purchaseToken: TOKEN }, limitedEnv), 429);
    expect(calls).toHaveLength(0);
  });

  it("accepts a 2048-character token in a 4096-byte body", async () => {
    const token = "x".repeat(2048);
    const compactBody = JSON.stringify({ purchaseToken: token });
    const body = compactBody + " ".repeat(4096 - compactBody.length);
    expect(token.length).toBe(2048);
    expect(new TextEncoder().encode(body).byteLength).toBe(4096);

    const { calls } = fakeGoogle(() => Response.json(purchase({ acknowledgement: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" })));
    const response = await postPurchase(body, await testEnv());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ad_free: true });
    expect(publisherCalls(calls).some((call) => call.url === `${PUBLISHER_ROOT}/applications/${PACKAGE}/purchases/productsv2/tokens/${encodeURIComponent(token)}`)).toBe(true);
  });

  it("does not leak a token-bearing fetch exception or credential failure", async () => {
    const fixture = await serviceAccount();
    const logged = [
      vi.spyOn(console, "error").mockImplementation(() => {}),
      vi.spyOn(console, "warn").mockImplementation(() => {}),
    ];
    const diagnostics = async (response: Response) => `${await response.text()} ${JSON.stringify(logged.flatMap((spy) => spy.mock.calls))}`;
    const tokenUrl = PURCHASE_URL;
    const { calls } = fakeGoogle(() => {
      throw new Error(`${TOKEN} ${fixture.privateKeyPem} ${GOOGLE_ERROR_BODY} ${tokenUrl}`);
    });
    const transportResponse = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    const transportOutput = await diagnostics(transportResponse.clone());
    await expectError(transportResponse, 503);
    expect(transportOutput).not.toContain(TOKEN);
    expect(transportOutput).not.toContain(fixture.privateKeyPem);
    expect(transportOutput).not.toContain(GOOGLE_ERROR_BODY);
    expect(transportOutput).not.toContain(tokenUrl);
    expect(calls.length).toBeGreaterThan(0);

    const forbiddenCalls = fakeGoogle(() => new Response(GOOGLE_ERROR_BODY, { status: 403 }));
    const forbidden = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    const forbiddenBody = await expectError(forbidden, 503);
    expect(forbiddenBody.code).not.toBe("purchase_inactive");
    expect(acknowledgements(forbiddenCalls.calls)).toHaveLength(0);
    expect(consumptions(forbiddenCalls.calls)).toHaveLength(0);
    expect(await diagnostics(new Response(JSON.stringify(forbiddenBody)))).not.toContain(GOOGLE_ERROR_BODY);

    const oauthFailureCalls = fakeGoogle(() => Response.json({}), () => new Response(GOOGLE_ERROR_BODY, { status: 403 }));
    const oauthFailure = await postPurchase({ purchaseToken: TOKEN }, await testEnv());
    const oauthOutput = await diagnostics(oauthFailure.clone());
    await expectError(oauthFailure, 503);
    expect(oauthOutput).not.toContain(GOOGLE_ERROR_BODY);
    expect(oauthOutput).not.toContain(OAUTH_URL);
    expect(publisherCalls(oauthFailureCalls.calls)).toHaveLength(0);

    const badKey = "fake-key-secret-marker";
    fakeGoogle(() => Response.json(purchase()));
    const credentialFailure = await postPurchase({ purchaseToken: TOKEN }, await testEnv({
      PLAY_SERVICE_ACCOUNT: JSON.stringify({ client_email: "invalid@example.test", private_key: badKey }),
    }));
    const credentialOutput = await diagnostics(credentialFailure);
    expect(credentialFailure.status).toBe(503);
    expect(credentialOutput).not.toContain(badKey);
    expect(credentialOutput).not.toContain(TOKEN);
  });

  it("signs valid scoped Google assertions", async () => {
    const fixture = await serviceAccount();
    let signatureVerified = false;
    const { calls } = fakeGoogle(
      () => Response.json(purchase({ acknowledgement: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" })),
      async (call) => {
        const form = new URLSearchParams(String(call.init?.body));
        const assertion = form.get("assertion")!;
        const [headerPart, claimsPart, signaturePart] = assertion.split(".");
        const signingInput = `${headerPart}.${claimsPart}`;
        const header = JSON.parse(new TextDecoder().decode(decodeBase64url(headerPart!)));
        const claims = JSON.parse(new TextDecoder().decode(decodeBase64url(claimsPart!)));
        signatureVerified = await crypto.subtle.verify(
          "RSASSA-PKCS1-v1_5",
          fixture.publicKey,
          decodeBase64url(signaturePart!),
          new TextEncoder().encode(signingInput),
        );
        expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
        expect(header).toEqual({ alg: "RS256", typ: "JWT" });
        expect(claims).toMatchObject({
          iss: "purchase-test@example.iam.gserviceaccount.com",
          scope: PUBLISHER_SCOPE,
          aud: OAUTH_URL,
        });
        expect(claims.exp).toBeGreaterThan(Math.floor(Date.now() / 1000));
        expect(claims.exp).toBeLessThanOrEqual(Math.floor(Date.now() / 1000) + 3600);
        return signatureVerified ? Response.json({ access_token: "test-access-token" }) : new Response("invalid assertion", { status: 400 });
      },
    );
    const response = await postPurchase({ purchaseToken: TOKEN }, await testEnv());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ad_free: true });
    expect(signatureVerified).toBe(true);
    expect(publisherCalls(calls).some((call) => call.url === PURCHASE_URL)).toBe(true);
  });
});
