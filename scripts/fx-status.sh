#!/usr/bin/env bash
# What FX history do we hold, and is there a gap?
#
# The worker runs locally, so it only fetches while this machine is awake. A
# missed working day is a real gap: the ECB does not republish, so a rate not
# captured on the day is gone. This is the check that makes that visible rather
# than discovered during a restatement months later.

set -euo pipefail

# The `docker` command here is podman's compatibility wrapper, which prints
# "Emulate Docker CLI using podman" to stderr on every single invocation unless
# /etc/containers/nodocker exists, and creating that needs root. Calling podman
# directly skips the wrapper and the noise, while still working on a machine
# with real Docker.
container() {
  if command -v podman >/dev/null 2>&1; then podman "$@"; else docker "$@"; fi
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
DSN="postgresql://postgres.${VITE_SUPABASE_PROJECT_ID}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"

# Retry, and say why on failure. The Supabase pooler times out intermittently
# from here, and `set -e` plus a silent psql turns that into a bare "Error 1"
# that tells the reader nothing about whether their data is missing or their
# network is.
attempt=0
while :; do
  attempt=$((attempt + 1))
  if OUT=$(container run --rm -i --network host docker.io/library/postgres:17 psql "$DSN" -q -c "
WITH held AS (
  SELECT rate_date FROM public.fx_rates
   WHERE base_currency = 'EUR' AND quote_currency = 'GBP'
),
working_days AS (
  SELECT d::date AS day
    FROM generate_series(
           COALESCE((SELECT min(rate_date) FROM held), current_date),
           current_date, interval '1 day') d
   WHERE extract(isodow FROM d) < 6
)
SELECT
  (SELECT count(*) FROM held)                                  AS rates_held,
  (SELECT max(rate_date) FROM held)                            AS newest,
  (SELECT current_date - max(rate_date) FROM held)             AS days_behind,
  (SELECT count(*) FROM working_days w
    WHERE NOT EXISTS (SELECT 1 FROM held h WHERE h.rate_date = w.day)
      AND w.day < current_date)                                AS working_days_missing;
" 2>&1); then
    printf '%s\n' "$OUT" | grep -v "Emulate Docker"
    break
  fi
  if [ "$attempt" -ge 3 ]; then
    echo "Could not read fx_rates after $attempt attempts." >&2
    printf '%s\n' "$OUT" | grep -v "Emulate Docker" | tail -3 >&2
    echo >&2
    echo "This is about reaching the database, not about the data. The Supabase" >&2
    echo "pooler times out intermittently; try again in a moment." >&2
    exit 1
  fi
  sleep 3
done

echo "Note: the ECB publishes on working days only, so a Saturday or Sunday gap is"
echo "expected. A missing weekday means the worker was not running that day."
