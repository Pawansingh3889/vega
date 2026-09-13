#!/usr/bin/env bash
# Load the known dataset: one small UK food manufacturer.
#
# auth.users belongs to GoTrue, so the seed SQL does not touch it. Against a
# real Supabase project this creates the user through the Auth admin API, which
# makes it an identity somebody can actually sign in as. Against a local shim
# database there is no GoTrue, so the row is inserted directly.
#
#   ./scripts/seed-demo.sh --local <container-name>
#   ./scripts/seed-demo.sh --hosted            # uses .env + pass
#
# The user id is fixed so the drill can compare exact values.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$ROOT/supabase/seed.sql"
USER_ID="11111111-0000-4000-8000-0000000000f1"
USER_EMAIL="ruth@pennine-bakehouse.test"
MODE="${1:---hosted}"

case "$MODE" in
  --local)
    CONTAINER="${2:?usage: seed-demo.sh --local <container>}"
    docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<SQL >/dev/null
INSERT INTO auth.users (id, email) VALUES ('$USER_ID', '$USER_EMAIL')
  ON CONFLICT (id) DO NOTHING;
SQL
    docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$SEED" >/dev/null
    echo "seeded local container $CONTAINER"
    ;;

  --hosted)
    # .env deliberately holds ${VEGA_DB_PASSWORD} rather than the password, so
    # supply it from pass before sourcing or set -u trips on the placeholder.
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
    : "${VITE_SUPABASE_URL:?}" "${SUPABASE_SERVICE_ROLE_KEY:?}"

    # Idempotent: delete any prior identity at this id, then recreate it.
    curl -s -o /dev/null -X DELETE \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      "$VITE_SUPABASE_URL/auth/v1/admin/users/$USER_ID" || true

    code=$(curl -s -o /tmp/vega-seed-user.json -w '%{http_code}' -X POST \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"$USER_ID\",\"email\":\"$USER_EMAIL\",\"password\":\"$(pass show supabase/vega-demo-user)\",\"email_confirm\":true}" \
      "$VITE_SUPABASE_URL/auth/v1/admin/users")
    if [ "$code" != "200" ] && [ "$code" != "201" ]; then
      echo "creating the demo user failed with HTTP $code"; head -c 400 /tmp/vega-seed-user.json; exit 1
    fi
    echo "demo user created via the Auth admin API"

    PGPASSWORD="$(pass show supabase/vega-uk-db)" \
    docker run --rm -i --network host docker.io/library/postgres:17 \
      psql "postgresql://postgres.${VITE_SUPABASE_PROJECT_ID}:$(pass show supabase/vega-uk-db)@aws-0-eu-west-2.pooler.supabase.com:5432/postgres" \
      -v ON_ERROR_STOP=1 < "$SEED" >/dev/null
    echo "seeded hosted project ${VITE_SUPABASE_PROJECT_ID}"
    ;;

  *) echo "usage: seed-demo.sh [--local <container> | --hosted]"; exit 2 ;;
esac
