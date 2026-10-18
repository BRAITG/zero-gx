import type { Env } from "./env";

/** Thrown by handlers; the router turns it into a JSON `{"error"}` response. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export type Handler = (request: Request, env: Env, params: Record<string, string>) => Promise<Response>;

/** Reads the raw body, refusing more than `maxBytes` actually received (Content-Length is only a shortcut). */
export async function readBytes(request: Request, maxBytes: number): Promise<Uint8Array> {
  const tooBig = new HttpError(413, `The request body is over ${maxBytes} bytes.`);
  if (Number(request.headers.get("Content-Length")) > maxBytes) throw tooBig;
  const chunks: Uint8Array[] = [];
  let size = 0;
  if (request.body) {
    for await (const chunk of request.body) {
      size += chunk.byteLength;
      if (size > maxBytes) throw tooBig;
      chunks.push(chunk);
    }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

/** Reads a JSON object body, refusing more than `maxBytes` of raw body. */
export async function readJson(request: Request, maxBytes = 4096): Promise<Record<string, unknown>> {
  const bytes = await readBytes(request, maxBytes);
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpError(400, "The request body is not valid JSON.");
  }
  if (body === null || typeof body !== "object" || Array.isArray(body)) throw new HttpError(400, "The request body must be a JSON object.");
  return body as Record<string, unknown>;
}
