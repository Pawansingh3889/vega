#!/usr/bin/env bash
# Does the hosted database still match what the migrations describe?
#
# ROADMAP Phase 2 asked for "Alembic autogenerate produces an empty diff",
# written on the assumption that SQLAlchemy models would describe the same
# tables as the migrations, making two writers for one schema. That has not
# happened: the service uses raw queries and defines no models, so autogenerate
# has nothing to compare and would pass vacuously, which is the failure mode
# this project has hit four times already.
#
# The risk that IS real: somebody changes the hosted database through the
# Supabase dashboard, and the migrations quietly stop describing production.
# Nothing catches that, because every local check rebuilds from the migrations
# and therefore agrees with itself.
#
# So this compares the two. A fresh local database built from migrations, and
# the hosted one, dumped the same way and diffed.
#
#   ./scripts/check-schema-drift.sh
#
# Reinstate the Alembic check the day models appear; both would then be worth
# having, since they catch different drift.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/worktree-id.sh"
LOCAL_NAME="${VEGA_CONTAINER_PREFIX}-drift-local"
PORT="${DRIFT_PORT:-${VEGA_DRIFT_PORT}}"
IMAGE="docker.io/library/postgres:17"

cleanup() { [ "${KEEP:-0}" = "1" ] || docker rm -f "$LOCAL_NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> building a fresh database from the migrations"
docker rm -f "$LOCAL_NAME" >/dev/null 2>&1 || true
docker run -d --name "$LOCAL_NAME" -e POSTGRES_PASSWORD=postgres -p "$PORT:5432" "$IMAGE" >/dev/null
stable=0
for _ in $(seq 1 90); do
  if docker exec "$LOCAL_NAME" psql -U postgres -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
    stable=$((stable+1)); [ "$stable" -ge 2 ] && break
  else stable=0; fi
  sleep 1
done
docker exec -i "$LOCAL_NAME" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < "$ROOT/scripts/supabase-shim.sql" >/dev/null 2>&1
for f in $(find "$ROOT/supabase/migrations" -maxdepth 1 -name '*.sql' | sort); do
  docker exec -i "$LOCAL_NAME" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$f" >/dev/null 2>&1 \
    || { echo "    migration $(basename "$f") failed; fix that before comparing"; exit 1; }
done

# Compare the shape, not the dump text. Two pg_dumps differ on ordering,
# comments and whitespace in ways that say nothing about drift, so this asks
# the catalogue the same questions of both databases.
SHAPE_QUERY=$(cat <<'SQL'
SELECT 'table:'  || table_name || '.' || column_name || ':' || data_type
       || ':' || is_nullable
  FROM information_schema.columns WHERE table_schema = 'public'
UNION ALL
SELECT 'policy:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text
  FROM pg_policies WHERE schemaname = 'public'
UNION ALL
SELECT 'index:'  || indexname || ':' || indexdef
  FROM pg_indexes WHERE schemaname = 'public'
UNION ALL
SELECT 'function:' || p.proname || ':' || pg_get_function_identity_arguments(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   -- Extension-owned functions are excluded. The local shim installs pgcrypto
   -- into public; Supabase installs it into `extensions`. That is where the two
   -- environments differ by design, and reporting it as drift every run is how
   -- a drift check gets ignored.
   AND NOT EXISTS (
     SELECT 1 FROM pg_depend d
      WHERE d.objid = p.oid AND d.deptype = 'e'
   )
UNION ALL
SELECT 'rls:' || c.relname || ':' || c.relrowsecurity::text
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY 1
SQL
)

echo "==> reading the local shape"
docker exec -i "$LOCAL_NAME" psql -U postgres -d postgres -tAc "$SHAPE_QUERY" 2>/dev/null | sort > /tmp/vega-shape-local.txt

echo "==> reading the hosted shape"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
DSN="postgresql://postgres.${VITE_SUPABASE_PROJECT_ID}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
docker run --rm -i --network host "$IMAGE" psql "$DSN" -tAc "$SHAPE_QUERY" 2>/dev/null | sort > /tmp/vega-shape-hosted.txt

echo "==> comparing"
echo "    local:  $(wc -l < /tmp/vega-shape-local.txt) objects"
echo "    hosted: $(wc -l < /tmp/vega-shape-hosted.txt) objects"

if diff -q /tmp/vega-shape-local.txt /tmp/vega-shape-hosted.txt >/dev/null; then
  echo
  echo "no drift: the hosted database matches the migrations"
  exit 0
fi

echo
echo "DRIFT DETECTED"
echo
echo "  in the migrations but NOT hosted (a migration that never reached London):"
comm -23 /tmp/vega-shape-local.txt /tmp/vega-shape-hosted.txt | head -30 | sed 's/^/    /'
echo
echo "  hosted but NOT in the migrations (usually a dashboard edit):"
comm -13 /tmp/vega-shape-local.txt /tmp/vega-shape-hosted.txt | head -30 | sed 's/^/    /'
echo
echo "Full lists: /tmp/vega-shape-local.txt and /tmp/vega-shape-hosted.txt"
exit 1
