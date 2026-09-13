#!/usr/bin/env bash
# Install the worker as a systemd user service so it survives a reboot.
#
# The env file is written outside the repository, holding the pooler DSN with
# its password. It never enters git, and it is written 0600.
#
#   ./scripts/install-worker-service.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"

REF="${VITE_SUPABASE_PROJECT_ID:?missing from .env}"
API_PW="$(pass show supabase/vega-api-role)"
CONF="$HOME/.config/vega"
UNITS="$HOME/.config/containers/systemd"

mkdir -p "$CONF" "$UNITS"
umask 077
cat > "$CONF/worker.env" <<ENVEOF
VITE_SUPABASE_URL=https://${REF}.supabase.co
VEGA_DATABASE_URL=postgresql://vega_api.${REF}:${API_PW}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres
VEGA_WORKER_DATABASE_URL=postgresql://vega_api.${REF}:${API_PW}@aws-0-eu-west-2.pooler.supabase.com:5432/postgres
ENVEOF
chmod 600 "$CONF/worker.env"
echo "wrote $CONF/worker.env (mode $(stat -c %a "$CONF/worker.env"))"

podman build -q -t localhost/vega-api:worker "$ROOT/apps/api" >/dev/null
echo "built localhost/vega-api:worker"

cp "$ROOT/deploy/systemd/vega-worker.container" "$UNITS/"
systemctl --user daemon-reload
echo "unit installed"

if [ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" != "yes" ]; then
  echo
  echo "LINGERING IS OFF. Without it this dies at logout and does not come back"
  echo "after a reboot, which is the case the service exists for. Run:"
  echo "    loginctl enable-linger $USER"
fi
