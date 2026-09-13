#!/usr/bin/env bash
# Install the daily backup timer. Reads the connection string from the password
# store and writes it to an EnvironmentFile at 0600, the same shape
# install-worker-service.sh uses. Nothing sensitive enters git or the unit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$HOME/.config/vega"
UNITS="$HOME/.config/systemd/user"
mkdir -p "$CONF" "$UNITS"

# shellcheck disable=SC1091
. "$ROOT/scripts/load-env.sh"
: "${VEGA_DATABASE_URL:?VEGA_DATABASE_URL is not set, so the timer would have nothing to dump}"

umask 077
cat > "$CONF/backup.env" <<ENVEOF
VEGA_DATABASE_URL=$VEGA_DATABASE_URL
VEGA_BACKUP_DIR=$HOME/.local/share/vega/backups
VEGA_BACKUP_KEEP_DAYS=30
ENVEOF
chmod 600 "$CONF/backup.env"
echo "wrote $CONF/backup.env (mode $(stat -c %a "$CONF/backup.env"))"

install -m 644 "$ROOT/deploy/systemd/vega-backup.service" "$UNITS/vega-backup.service"
install -m 644 "$ROOT/deploy/systemd/vega-backup.timer" "$UNITS/vega-backup.timer"
systemctl --user daemon-reload
systemctl --user enable --now vega-backup.timer
echo

if [ "$(loginctl show-user "$USER" --property=Linger --value)" != "yes" ]; then
  echo "WARNING: lingering is off, so this timer stops when you log out." >&2
  echo "  loginctl enable-linger $USER" >&2
fi

systemctl --user list-timers vega-backup.timer --no-pager
echo
echo "Run it once now, rather than finding out tomorrow whether it works:"
echo "  systemctl --user start vega-backup.service && journalctl --user -u vega-backup -n 20"
