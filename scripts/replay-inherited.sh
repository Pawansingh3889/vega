#!/usr/bin/env bash
# Replay the archived inherited migrations and report what happens. Diagnostic
# only: it writes a report and changes nothing.
#
# Vega's baseline is NOT derived by this script. Replaying the 344 inherited
# migrations against a stock Postgres with a shim leaves 55 of them failing and
# the result short of one table, eight policies and seven functions. The
# baseline is adopted from rigel-inventory's verified India dump instead, and
# this script exists to document that decision rather than to be trusted.
#
# Run it when you want to see the current failure profile, for instance after
# improving scripts/supabase-shim.sql.
#
#   ./scripts/replay-inherited.sh
#
# Env:
#   PGPORT   host port for the throwaway container (default 54329)
#   KEEP     set to 1 to leave the container running for inspection

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/worktree-id.sh"
# shellcheck disable=SC1091
. "$ROOT/scripts/pg-wait.sh"
MIGDIR="$ROOT/supabase/archive"
ARCHIVE="$ROOT/supabase/archive"
OUT="$MIGDIR/00000000000000_inherited_baseline.sql"
REPORT="$ROOT/supabase/archive/replay-report.tsv"
PORT="${PGPORT:-${VEGA_REPLAY_PORT}}"
NAME="${VEGA_CONTAINER_PREFIX}-baseline-squash"

# podman-as-docker writes an "Emulate Docker CLI" notice to stderr on every exec,
# which otherwise masks the actual psql error in the replay report.
psql_run() { docker exec -i "$NAME" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }

cleanup() {
  if [ "${KEEP:-0}" != "1" ]; then docker rm -f "$NAME" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

echo "==> throwaway Postgres on :$PORT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -e POSTGRES_PASSWORD=postgres -p "$PORT:5432" docker.io/library/postgres:17 >/dev/null
wait_for_postgres "$NAME"

echo "==> Supabase shim (roles, auth schema, extensions)"
psql_run < "$ROOT/scripts/supabase-shim.sql" >/dev/null

echo "==> replaying inherited migrations"
mkdir -p "$ARCHIVE"
: > "$REPORT"
ERRTMP=$(mktemp)
trap 'rm -f "$ERRTMP"' RETURN 2>/dev/null || true
ok=0; fail=0
# Inherited migrations carry a 14-digit timestamp prefix. Vega's own are 000N_.
for f in $(find "$MIGDIR" -maxdepth 1 -name '*.sql' | sort); do
  n="$(basename "$f")"
  if psql_run < "$f" >/dev/null 2>"$ERRTMP"; then
    printf '%s\tOK\t\n' "$n" >> "$REPORT"; ok=$((ok+1))
  else
    msg=$(grep -v "Emulate Docker CLI" "$ERRTMP" | grep -m1 "ERROR" | tr '\t' ' ')
    printf '%s\tFAIL\t%s\n' "$n" "${msg:-unknown}" >> "$REPORT"
    fail=$((fail+1))
  fi
done
echo "    $ok ok, $fail failed (see supabase/archive/replay-report.tsv)"


echo "==> report written to supabase/archive/replay-report.tsv (diagnostic only)"
