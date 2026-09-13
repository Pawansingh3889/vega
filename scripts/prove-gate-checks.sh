#!/usr/bin/env bash
# Break each gate check on purpose and confirm it refuses.
#
#   ./scripts/prove-gate-checks.sh
#
# WHY. START-HERE.md rule 6 asks that a new check be proven able to fail,
# and the reason is written into this repository's history: checks here have
# passed while doing nothing at least eleven times, three of them inside tools
# written specifically to stop that. A check proven once, by hand, on the day
# it was written, is a claim about the past. This is the claim as something you
# can run.
#
# Each case makes the exact mistake the check exists to catch, runs only that
# check, and puts the tree back. A check that returns 0 with its own bug in
# front of it is reported as a failure of this script.
#
# It edits tracked files, so it refuses to start on a dirty tree: restoring is
# `git checkout` and that would take your work with it.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "refusing to run: the tree is dirty." >&2
  echo "This edits tracked files and restores them with git checkout, which" >&2
  echo "would discard uncommitted work. Commit or stash first." >&2
  exit 2
fi

FAILED=0
WAIVERS="security/audit-waivers.json"

restore() {
  git checkout -q -- . 2>/dev/null || true
  rm -f supabase/migrations/0017__prove_duplicate.sql
  rm -rf apps/api/src/vega_api/modules/proveunreachable
}
trap restore EXIT

# case <name> <check command> ; the mutation is applied by the caller first.
case_is_refused() {
  local name="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  restore
  if [ "$rc" -ne 0 ]; then
    printf '  refused   %s\n' "$name"
  else
    printf '  PASSED    %s   <-- the check did not catch its own bug\n' "$name"
    printf '%s\n' "$out" | tail -3 | sed 's/^/            /'
    FAILED=1
  fi
}

echo "==> proving each gate check refuses the mistake it exists to catch"

cp supabase/migrations/0017_append_only_ledgers.sql supabase/migrations/0017__prove_duplicate.sql
case_is_refused "check-migrations, two migrations at one prefix" \
  python3 scripts/check-migrations.py

sed -i "0,/\.select(/s//.select('__prove_column_that_does_not_exist')\n    .select(/" \
  supabase/functions/verify-email-confirmation/index.ts
case_is_refused "check-edge-function-columns, a column that does not exist" \
  python3 scripts/check-edge-function-columns.py

# The bad reference is assembled here rather than written out, because
# check-citations reads this file too and would flag the probe itself. That it
# does is the check working, and it is worth knowing before you "fix" this line.
BAD_REF="N9""9"
sed -i "s/SECURITY\.md/SECURITY.md ${BAD_REF}/" docs/decisions/0004-vega-owns-carbon.md
case_is_refused "check-citations, a reference that does not resolve" \
  python3 scripts/check-citations.py

# A plain name on purpose. check-reachable skips directories starting with an
# underscore, so a probe called __prove_unreachable proves nothing: the first
# version of this script used one and reported the check as broken when the
# probe was.
mkdir -p apps/api/src/vega_api/modules/proveunreachable
printf '"""A module nothing imports."""\n' \
  > apps/api/src/vega_api/modules/proveunreachable/__init__.py
case_is_refused "check-reachable, a module nothing imports" \
  python3 scripts/check-reachable.py

python3 - "$WAIVERS" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["waivers"] = [{"advisory": "GHSA-prove", "package": "left-pad",
                 "reason": "probe", "expires": "2020-01-01"}]
p.write_text(json.dumps(d, indent=2))
PY
case_is_refused "check_audit_waivers, an expired waiver" \
  python3 scripts/check_audit_waivers.py

python3 - "$WAIVERS" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["waivers"] = [{"advisory": "GHSA-prove", "package": "left-pad", "reason": "probe"}]
p.write_text(json.dumps(d, indent=2))
PY
case_is_refused "check_audit_waivers, a waiver with no expiry" \
  python3 scripts/check_audit_waivers.py

# The one rule CONTRIBUTING states in capitals: the ceiling only goes down.
cat >> apps/web/src/lib/utils.ts <<'TS'

export function __prove(x: any): any {
  return x;
}
TS
case_is_refused "eslint ceiling, one more warning than allowed" \
  pnpm --filter @vega/web run lint

# service.py purity, the rule three modules in a row broke before it was enforced.
printf '\nimport httpx  # noqa\n' >> apps/api/src/vega_api/modules/vat/service.py
case_is_refused "import-linter, network I/O inside service.py" \
  bash -c 'cd apps/api && uv run lint-imports'

echo
if [ "$FAILED" -eq 0 ]; then
  echo "every check refused its own bug."
else
  echo "at least one check passed with its own bug in front of it." >&2
fi
exit "$FAILED"
