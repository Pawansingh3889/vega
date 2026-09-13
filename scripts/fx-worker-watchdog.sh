#!/usr/bin/env bash
# Restart the FX worker when it has stopped talking to the database.
#
# WHY THIS EXISTS. On 7 September 2026 the worker sat for 7 hours 49 minutes
# having stopped, while every signal said it was fine:
#
#   systemctl --user is-active vega-worker   ->  active
#   podman ps                                ->  Up 8 hours
#   PID 1 in the container                   ->  alive
#   last heartbeat in the database           ->  7h49m old
#   jobs ever deferred or run                ->  0
#
# `Restart=always` is set on the unit and never fired, because nothing exited.
# Procrastinate logged "Stop requested" after a pooler timeout and stopped its
# worker loop, but the process stayed up, so systemd had nothing to restart.
#
# That matters more here than for most services. The ECB publishes once and does
# not republish, so a day the worker sleeps through is a rate that cannot be
# recovered later, and an invoice raised that day has no rate to store on it.
#
# The heartbeat is the only signal that distinguishes working from present, so
# that is the one this watches.
#
#   ./scripts/fx-worker-watchdog.sh          check, restart if stale
#   CHECK_ONLY=1 ./scripts/fx-worker-watchdog.sh   report, never restart
#
# Env: STALE_AFTER_SECONDS (default 600)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"

STALE_AFTER="${STALE_AFTER_SECONDS:-600}"
UNIT="vega-worker.service"

container() {
  if command -v podman >/dev/null 2>&1; then podman "$@"; else docker "$@"; fi
}

DSN="postgresql://postgres.${VITE_SUPABASE_PROJECT_ID}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"

# Age of the newest heartbeat in whole seconds, or -1 when no worker is
# registered at all. Empty output means the query itself failed.
#
# The -1 is not decoration. Procrastinate DELETES the worker row on a clean
# shutdown, so a stopped worker leaves zero rows and `max()` returns NULL. The
# first version of this returned empty for that and refused to restart, which
# is precisely backwards: no row means no worker is connected. Stopping the
# worker on purpose is what found it. `coalesce` keeps "nothing registered"
# apart from "could not ask".
age_seconds() {
  container run --rm -e PGCONNECT_TIMEOUT=20 docker.io/library/postgres:17 \
    psql "$DSN" -tAc \
    "select coalesce(
              floor(extract(epoch from (now() - max(last_heartbeat))))::bigint,
              -1)
       from procrastinate.procrastinate_workers" 2>/dev/null | tr -d '[:space:]'
}

AGE="$(age_seconds || true)"

if [ -z "$AGE" ]; then
  # Could not read the heartbeat at all. Deliberately NOT a restart: the most
  # likely cause is that this machine cannot reach Supabase, and bouncing the
  # worker every 15 minutes through a network outage helps nothing and buries
  # the real signal.
  echo "fx-watchdog: cannot read the heartbeat. Not restarting; check connectivity." >&2
  exit 1
fi

if [ "$AGE" -eq -1 ]; then
  echo "fx-watchdog: no worker is registered at all." >&2
elif [ "$AGE" -le "$STALE_AFTER" ]; then
  echo "fx-watchdog: worker heartbeat is ${AGE}s old, healthy (limit ${STALE_AFTER}s)."
  exit 0
else
  echo "fx-watchdog: heartbeat is ${AGE}s old, over the ${STALE_AFTER}s limit." >&2
fi

if [ "${CHECK_ONLY:-0}" = "1" ]; then
  echo "fx-watchdog: CHECK_ONLY set, not restarting." >&2
  exit 1
fi

echo "fx-watchdog: restarting $UNIT" >&2
systemctl --user restart "$UNIT"

# Say whether it worked, rather than assuming. A restart that leaves the
# heartbeat stale is the case worth shouting about, and it is the case this
# whole script exists because nobody could see.
sleep 30
AFTER="$(age_seconds || true)"
if [ -n "$AFTER" ] && [ "$AFTER" -ne -1 ] && [ "$AFTER" -le "$STALE_AFTER" ]; then
  echo "fx-watchdog: recovered, heartbeat is now ${AFTER}s old."
  exit 0
fi

echo "fx-watchdog: RESTARTED AND STILL STALE (${AFTER:-unreadable}s). Needs a person." >&2
exit 1
