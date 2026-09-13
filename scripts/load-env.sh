# Source this, do not run it:  . "$ROOT/scripts/load-env.sh"
#
# .env deliberately holds ${VEGA_DB_PASSWORD} and ${VEGA_API_PASSWORD} rather
# than the passwords themselves, so the file can be read without handing over a
# credential. That means anything sourcing it under `set -u` trips on the
# placeholders unless they are exported first.
#
# Doing that in one place rather than in every script, because getting it wrong
# fails at the point of use with a message about an unbound variable, which
# sounds like a bug in the script rather than a missing secret.

VEGA_DB_PASSWORD="$(pass show supabase/vega-uk-db)"
export VEGA_DB_PASSWORD
if pass show supabase/vega-api-role >/dev/null 2>&1; then
  VEGA_API_PASSWORD="$(pass show supabase/vega-api-role)"
  export VEGA_API_PASSWORD
else
  # Not provisioned yet. Empty is fine for anything that only needs the admin
  # connection, and the API itself fails loudly if it is actually required.
  export VEGA_API_PASSWORD=""
fi

set -a
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/.env"
set +a
