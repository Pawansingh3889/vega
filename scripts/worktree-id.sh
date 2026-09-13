# Source this, do not run it:  . "$ROOT/scripts/worktree-id.sh"
#
# Gives every worktree its own container names and its own block of ports.
#
# WHY. The scripts used fixed names (`vega-verify-baseline`, `vega-pytest-rls`)
# and fixed ports. Two checkouts running the gate at the same time is not a rare
# case, it is the normal case, and `podman rm -f vega-verify-baseline` from one
# kills the database the other is mid-test against. That surfaces as a flaky
# test rather than as a collision, which is the worst way for it to appear.
#
# HOW. A short stable id derived from the worktree's absolute path. Same
# worktree always gets the same id, so containers are reusable; different
# worktrees can never collide.

_vega_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# The id is written to a file rather than recomputed everywhere. The Python test
# suite needs the same value, and `cksum` and Python's crc32 are different
# algorithms, so deriving it twice gave one worktree two identities. One file,
# read by both, cannot drift.
if [ ! -f "$_vega_root/.vega-worktree-id" ]; then
  printf '%02d' "$(( $(printf '%s' "$_vega_root" | cksum | cut -d' ' -f1) % 90 ))" \
    > "$_vega_root/.vega-worktree-id"
fi
VEGA_WORKTREE_ID="$(cat "$_vega_root/.vega-worktree-id")"
export VEGA_WORKTREE_ID

# Distinct names per worktree.
export VEGA_CONTAINER_PREFIX="vega-${VEGA_WORKTREE_ID}"

# Distinct port block per worktree: base 54300 plus 100 per worktree, so
# worktree 07 gets 55000-55009. Well clear of Supabase's own 54321-54324.
VEGA_PORT_BASE="$((54400 + VEGA_WORKTREE_ID * 100))"
export VEGA_PORT_BASE
export VEGA_VERIFY_PORT="$((VEGA_PORT_BASE + 1))"
export VEGA_REPLAY_PORT="$((VEGA_PORT_BASE + 2))"
export VEGA_RESTORE_PORT="$((VEGA_PORT_BASE + 3))"
export VEGA_DRIFT_PORT="$((VEGA_PORT_BASE + 4))"
export VEGA_PYTEST_PORT="$((VEGA_PORT_BASE + 5))"
