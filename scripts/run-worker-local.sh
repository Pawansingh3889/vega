#!/usr/bin/env bash
# Run the job worker locally, in the same container image Fly would run.
#
# WHY THIS IS A REASONABLE PLACE FOR IT. The worker's only job today fetches one
# XML file a day. Paying a cloud provider a standing monthly charge for that is
# poor value while the API has no callers, and the container is identical either
# way, so moving it to Fly later is a deploy rather than a rewrite.
#
# WHAT IT COSTS YOU INSTEAD. The job only runs while this machine is awake. A
# missed day is a real gap, because a published FX rate is gone once the day
# passes, so check `make fx-status` occasionally. That is the honest trade.
#
#   ./scripts/run-worker-local.sh start
#   ./scripts/run-worker-local.sh logs
#   ./scripts/run-worker-local.sh once     # run the FX job now, do not wait for the schedule
#   ./scripts/run-worker-local.sh status
#   ./scripts/run-worker-local.sh stop

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
. "$ROOT/scripts/worktree-id.sh"
NAME="${VEGA_CONTAINER_PREFIX}-worker"
IMAGE="vega-api:${VEGA_WORKTREE_ID}"

# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
REF="${VITE_SUPABASE_PROJECT_ID:?missing from .env}"
API_PW="$(pass show supabase/vega-api-role)"

# The SESSION pooler, 5432. Procrastinate wakes on LISTEN/NOTIFY and that does
# not survive the transaction pooler on 6543: jobs would run only on the poll
# interval, which reads as "slow" rather than "broken".
WORKER_DSN="postgresql://vega_api.${REF}:${API_PW}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"

build_if_missing() {
  container image inspect "$IMAGE" >/dev/null 2>&1 || {
    echo "==> building $IMAGE"
    container build -t "$IMAGE" "$ROOT/apps/api"
  }
}

case "${1:-status}" in
  start)
    build_if_missing
    container rm -f "$NAME" >/dev/null 2>&1 || true
    container run -d --name "$NAME" --network host --restart unless-stopped \
      -e VITE_SUPABASE_URL="https://${REF}.supabase.co" \
      -e VEGA_DATABASE_URL="$WORKER_DSN" \
      -e VEGA_WORKER_DATABASE_URL="$WORKER_DSN" \
      "$IMAGE" procrastinate --app vega_api.tasks.app worker >/dev/null
    sleep 4
    if container ps --format '{{.Names}}' | grep -qx "$NAME"; then
      echo "worker running. Daily FX ingestion at 16:30 UTC."
      container logs "$NAME" 2>&1 | tail -4
    else
      echo "worker exited immediately:"; container logs "$NAME" 2>&1 | tail -12; exit 1
    fi
    ;;
  once)
    build_if_missing
    container run --rm --network host \
      -e VITE_SUPABASE_URL="https://${REF}.supabase.co" \
      -e VEGA_DATABASE_URL="$WORKER_DSN" \
      -e VEGA_WORKER_DATABASE_URL="$WORKER_DSN" \
      "$IMAGE" python -c "
import asyncio, sys
from datetime import UTC, datetime
import asyncpg
from vega_api.config import get_settings
from vega_api.modules import fx

async def main():
    conn = await asyncpg.connect(get_settings().database_url)
    try:
        n = await fx.ingest(conn, today=datetime.now(UTC).date())
        if n:
            print(f'stored {n} new rate(s)')
        else:
            print('nothing new: the published day is already held')
    except fx.FeedRejectedError as e:
        print(f'refused: {e}'); sys.exit(1)
    finally:
        await conn.close()

asyncio.run(main())
"
    ;;
  logs)   container logs -f "$NAME" ;;
  stop)   container rm -f "$NAME" >/dev/null 2>&1 && echo "worker stopped" ;;
  status)
    if container ps --format '{{.Names}}' | grep -qx "$NAME"; then
      echo "worker: running"
    else
      echo "worker: not running"
    fi
    ;;
  *) echo "usage: run-worker-local.sh [start|once|logs|status|stop]"; exit 2 ;;
esac
