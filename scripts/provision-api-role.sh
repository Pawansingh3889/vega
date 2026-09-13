#!/usr/bin/env bash
# Give the vega_api role a password and let it log in.
#
# Migration 0014 creates the role NOLOGIN with its grants, so what the role may
# reach stays reviewable in git. The password is not a schema decision and must
# never be committed, so it is set here from pass instead.
#
#   ./scripts/provision-api-role.sh
#
# Re-runnable: rotating the password is running this again after replacing the
# pass entry.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! pass show supabase/vega-api-role >/dev/null 2>&1; then
  echo "generating a password for vega_api and storing it in pass"
  # head -c leaves no trailing newline, so build the value first rather than
  # piping into a read that then returns non-zero under set -e.
  generated="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  [ ${#generated} -eq 32 ] || { echo "password generation failed"; exit 1; }
  printf '%s\n' "$generated" | pass insert -e -f supabase/vega-api-role >/dev/null
fi

APIPW="$(pass show supabase/vega-api-role)"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
REF="$VITE_SUPABASE_PROJECT_ID"
ADMIN="postgresql://postgres.${REF}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"

docker run --rm -i --network host docker.io/library/postgres:17 \
  psql "$ADMIN" -v ON_ERROR_STOP=1 -q \
  -c "ALTER ROLE vega_api LOGIN PASSWORD '${APIPW}'" >/dev/null
echo "vega_api can log in"

# Prove it, and prove it still owns nothing.
PROBE="postgresql://vega_api.${REF}:${APIPW}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
docker run --rm -i --network host docker.io/library/postgres:17 psql "$PROBE" -tAc \
  "SELECT 'connected as ' || current_user
        || ', owns ' || (SELECT count(*) FROM pg_class c JOIN pg_roles r ON r.oid=c.relowner
                          WHERE r.rolname='vega_api') || ' objects'
        || ', can become authenticated: '
        || pg_has_role('vega_api','authenticated','MEMBER')::text" 2>/dev/null
