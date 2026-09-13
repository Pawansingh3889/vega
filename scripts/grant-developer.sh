#!/usr/bin/env bash
# Grant or revoke the developer override.
#
# A grant lets one account act in ANY company by setting the x-vega-company
# header, without membership. It is a real cross-tenant hole with an expiry
# attached. See migration 0015 for what it does and does not do.
#
#   ./scripts/grant-developer.sh grant  <email> <days> "<reason>"
#   ./scripts/grant-developer.sh revoke <email>
#   ./scripts/grant-developer.sh list
#
# Uses the service role, because developer_access is deliberately unreachable
# through the API.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
DSN="postgresql://postgres.${VITE_SUPABASE_PROJECT_ID}:${VEGA_DB_PASSWORD}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
psql_run() { docker run --rm -i --network host docker.io/library/postgres:17 psql "$DSN" -v ON_ERROR_STOP=1 "$@"; }

case "${1:-list}" in
  grant)
    EMAIL="${2:?email required}"; DAYS="${3:-90}"; REASON="${4:?reason required}"
    psql_run -q -c "INSERT INTO public.developer_access (email, reason, expires_at)
                    VALUES ('$EMAIL', '$REASON', now() + make_interval(days => $DAYS))
                    ON CONFLICT (email) DO UPDATE
                      SET expires_at = EXCLUDED.expires_at,
                          reason     = EXCLUDED.reason,
                          granted_at = now()"
    echo "granted to $EMAIL for $DAYS days"
    ;;
  revoke)
    psql_run -q -c "DELETE FROM public.developer_access WHERE lower(email) = lower('${2:?email required}')"
    echo "revoked for ${2}"
    ;;
  list)
    echo "email | expires | days left | reason"
    psql_run -tAc "SELECT email || ' | ' || expires_at::date || ' | ' ||
                          greatest(0, extract(day from expires_at - now()))::int || ' | ' || reason
                     FROM public.developer_access ORDER BY expires_at"
    ;;
  *) echo "usage: grant-developer.sh [grant <email> <days> <reason> | revoke <email> | list]"; exit 2 ;;
esac
