#!/usr/bin/env bash
# Prove the migration set rebuilds a database from nothing, and lands where we
# think it lands.
#
# Phase 1's exit says a fresh database builds from migrations alone with no
# manual steps. This is that check, runnable locally and in CI:
#   baseline -> Vega's forward migrations -> assert the end state
#
#   ./scripts/verify-baseline.sh
#
# Env:  PGPORT (default 54330), KEEP=1 to leave the container up

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/worktree-id.sh"
# shellcheck disable=SC1091
. "$ROOT/scripts/pg-wait.sh"
MIGDIR="$ROOT/supabase/migrations"
PORT="${PGPORT:-${VEGA_VERIFY_PORT}}"
NAME="${VEGA_CONTAINER_PREFIX}-verify-baseline"
FAILED=0

psql_q() { docker exec -i "$NAME" psql -U postgres -d postgres -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }

cleanup() { [ "${KEEP:-0}" = "1" ] || docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> fresh Postgres on :$PORT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=postgres -p "$PORT:5432" docker.io/library/postgres:17 >/dev/null
wait_for_postgres "$NAME"

echo "==> shim, then every migration in order"
docker exec -i "$NAME" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < "$ROOT/scripts/supabase-shim.sql" >/dev/null 2>&1

for f in $(find "$MIGDIR" -maxdepth 1 -name '*.sql' | sort); do
  n="$(basename "$f")"
  if docker exec -i "$NAME" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$f" >/dev/null 2>/tmp/vega-verify.err; then
    echo "    ok    $n"
  else
    echo "    FAIL  $n"
    grep -v "Emulate Docker CLI" /tmp/vega-verify.err | grep -m2 "ERROR" | sed 's/^/          /'
    FAILED=1
  fi
done

echo "==> asserting the end state"
check() { # name, actual, expected
  if [ "$2" = "$3" ]; then echo "    ok    $1: $2"; else echo "    FAIL  $1: got $2, want $3"; FAILED=1; fi
}
# A fixed table count breaks on every migration and asserts nothing about
# intent, so assert the properties that must hold instead.
check "tables exist (at least the inherited 51)" \
  "$(psql_q "select (count(*) >= 51)::int from pg_tables where schemaname='public'")" "1"

# Guard. Every assertion below counts rows about auth_rate_limits, and a count
# of zero is indistinguishable from "the table was never created". Assert the
# subject exists before trusting anything that counts over it.
check "auth_rate_limits exists" \
  "$(psql_q "select count(*) from pg_tables where schemaname='public' and tablename='auth_rate_limits'")" "1"

echo "    -- N1: deny by default"
check "every table has RLS enabled" \
  "$(psql_q "select count(*) from pg_tables t join pg_class c on c.relname=t.tablename join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where t.schemaname='public' and not c.relrowsecurity")" "0"
check "no table is left without a policy" \
  "$(psql_q "select count(*) from pg_tables t where t.schemaname='public' and not exists (select 1 from pg_policies p where p.tablename=t.tablename)")" "0"
check "every SECURITY DEFINER pins search_path" \
  "$(psql_q "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))")" "0"

echo "    -- inherited defects: permissive policy, and mutable search_path"
check "auth_rate_limits public read dropped" \
  "$(psql_q "select count(*) from pg_policies where tablename='auth_rate_limits' and policyname='Anyone can check rate limits'")" "0"
check "auth_rate_limits reachable only by service_role" \
  "$(psql_q "select count(*) from pg_policies where tablename='auth_rate_limits' and roles::text <> '{service_role}'")" "0"
check "hashed_email index is unique" \
  "$(psql_q "select count(*) from pg_indexes where indexname='idx_auth_rate_limits_hashed_email' and indexdef like '%UNIQUE%'")" "1"

echo "    -- SPEC.md section 2: UK VAT"
check "vat_treatments seeded" \
  "$(psql_q "select (count(*) >= 11)::int from public.vat_treatments")" "1"
check "every treatment has a rate" \
  "$(psql_q "select count(*) from public.vat_treatments t where not exists (select 1 from public.vat_rates r where r.treatment_code=t.code)")" "0"
check "no India GST columns remain" \
  "$(psql_q "select count(*) from information_schema.columns where table_schema='public' and (column_name like 'cgst%' or column_name like 'sgst%' or column_name like 'igst%' or column_name='gst_percentage' or column_name='gst_rate')")" "0"
check "every line table carries a treatment" \
  "$(psql_q "select count(*) from (values ('sales_invoice_items'),('sales_order_items'),('purchase_order_items'),('credit_note_items'),('debit_note_items'),('supplier_credit_note_items'),('performa_invoice_items'),('grn_line_items'),('return_order_lines')) as t(n) where not exists (select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=t.n and c.column_name='vat_treatment_code')")" "0"

echo "    -- SPEC.md section 1: money"
check "no INR default survives" \
  "$(psql_q "select count(*) from information_schema.columns where table_schema='public' and column_name='currency' and column_default like '%INR%'")" "0"
check "documents carry a stored FX rate" \
  "$(psql_q "select count(*) from (values ('sales_invoices'),('sales_orders'),('purchase_orders'),('credit_notes'),('debit_notes'),('performa_invoices'),('supplier_credit_notes')) as t(n) where not exists (select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=t.n and c.column_name='fx_rate_date')")" "0"
check "a non-GBP document cannot omit its rate" \
  "$(psql_q "select count(*) from pg_constraint where conname='sales_invoices_fx_complete'")" "1"

echo "    -- SPEC.md section 4: identity and customs"
check "no India identity columns remain" \
  "$(psql_q "select count(*) from information_schema.columns where table_schema='public' and (column_name like '%pin_code%' or column_name like '%hsn%' or column_name in ('gstn','gstin','gst_number','pan_number','ifsc_code','place_of_supply','gst_tax_location'))")" "0"
check "companies carry VAT, EORI and XI numbers" \
  "$(psql_q "select count(*) from information_schema.columns where table_schema='public' and table_name='companies' and column_name in ('vat_number','eori_number','xi_vat_number','company_registration_number')")" "4"

echo "    -- the batch traceability structure"
check "batches and batch_movements exist" \
  "$(psql_q "select count(*) from pg_tables where schemaname='public' and tablename in ('batches','batch_movements')")" "2"
check "batch tables are company-scoped" \
  "$(psql_q "select count(*) from (values ('batches'),('batch_movements')) as t(n) where not exists (select 1 from pg_policies p where p.tablename=t.n and p.qual like '%user_company_id%')")" "0"
check "stock lines can name a batch" \
  "$(psql_q "select count(*) from (values ('sales_invoice_items'),('sales_order_items'),('grn_line_items'),('return_order_lines'),('inventory_transactions'),('stock_transfers'),('inventory_adjustments')) as t(n) where not exists (select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=t.n and c.column_name='batch_id')")" "0"
check "products carry shelf life" \
  "$(psql_q "select count(*) from information_schema.columns where table_schema='public' and table_name='products' and column_name in ('shelf_life_days','requires_batch_tracking')")" "2"

echo
[ "$FAILED" = "0" ] && echo "baseline verified" || echo "baseline verification FAILED"
exit "$FAILED"
