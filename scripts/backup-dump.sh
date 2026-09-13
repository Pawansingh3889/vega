#!/usr/bin/env bash
# Dump London to this machine, and refuse to call it a backup unless it is one.
#
# The free Supabase plan has no platform backup (ROADMAP.md item 4), so this is
# the only copy of the data that survives the project being deleted. That makes
# the verification below the point of the script rather than a nicety: pg_dump
# exits 0 on a dump that restores nothing, which is how "we have backups" and
# "we have no backups" end up looking identical.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${VEGA_BACKUP_DIR:-$HOME/.local/share/vega/backups}"
KEEP_DAYS="${VEGA_BACKUP_KEEP_DAYS:-30}"
# A dump smaller than this is not a schema plus data, whatever pg_dump said.
MIN_BYTES="${VEGA_BACKUP_MIN_BYTES:-50000}"
# Same image restore-drill.sh uses. The host has no libpq, and pinning the
# client version to the one the drill restores with means a dump this script
# writes is one that script can read.
IMAGE="${VEGA_PG_IMAGE:-docker.io/library/postgres:17}"
RUNTIME="${VEGA_CONTAINER_RUNTIME:-}"
if [[ -z "$RUNTIME" ]]; then
  if command -v docker >/dev/null 2>&1; then RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then RUNTIME=podman
  else echo "FAILED: neither docker nor podman is available, so nothing can dump." >&2; exit 1
  fi
fi
pg() { "$RUNTIME" run --rm -i --network host "$IMAGE" "$@"; }

# Under systemd the connection comes from an EnvironmentFile, and there is no
# .env or password-store agent in that context. Only fall back to the repo's
# development environment when the caller has not already supplied one.
if [[ -z "${VEGA_DATABASE_URL:-}" ]]; then
  if [[ -f "$ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    . "$ROOT/scripts/load-env.sh"
  else
    echo "FAILED: VEGA_DATABASE_URL is not set and $ROOT/.env does not exist." >&2
    echo "Under systemd this comes from ~/.config/vega/backup.env." >&2
    exit 1
  fi
fi

: "${VEGA_DATABASE_URL:?VEGA_DATABASE_URL is not set, so there is nothing to dump}"

mkdir -p "$DEST"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$DEST/vega-$stamp.sql"

echo "dumping to $out"
if ! pg pg_dump "$VEGA_DATABASE_URL" \
      --no-owner --no-privileges --schema=public \
      > "$out"; then
  rm -f "$out"
  echo "FAILED: pg_dump could not complete. No backup was written." >&2
  exit 1
fi

# --- the part that makes it a backup rather than a file ---------------------

bytes="$(stat -c %s "$out")"
if [[ "$bytes" -lt "$MIN_BYTES" ]]; then
  echo "FAILED: dump is $bytes bytes, under the $MIN_BYTES floor." >&2
  echo "pg_dump exited 0, so something answered; it did not answer with a database." >&2
  mv "$out" "$out.rejected"
  exit 1
fi

# Count what the live database has, and what the dump claims to recreate. A
# dump that is missing tables is the failure mode that looks most like success.
live_tables="$(pg psql "$VEGA_DATABASE_URL" -tAc \
  "select count(*) from information_schema.tables
    where table_schema = 'public' and table_type = 'BASE TABLE'")"
dump_tables="$(grep -cE '^CREATE TABLE ' "$out" || true)"

if [[ "$dump_tables" -ne "$live_tables" ]]; then
  echo "FAILED: London has $live_tables tables, the dump carries $dump_tables." >&2
  mv "$out" "$out.rejected"
  exit 1
fi

gzip -f "$out"
echo "ok: $out.gz ($(stat -c %s "$out.gz") bytes, $dump_tables tables)"

# Retention. Only ever removes files this script wrote.
find "$DEST" -maxdepth 1 -name 'vega-*.sql.gz' -mtime "+$KEEP_DAYS" -print -delete \
  | sed 's/^/expired: /'

# A dump nobody has restored is a hypothesis. scripts/restore-drill.sh proves
# one, and #58 asks for it to run against output from this script rather than a
# hand-made file.
echo
echo "latest: $(ls -t "$DEST"/vega-*.sql.gz | head -1)"
echo "verify with: scripts/restore-drill.sh $(ls -t "$DEST"/vega-*.sql.gz | head -1)"
