#!/usr/bin/env bash
# Deploys the Worker to the Cloudflare account of CLOUDFLARE_API_TOKEN, creating what is missing.
# Safe to run on every push: each step is idempotent. Run from server/ with dependencies installed.
# Secrets come from the environment (see server/README.md); unset ones are left as they are.
set -euo pipefail

wrangler() { npx --no-install wrangler "$@"; }

# D1: create once, then point wrangler.toml at it (the committed file holds a placeholder id).
id=$(wrangler d1 list --json | node -e 'const l=JSON.parse(require("fs").readFileSync(0,"utf8"));const d=l.find(x=>x.name==="zero-gx");if(d)process.stdout.write(d.uuid)')
if [ -z "$id" ]; then
  wrangler d1 create zero-gx >/dev/null
  id=$(wrangler d1 list --json | node -e 'const l=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(l.find(x=>x.name==="zero-gx").uuid)')
fi
sed -i.bak "s/^database_id = .*/database_id = \"$id\"/" wrangler.toml && rm wrangler.toml.bak

# R2: create once.
if ! wrangler r2 bucket list | grep -q '^name:\s*zero-gx-demos$'; then
  wrangler r2 bucket create zero-gx-demos
fi

wrangler d1 migrations apply zero-gx --remote
wrangler deploy

# Secrets: upload every one that is set, in one new version. The file never leaves the runner's temp dir.
file=$(mktemp)
trap 'rm -f "$file"' EXIT
chmod 600 "$file"
node -e '
const names = ["SESSION_KEY", "ADMIN_TOKEN", "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "PLAY_SERVICE_ACCOUNT",
  "GITHUB_APP_ID", "GITHUB_APP_KEY", "GITHUB_INSTALLATION_ID", "GITHUB_WEBHOOK_SECRET"];
const set = Object.fromEntries(names.filter((n) => process.env[n]).map((n) => [n, process.env[n]]));
require("fs").writeFileSync(process.argv[1], JSON.stringify(set));
console.log("Secrets to upload: " + (Object.keys(set).join(", ") || "none"));
' "$file"
if [ "$(cat "$file")" != "{}" ]; then
  wrangler secret bulk "$file"
fi
