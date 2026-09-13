#!/usr/bin/env bash
# Install the FX worker watchdog as a systemd user timer.
#
#   ./scripts/install-fx-watchdog.sh
#
# Needs no secrets of its own: the watchdog reads .env the same way every other
# script here does. Lingering must be on, or this dies at logout, which is the
# case it exists for.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNITS="$HOME/.config/systemd/user"

# The unit hardcodes %h/projects/vega because a systemd unit cannot ask where it
# was installed from. Refuse rather than install something that will silently
# never run.
EXPECTED="$HOME/projects/vega"
if [ "$ROOT" != "$EXPECTED" ]; then
  echo "This repo is at $ROOT, but the unit runs $EXPECTED/scripts/fx-worker-watchdog.sh." >&2
  echo "Install from $EXPECTED, or edit ExecStart in the unit first." >&2
  exit 1
fi

mkdir -p "$UNITS"
cp "$ROOT/deploy/systemd/vega-fx-watchdog.service" "$UNITS/"
cp "$ROOT/deploy/systemd/vega-fx-watchdog.timer" "$UNITS/"
systemctl --user daemon-reload
systemctl --user enable --now vega-fx-watchdog.timer
echo "installed and enabled vega-fx-watchdog.timer"

if [ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" != "yes" ]; then
  echo
  echo "LINGERING IS OFF. This timer dies at logout and does not come back after"
  echo "a reboot, which is the case it exists for. Run:"
  echo "    loginctl enable-linger $USER"
  exit 1
fi

systemctl --user list-timers vega-fx-watchdog.timer --no-pager
