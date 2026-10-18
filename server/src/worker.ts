import type { Env } from "./env";
import { type Handler, HttpError } from "./http";
import { getBoard, getDemo, postOfficial, postScore } from "./scores";
import { getNonce, postSession } from "./session";

/** Method + path pattern -> handler. `:name` segments are captured into the handler's params. */
const routes: [method: string, pattern: string, handler: Handler][] = [
  ["GET", "/nonce", getNonce],
  ["POST", "/session", postSession],
  ["POST", "/scores", postScore],
  ["GET", "/boards/:sha256", getBoard],
  ["GET", "/demos/:sha256/:player/:file", getDemo],
  ["POST", "/admin/official", postOfficial],
];

function match(pattern: string, path: string): Record<string, string> | null {
  const want = pattern.split("/");
  const have = path.split("/");
  if (want.length !== have.length) return null;
  const params: Record<string, string> = {};
  for (const [i, part] of want.entries()) {
    if (part.startsWith(":")) {
      try {
        params[part.slice(1)] = decodeURIComponent(have[i]!);
      } catch {
        throw new HttpError(404, "Not found.");
      }
    } else if (part !== have[i]) return null;
  }
  return params;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const path = new URL(request.url).pathname;
    try {
      for (const [method, pattern, handler] of routes) {
        const params = request.method === method ? match(pattern, path) : null;
        if (params) return await handler(request, env, params);
      }
      throw new HttpError(404, "Not found.");
    } catch (error) {
      if (error instanceof HttpError) return Response.json({ error: error.message }, { status: error.status });
      console.error(error);
      return Response.json({ error: "Internal error." }, { status: 500 });
    }
  },
} satisfies ExportedHandler<Env>;
