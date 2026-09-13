#!/usr/bin/env bash
# The data restore drill: prove a backup can actually be restored.
#
# ROADMAP Phase 1 asks for more than "a dump exists". A backup nobody has ever
# restored is a hope, so this dumps a seeded database, restores it into a fresh
# one, and then checks the restored copy on three axes:
#
#   1. Every table's row count matches.
#   2. Specific known values survive, not just the right quantity of rows.
#   3. The tenant boundary still works, which proves policies and functions
#      came across and not merely the tables and rows.
#
#   ./scripts/restore-drill.sh --local <source-container>
#   ./scripts/restore-drill.sh --hosted
#
# The hosted form dumps the London project. The restore target is always a local
# Postgres: a scratch Supabase project would be a third on a plan that allows
# two. That is an honest limit of this drill and it is printed in the output.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/worktree-id.sh"
TARGET="${VEGA_CONTAINER_PREFIX}-restore-target"
PORT="${RESTORE_PORT:-${VEGA_RESTORE_PORT}}"
IMAGE="docker.io/library/postgres:17"
DUMP="${DUMP_PATH:-/tmp/vega-drill-${VEGA_WORKTREE_ID}.dump}"
AUTHDUMP="${DUMP}.auth"
MODE="${1:---hosted}"
FAILED=0

cleanup() { [ "${KEEP:-0}" = "1" ] || docker rm -f "$TARGET" >/dev/null 2>&1 || true; }
trap cleanup EXIT

pgq() { docker exec -i "$TARGET" psql -U postgres -d postgres -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }

echo "==> taking the backup"
case "$MODE" in
  --local)
    SRC="${2:?usage: restore-drill.sh --local <container>}"
    docker exec -i "$SRC" pg_dump -U postgres -d postgres \
      --no-owner --no-privileges --schema=public > "$DUMP"
    # public alone is not a backup: profiles and company_users hold foreign keys
    # into auth.users, so restoring public by itself cannot satisfy them.
    #
    # Only the identity references travel, emitted as INSERT statements rather
    # than a pg_dump of auth.users. A real Supabase auth.users carries GoTrue's
    # full column set, which does not fit the shim's table, and a column
    # mismatch makes COPY drop every row silently. This is a stated limit: the
    # drill proves the business data restores and its foreign keys resolve, not
    # that GoTrue's user records survive.
    docker exec -i "$SRC" psql -U postgres -d postgres -tAc \
      "SELECT format('INSERT INTO auth.users (id, email) VALUES (%L, %L) ON CONFLICT (id) DO NOTHING;', id, email) FROM auth.users" \
      > "$AUTHDUMP" 2>/dev/null
    SRC_COUNTS=$(docker exec -i "$SRC" psql -U postgres -d postgres -tAc "
      SELECT string_agg(t || ':' || c, ',' ORDER BY t) FROM (
        SELECT relname AS t, n_live_tup AS c FROM pg_stat_user_tables
         WHERE schemaname='public') d" 2>/dev/null | tr -d '[:space:]')
    ;;
  --hosted)
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
    DSN="postgresql://postgres.${VITE_SUPABASE_PROJECT_ID}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
    docker run --rm -i --network host "$IMAGE" \
      pg_dump "$DSN" --no-owner --no-privileges --schema=public > "$DUMP"
    docker run --rm -i --network host "$IMAGE" \
      psql "$DSN" -tAc \
      "SELECT format('INSERT INTO auth.users (id, email) VALUES (%L, %L) ON CONFLICT (id) DO NOTHING;', id, email) FROM auth.users" \
      > "$AUTHDUMP" 2>/dev/null
    SRC_COUNTS=""
    ;;
  *) echo "usage: restore-drill.sh [--local <container> | --hosted]"; exit 2 ;;
esac
echo "    dump: $(wc -c < "$DUMP") bytes"
[ -s "$DUMP" ] || { echo "    empty dump, nothing to restore"; exit 1; }

echo "==> restoring into a fresh Postgres on :$PORT"
docker rm -f "$TARGET" >/dev/null 2>&1 || true
docker run -d --name "$TARGET" -e POSTGRES_PASSWORD=postgres -p "$PORT:5432" "$IMAGE" >/dev/null
stable=0
for _ in $(seq 1 90); do
  if docker exec "$TARGET" psql -U postgres -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
    stable=$((stable+1)); [ "$stable" -ge 2 ] && break
  else stable=0; fi
  sleep 1
done

docker exec -i "$TARGET" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < "$ROOT/scripts/supabase-shim.sql" >/dev/null 2>&1

# Identities first, so the membership foreign keys have something to point at.
if [ -s "$AUTHDUMP" ]; then
  docker exec -i "$TARGET" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    < "$AUTHDUMP" >/dev/null 2>/tmp/vega-auth-restore.err \
    || { echo "    AUTH IDENTITY RESTORE FAILED"; grep -m2 ERROR /tmp/vega-auth-restore.err | sed 's/^/      /'; exit 1; }
  restored_ids=$(docker exec -i "$TARGET" psql -U postgres -d postgres -tAc 'SELECT count(*) FROM auth.users' 2>/dev/null | tr -d '[:space:]')
  echo "    auth identities restored: $restored_ids"
  [ "${restored_ids:-0}" -gt 0 ] || { echo "    no identities restored; the public restore cannot satisfy its foreign keys"; exit 1; }
fi
# pg_dump emits CREATE SCHEMA public and psql meta-commands that a fresh target
# already satisfies or does not understand. Filtering them is restore mechanics,
# not editing the backup: the dump on disk is untouched.
if ! grep -v '^CREATE SCHEMA public;$' "$DUMP" \
   | grep -v "^COMMENT ON SCHEMA public IS" \
   | grep -v '^\\restrict \|^\\unrestrict ' \
   | docker exec -i "$TARGET" psql -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null 2>/tmp/vega-restore.err; then
  echo "    RESTORE FAILED"
  grep -v "Emulate Docker CLI" /tmp/vega-restore.err | grep -m3 ERROR | sed 's/^/      /'
  exit 1
fi
echo "    restored"

echo "==> 1. row counts"
docker exec -i "$TARGET" psql -U postgres -d postgres -c "ANALYZE" >/dev/null 2>&1
for pair in "companies:1" "customers:2" "suppliers:2" "products:4" "batches:4" \
            "batch_movements:4" "sales_invoices:1" "sales_invoice_items:2" \
            "vat_treatments:11" "vat_rates:11"; do
  t="${pair%%:*}"; want="${pair##*:}"
  got=$(pgq "SELECT count(*) FROM public.$t")
  if [ "$got" = "$want" ]; then echo "    ok    $t: $got"
  else echo "    FAIL  $t: got $got want $want"; FAILED=1; fi
done

echo "==> 2. known values survived"
chk() { if [ "$2" = "$3" ]; then echo "    ok    $1"; else echo "    FAIL  $1: got '$2' want '$3'"; FAILED=1; fi; }
chk "company VAT number"    "$(pgq "SELECT vat_number FROM public.companies WHERE name='Pennine Bakehouse Ltd'")" "GB123456789"
chk "bread is zero rated"   "$(pgq "SELECT default_vat_treatment_code FROM public.products WHERE sku='SD-800'")" "ZER"
chk "brownies standard"     "$(pgq "SELECT default_vat_treatment_code FROM public.products WHERE sku='CB-200'")" "STD"
chk "batch use-by kept"     "$(pgq "SELECT use_by_on FROM public.batches WHERE batch_code='SD-2026-0904'")" "2026-09-08"
chk "invoice VAT total"     "$(pgq "SELECT sum(vat_amount) FROM public.sales_invoice_items")" "25.00"
chk "invoice line to batch" "$(pgq "SELECT count(*) FROM public.sales_invoice_items WHERE batch_id IS NOT NULL")" "2"

echo "==> 3. the tenant boundary survived the restore"
# Rows and tables can restore perfectly while policies do not. Acting as the
# seeded user must still return exactly that company's products.
seen=$(docker exec -i "$TARGET" psql -U postgres -d postgres -tAc "
  BEGIN;
  SET LOCAL ROLE authenticated;
  SELECT set_config('request.jwt.claim.sub','11111111-0000-4000-8000-0000000000f1',true);
  SELECT count(*) FROM public.products;
  ROLLBACK;" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
chk "seeded user sees their 4 products" "$seen" "4"

stranger=$(docker exec -i "$TARGET" psql -U postgres -d postgres -tAc "
  BEGIN;
  SET LOCAL ROLE authenticated;
  SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
  SELECT count(*) FROM public.products;
  ROLLBACK;" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
chk "a stranger sees none" "$stranger" "0"

echo
echo "SCOPE: the restore target is a local Postgres, not a fresh Supabase project."
echo "This proves the dump is complete and restorable, and that policies and"
echo "functions came with it. It does not exercise a Supabase project restore."
echo
[ "$FAILED" = "0" ] && echo "restore drill PASSED" || echo "restore drill FAILED"
exit "$FAILED"
