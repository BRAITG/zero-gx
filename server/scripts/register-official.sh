#!/usr/bin/env bash
# Trusted release checkout only; credentials stay in Wrangler's environment, never arguments or logs.
set +x
set -euo pipefail

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "::notice::No CLOUDFLARE_API_TOKEN; skipping official level registration."
  exit 0
fi
[ "$#" -eq 1 ] || { echo "::error::Usage: scripts/register-official.sh RELEASE" >&2; exit 1; }
[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || unset CLOUDFLARE_ACCOUNT_ID
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Validate the whole bundle before contacting Cloudflare. Hash the canonical files without reserializing.
node --input-type=module - "$1" "$work/official.sql" <<'NODE'
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
const [release, output] = process.argv.slice(2);
function fail(message) { console.error(`::error::${message}`); process.exit(1); }
if (!/^[A-Za-z0-9._-]{1,64}$/.test(release) || /[\r\n]/.test(release)) fail("Invalid release: use 1–64 letters, digits, dots, dashes or underscores.");
const files = readdirSync("../levels", { withFileTypes: true }).filter((entry) => entry.name.endsWith(".json"));
if (files.length < 1 || files.length > 200) fail("The bundle must contain 1–200 official level files.");
if (files.some((entry) => !entry.isFile() || !/^level_[0-9]{2}\.json$/.test(entry.name))) fail("Official level files must be regular files named level_NN.json.");
// All SQL values are either strictly allowlisted above or generated lowercase hex: none can contain a quote.
const values = files.sort((a, b) => a.name.localeCompare(b.name)).map((entry) => {
  const sha256 = createHash("sha256").update(readFileSync(`../levels/${entry.name}`)).digest("hex");
  return `('${sha256}', '${entry.name.slice(0, -5)}', '${release}')`;
});
writeFileSync(output, `INSERT INTO official_levels (sha256, name, release) VALUES ${values.join(", ")} ON CONFLICT (sha256) DO UPDATE SET name = excluded.name, release = excluded.release;\n`);
NODE

# Resolve by the deployment's database name, never the committed placeholder id.
if ! npx --no-install wrangler d1 list --json > "$work/databases.json" 2> "$work/error"; then
  echo "::error::Official registration failed: unable to list D1 databases with the deployment credential." >&2
  exit 1
fi
node --input-type=module - "$work/databases.json" "$work/wrangler.toml" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
const [input, output] = process.argv.slice(2);
let databases;
try { databases = JSON.parse(readFileSync(input, "utf8")); } catch {
  console.error("::error::Official registration failed: invalid D1 database listing.");
  process.exit(1);
}
const database = Array.isArray(databases) && databases.find((entry) => entry.name === "zero-gx");
if (!database || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(database.uuid) || database.uuid === "00000000-0000-0000-0000-000000000000") {
  console.error("::error::Official registration failed: deployed D1 database zero-gx was not found.");
  process.exit(1);
}
writeFileSync(output, `name = "zero-gx"\n[[d1_databases]]\nbinding = "DB"\ndatabase_name = "zero-gx"\ndatabase_id = "${database.uuid}"\n`);
NODE
if ! npx --no-install wrangler d1 execute zero-gx --remote --config "$work/wrangler.toml" --file "$work/official.sql" > "$work/result" 2> "$work/error"; then
  # Do not relay raw tool responses: authentication failures could include credential-bearing diagnostics.
  echo "::error::Official registration failed: remote D1 upsert did not complete." >&2
  exit 1
fi
echo "Official levels registered for $1."
