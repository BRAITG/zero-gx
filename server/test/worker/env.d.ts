import type { D1Migration } from "@cloudflare/vitest-plugin";
import type { Env } from "../../src/env";

declare global {
  namespace Cloudflare {
    interface GlobalProps {
      mainModule: typeof import("../../src/worker");
    }
    interface Env extends ServerEnv {
      TEST_MIGRATIONS: D1Migration[];
      // Base64 fixture files, see vitest.config.ts.
      LEVEL_01: string;
      DEMO_LEVEL_01: string;
      DEMO_TELEPORT: string;
      LEVEL_05: string;
      DEMO_LEVEL_05: string;
    }
  }
}
type ServerEnv = Env;
