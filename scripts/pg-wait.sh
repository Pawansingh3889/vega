# Source this, do not run it:  . "$ROOT/scripts/pg-wait.sh"
#
#   wait_for_postgres <container-name>
#
# WHY. `pg_isready` reports ready against a server that is about to disappear.
# The official image starts a temporary server to run its init scripts, then
# shuts it down and restarts it for real, and `pg_isready` answers yes across
# that whole window.
#
# Sampled at 50ms against postgres:17, three consecutive container starts:
#
#   trial 1:  13 ..   1 .Q   1 R.   1 .Q   104 RQ
#   trial 2:  12 ..   1 RQ   1 ..   106 RQ
#   trial 3:  12 ..   1 RQ   1 ..   1 .Q   105 RQ
#
#   (R = pg_isready says ready, Q = `SELECT 1` actually succeeds, . = neither)
#
# Trial 1's `R.` is `pg_isready` reporting ready while a real query fails, which
# is the state `verify-baseline.sh` used to break its wait loop in and then run
# the shim into. Trials 2 and 3 rule out the obvious fix as well: `RQ` followed
# by `..` is a real query succeeding and the server going away afterwards, so
# waiting for one good query is not enough either.
#
# HOW. Require two successful queries a second apart. The dead window above is
# 50 to 100ms, so a one second gap clears it with room to spare. This is the
# same rule `apps/api/tests/conftest.py` already applies; it lived only in the
# Python path, which is why the two shell scripts kept flaking.
#
# Refuses loudly rather than returning. A wait that gives up quietly turns "the
# database never started" into a confusing SQL error thirty lines later, which
# is how this cost a CI log read instead of one line of output.

wait_for_postgres() {
  local name="$1"
  local timeout="${2:-90}"
  local stable=0
  local attempt

  for attempt in $(seq 1 "$timeout"); do
    if docker exec "$name" psql -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
      stable=$((stable + 1))
      if [ "$stable" -ge 2 ]; then
        return 0
      fi
    else
      stable=0
    fi
    sleep 1
  done

  # podman-as-docker writes an "Emulate Docker CLI" notice to stderr on every
  # call, which otherwise pads out the only output anybody reads here.
  echo "FAIL: Postgres in container '$name' never became ready after ${timeout}s." >&2
  echo "      Last 20 lines of its log:" >&2
  docker logs --tail 20 "$name" 2>&1 | grep -v "Emulate Docker CLI" >&2 || true
  return 1
}
