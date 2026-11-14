import type { Env } from "./env";
import { serviceAccountAssertion } from "./google";
import { HttpError, limitAuth, readJson } from "./http";

const PACKAGE = "dev.braitg.zerogx";
const PRODUCT = "remove_ads";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const PUBLISHER_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3";
const PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const MAX_BODY_BYTES = 4096;
const MAX_TOKEN_LENGTH = 2048;
const PURCHASE_INVALID = "The purchase token is invalid.";
const PURCHASE_INACTIVE = "The purchase is no longer active.";
const UNAVAILABLE = "Purchase verification is temporarily unavailable.";

type PurchaseRejection = { status: 404 | 409; code: "purchase_invalid" | "purchase_inactive"; message: string };
type PurchaseState = { state: "PENDING" } | { state: "PURCHASED"; acknowledged: boolean };

class PurchaseFailure extends Error {
  constructor(readonly rejection: PurchaseRejection) {
    super(rejection.message);
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function rejectPurchase(status: 404 | 409, code: PurchaseRejection["code"], message: string): never {
  throw new PurchaseFailure({ status, code, message });
}

async function responseJson(response: Response): Promise<Record<string, unknown>> {
  let data: unknown;
  try {
    data = await response.json();
  } catch {
    throw new GoogleFailure("Malformed Google response.");
  }
  if (!isObject(data)) throw new GoogleFailure("Malformed Google response.");
  return data;
}

/** A failed Google call, described only by HTTP status and Google's error enums (status, reason, OAuth error code) so the log never carries free text that could echo a token or key. */
class GoogleFailure extends Error {}

async function googleFailure(step: string, response: Response): Promise<GoogleFailure> {
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  const error = isObject(body) ? body.error : undefined;
  const enumOf = (value: unknown) => (typeof value === "string" && /^[A-Za-z_]{1,64}$/.test(value) ? value : "-");
  const reasons = isObject(error) && Array.isArray(error.errors) && isObject(error.errors[0]) ? error.errors[0].reason : undefined;
  const detail = isObject(error) ? `${enumOf(error.status)} ${enumOf(reasons)}` : enumOf(error); // OAuth answers {"error": "invalid_grant"}
  return new GoogleFailure(`${step} ${response.status} ${detail}`);
}

async function googleAccessToken(env: Env): Promise<string> {
  const assertion = await serviceAccountAssertion(env.PLAY_SERVICE_ACCOUNT, PUBLISHER_SCOPE);
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw await googleFailure("authorization", response);
  const data = await responseJson(response);
  if (typeof data.access_token !== "string" || data.access_token.length === 0) throw new GoogleFailure("Malformed Google authorization response.");
  return data.access_token;
}

async function googlePurchase(token: string, accessToken: string): Promise<PurchaseState> {
  const url = `${PUBLISHER_ROOT}/applications/${PACKAGE}/purchases/productsv2/tokens/${encodeURIComponent(token)}`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw await googleFailure("purchase lookup", response);

  const data = await responseJson(response);
  const stateContext = data.purchaseStateContext;
  if (!isObject(stateContext) || typeof stateContext.purchaseState !== "string") throw new GoogleFailure("Malformed Google purchase state.");
  const state = stateContext.purchaseState;
  if (state !== "PENDING" && state !== "CANCELLED" && state !== "PURCHASED") throw new GoogleFailure("Unknown Google purchase state.");

  const lineItems = data.productLineItem;
  if (!Array.isArray(lineItems) || lineItems.length === 0) throw new GoogleFailure("Malformed Google product line item.");
  if (lineItems.length !== 1) rejectPurchase(404, "purchase_invalid", PURCHASE_INVALID);
  const item: unknown = lineItems[0];
  if (!isObject(item) || typeof item.productId !== "string") throw new GoogleFailure("Malformed Google product line item.");
  if (item.productId !== PRODUCT) rejectPurchase(404, "purchase_invalid", PURCHASE_INVALID);
  if (state === "PENDING") return { state };
  if (state === "CANCELLED") rejectPurchase(409, "purchase_inactive", PURCHASE_INACTIVE);

  const offer = item.productOfferDetails;
  if (!isObject(offer)) throw new GoogleFailure("Malformed Google product details.");
  if ("rentOfferDetails" in offer || "preorderOfferDetails" in offer) rejectPurchase(404, "purchase_invalid", PURCHASE_INVALID);
  if (typeof offer.quantity !== "number" || !Number.isInteger(offer.quantity)) throw new GoogleFailure("Malformed Google quantity.");
  if (offer.quantity !== 1) rejectPurchase(404, "purchase_invalid", PURCHASE_INVALID);
  if (typeof offer.refundableQuantity !== "number" || !Number.isInteger(offer.refundableQuantity)) throw new GoogleFailure("Malformed Google refundable quantity.");
  if (offer.refundableQuantity === 0) rejectPurchase(409, "purchase_inactive", PURCHASE_INACTIVE);
  if (offer.refundableQuantity < 0 || offer.refundableQuantity !== offer.quantity) throw new GoogleFailure("Malformed Google refundable quantity.");
  if (offer.consumptionState === "CONSUMPTION_STATE_CONSUMED") rejectPurchase(404, "purchase_invalid", PURCHASE_INVALID);
  if (offer.consumptionState !== "CONSUMPTION_STATE_YET_TO_BE_CONSUMED") throw new GoogleFailure("Malformed Google consumption state.");

  if (data.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") return { state, acknowledged: true };
  if (data.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_PENDING") throw new GoogleFailure("Malformed Google acknowledgement state.");
  return { state, acknowledged: false };
}

async function acknowledge(token: string, accessToken: string): Promise<boolean> {
  const url = `${PUBLISHER_ROOT}/applications/${PACKAGE}/purchases/products/${PRODUCT}/tokens/${encodeURIComponent(token)}:acknowledge`;
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ developerPayload: "" }),
    });
  } catch {
    return false;
  }
  if (response.ok) return true;
  if (response.status === 408 || response.status === 409 || response.status === 429 || response.status >= 500) return false;
  throw new GoogleFailure("Google acknowledgement failed.");
}

function success(): Response {
  return Response.json({ ad_free: true });
}

function rejectionResponse(rejection: PurchaseRejection): Response {
  return Response.json({ error: rejection.message, code: rejection.code }, { status: rejection.status });
}

export async function postAdFreePurchase(request: Request, env: Env): Promise<Response> {
  await limitAuth(request, env);
  const { purchaseToken } = await readJson(request, MAX_BODY_BYTES);
  if (typeof purchaseToken !== "string" || purchaseToken.length === 0 || purchaseToken.length > MAX_TOKEN_LENGTH) {
    throw new HttpError(400, "A purchaseToken string of at most 2048 characters is required.");
  }

  try {
    const accessToken = await googleAccessToken(env);
    const purchase = await googlePurchase(purchaseToken, accessToken);
    if (purchase.state === "PENDING") return Response.json({ pending: true }, { status: 202 });
    if (purchase.acknowledged) return success();
    if (await acknowledge(purchaseToken, accessToken)) return success();

    const refreshed = await googlePurchase(purchaseToken, accessToken);
    if (refreshed.state === "PURCHASED" && refreshed.acknowledged) return success();
    throw new GoogleFailure("Google acknowledgement could not be confirmed.");
  } catch (error) {
    if (error instanceof PurchaseFailure) return rejectionResponse(error.rejection);
    console.error("Purchase verification failed:", error instanceof GoogleFailure ? error.message : "no answer from Google (network)");
    return Response.json({ error: UNAVAILABLE }, { status: 503 });
  }
}
