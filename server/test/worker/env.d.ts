import type { D1Migration } from "@cloudflare/vitest-plugin";
import type { Env } from "../../src/env";

declare global {
  namespace Cloudflare {
    interface GlobalProps {
      mainModule: typeof import("../../src/worker");
    }
    interface Env extends ServerEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}
type ServerEnv = Env;
