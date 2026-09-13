#!/usr/bin/env bash
# Deploy the API to Fly, with its secrets read from pass rather than typed.
#
#   flyctl auth login            # once, interactive
#   ./scripts/deploy-api.sh      # every time after
#
# Secrets never appear in fly.toml, in git, or in a shell you scrolled past.
# `flyctl secrets set` takes them on stdin for that reason.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="$ROOT/apps/api"
APP="${FLY_APP:-vega-api}"
REGION="${FLY_REGION:-lhr}"
ORG="${FLY_ORG:-personal}"

command -v flyctl >/dev/null || { echo "flyctl not on PATH; try export PATH=\"\$HOME/.fly/bin:\$PATH\""; exit 1; }
flyctl auth whoami >/dev/null 2>&1 || { echo "not logged in. Run: flyctl auth login"; exit 1; }

# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
REF="${VITE_SUPABASE_PROJECT_ID:?VITE_SUPABASE_PROJECT_ID missing from .env}"
API_PW="$(pass show supabase/vega-api-role)"

# Refuse to ship code ahead of the schema it assumes.
#
# This is the moment the mismatch becomes real. #99 was a service whose queries
# read line_subtotal deployed against a database that still had taxable_value,
# and the symptom was a 500 on the only endpoint anybody had built. The check
# already existed and ran nowhere; here the credentials are already loaded, so
# there is no reason for it not to.
#
# ALLOW_SCHEMA_DRIFT=1 to deploy anyway, which is a real case (rolling the
# service back to meet a schema you are not rolling back), and has to be typed.
if [ "${ALLOW_SCHEMA_DRIFT:-0}" != "1" ]; then
  echo "==> checking the hosted schema matches the migrations"
  if ! "$ROOT/scripts/check-schema-drift.sh"; then
    echo >&2
    echo "Refusing to deploy: London does not match supabase/migrations." >&2
    echo "Apply them first:  ./scripts/apply-migrations.sh --apply" >&2
    echo "Or set ALLOW_SCHEMA_DRIFT=1 if this deploy is deliberate." >&2
    exit 1
  fi
fi

if ! flyctl apps list 2>/dev/null | grep -q "^$APP"; then
  echo "==> creating $APP in $ORG"
  flyctl apps create "$APP" --org "$ORG"
fi

echo "==> setting secrets (values are not printed)"
# --stage so nothing deploys on a half-set secret list; the deploy below picks
# them up together.
flyctl secrets set --app "$APP" --stage \
  VITE_SUPABASE_URL="https://${REF}.supabase.co" \
  VEGA_DATABASE_URL="postgresql://vega_api.${REF}:${API_PW}@aws-0-eu-west-2.pooler.supabase.com:6543/postgres" \
  VEGA_WORKER_DATABASE_URL="postgresql://vega_api.${REF}:${API_PW}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres" \
  >/dev/null
echo "    VITE_SUPABASE_URL, VEGA_DATABASE_URL (6543), VEGA_WORKER_DATABASE_URL (5432)"

# WORKER_ONLY deploys just the job runner and leaves the HTTP API at zero
# machines. That is the right shape while nothing calls the API: the web app
# cannot reach it until its origin is in the CSP, so paying for it to sit idle
# buys nothing. The FX job is different: a rate not captured on the day is gone,
# so its history accrues from the moment it runs.
if [ "${WORKER_ONLY:-0}" = "1" ]; then
  echo "==> deploying the worker only"
  flyctl deploy "$API" --app "$APP" --regions "$REGION" --ha=false --process-groups worker
  echo "==> holding the API at zero machines"
  flyctl scale count api=0 --app "$APP" --yes >/dev/null 2>&1 || true
  flyctl status --app "$APP" 2>/dev/null | grep -v "Metrics token" | head -12
  echo
  echo "Worker running. The API is deployed but scaled to zero; bring it up with:"
  echo "    flyctl scale count api=1 --app $APP"
  exit 0
fi

echo "==> deploying to $REGION"
flyctl deploy "$API" --app "$APP" --regions "$REGION" --ha=false

echo "==> checking it answers"
HOST="$(flyctl status --app "$APP" --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('Hostname',''))" || true)"
if [ -n "$HOST" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "https://$HOST/health" || echo 000)
  echo "    https://$HOST/health -> HTTP $code"
  [ "$code" = "200" ] || { echo "    deployed but not healthy; check flyctl logs --app $APP"; exit 1; }
  echo
  echo "Add this origin to the web app's connect-src before the browser can call it:"
  echo "    apps/web/index.html and apps/web/public/_headers -> https://$HOST"
fi
