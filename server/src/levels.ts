import type { Env } from "./env";
import { HttpError } from "./http";

const LEVEL_ID = /^lvl_[a-z0-9]{10}$/;

/** The condition on `levels l` that makes a level visible: not hidden by its flag or by hidden.txt. */
export const VISIBLE = "l.hidden = 0 AND l.id NOT IN (SELECT level FROM hidden_levels)";

interface LevelRow {
  id: string;
  latest: number;
}

/** A level that exists and is not hidden, else 404. */
export async function visibleLevel(env: Env, id: string | undefined): Promise<LevelRow> {
  const level = LEVEL_ID.test(id ?? "") ? await env.DB.prepare(`SELECT l.id, l.latest FROM levels l WHERE l.id = ? AND ${VISIBLE}`).bind(id).first<LevelRow>() : null;
  if (!level) throw new HttpError(404, "Not found.");
  return level;
}
