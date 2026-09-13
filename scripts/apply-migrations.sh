#!/usr/bin/env bash
# Apply the migration history to the hosted project, and prove it landed.
#
#   ./scripts/apply-migrations.sh            show what is pending, change nothing
#   ./scripts/apply-migrations.sh --apply    push, then verify
#
# WHY THIS EXISTS. Nothing applied migrations to London. The schema got there
# once by hand and four migrations written afterwards stayed in the repository,
# so issued invoices were not frozen and invoice numbering was not gapless on
# the database that actually holds invoices, while the ROADMAP recorded both as
# done. See #99 and #100.
#
# The push itself is `supabase db push`, which is the sanctioned tool and knows
# how to record what it applied. This wrapper adds the two things that make it
# safe to run: it says what will change before it changes anything, and it
# proves the result afterwards rather than trusting the push's exit code.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"

REF="${VITE_SUPABASE_PROJECT_ID:?VITE_SUPABASE_PROJECT_ID missing from .env}"
: "${VEGA_DB_PASSWORD:?VEGA_DB_PASSWORD missing; scripts/load-env.sh reads it from pass}"

command -v supabase >/dev/null || {
  echo "the supabase CLI is not on PATH. https://supabase.com/docs/guides/cli" >&2
  exit 1
}

# Session pooler on 5432. The transaction pooler on 6543 cannot hold the
# advisory lock the migration runner takes.
DB_URL="postgresql://postgres.${REF}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"

pending() {
  supabase migration list --db-url "$DB_URL" 2>/dev/null \
    | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
start = raw.find("{")
if start < 0:
    sys.exit("could not read the migration list")
rows = json.loads(raw[start:]).get("migrations", [])
for row in rows:
    if row.get("local") and not row.get("remote"):
        print(row["local"])
'
}

echo "==> reading the migration history on ${REF}"
PENDING="$(pending)"

if [ -z "$PENDING" ]; then
  echo "    nothing pending: the hosted project has every migration in this tree."
  exit 0
fi

COUNT="$(printf '%s\n' "$PENDING" | wc -l | tr -d ' ')"
echo
echo "    ${COUNT} migration(s) in this tree have never been applied to ${REF}:"
printf '%s\n' "$PENDING" | sed 's/^/      /'
echo

if [ "${1:-}" != "--apply" ]; then
  echo "    Nothing was changed. Re-run with --apply to push them."
  echo "    Read them first: this writes to the database that holds real invoices."
  exit 0
fi

# One thing worth knowing before the numbering migration runs: it adds a unique
# index on (company_id, invoice_number), and an index cannot be built over rows
# that already violate it. Better to say so here than to have the push fail
# halfway with a Postgres error nobody has context for.
echo "==> checking for duplicate invoice numbers, which would refuse the unique index"
DUPES="$(
  podman run --rm -e PGCONNECT_TIMEOUT=20 docker.io/library/postgres:17 \
    psql "$DB_URL" -tAc "
      select count(*) from (
        select company_id, invoice_number
          from public.sales_invoices
         where invoice_number is not null
         group by 1, 2 having count(*) > 1
      ) d" 2>/dev/null | tr -d '[:space:]'
)"

if [ -z "$DUPES" ]; then
  echo "    could not read sales_invoices to check. Not pushing blind." >&2
  exit 1
fi
if [ "$DUPES" != "0" ]; then
  echo "    ${DUPES} (company, invoice_number) pair(s) are already duplicated." >&2
  echo "    The unique index will refuse to build. Resolve those first." >&2
  exit 1
fi
echo "    none"

echo "==> pushing"
supabase db push --db-url "$DB_URL"

# Verify rather than believe. A push that reports success and leaves the schema
# short is the failure this whole script exists because of, so the proof is the
# same comparison #99 was found with, not the push's own exit code.
echo "==> verifying: the hosted schema must now match the migrations"
"$ROOT/scripts/check-schema-drift.sh"
echo
echo "applied and verified."
