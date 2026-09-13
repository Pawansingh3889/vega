#!/usr/bin/env python3
"""Emit Procrastinate's schema as a Vega migration.

Procrastinate ships its schema as SQL and normally applies it with its own CLI.
Doing that here would break SECURITY.md N2 twice over: the tables would be
created by whichever role ran the command, and they would sit outside the
migration history that `make db-verify` rebuilds from.

So the schema is generated into a migration instead. It is created by the
migration role, which means postgres owns it and vega_api does not, and it lands
in a dedicated `procrastinate` schema so `public` keeps holding only business
tables and the "every table has RLS" assertion stays meaningful.

Regenerate after upgrading procrastinate:

    python3 scripts/generate-procrastinate-migration.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "supabase" / "migrations" / "0016_procrastinate_schema.sql"


def main() -> int:
    raw = subprocess.run(
        ["uv", "run", "python", "-c",
         "from procrastinate.schema import SchemaManager; print(SchemaManager.get_schema())"],
        cwd=ROOT / "apps" / "api", capture_output=True, text=True, check=True,
    ).stdout
    version = subprocess.run(
        ["uv", "run", "python", "-c",
         "import procrastinate; print(procrastinate.__version__)"],
        cwd=ROOT / "apps" / "api", capture_output=True, text=True, check=True,
    ).stdout.strip()

    header = f"""-- Procrastinate's job schema, generated. Do not edit by hand.
--
-- Generated from procrastinate {version} by
-- scripts/generate-procrastinate-migration.py. Regenerate after an upgrade
-- rather than patching this file.
--
-- WHY IT IS A MIGRATION. Procrastinate normally applies this with its own CLI,
-- which would create the objects as whoever ran the command and leave them
-- outside the history `make db-verify` rebuilds from. Generating it here means
-- the migration role owns the tables, so vega_api does not, which is what
-- SECURITY.md N2 requires.
--
-- WHY ITS OWN SCHEMA. The SQL below uses unqualified names, so it lands
-- wherever search_path points. Putting it in `procrastinate` keeps `public`
-- holding business tables only, which is what makes the "every table has RLS"
-- assertion mean something. A job queue is not tenant data and has no company
-- column to scope by; it is reachable only by the one role granted below.

CREATE SCHEMA IF NOT EXISTS procrastinate;

-- Session-scoped, not SET LOCAL. psql wraps each statement in its own implicit
-- transaction, so SET LOCAL would last exactly one statement and every object
-- below would land in public instead. The verifier caught precisely that.
SET search_path TO procrastinate;

"""
    footer = """
SET search_path TO public;

-- The worker's reach: use the schema and work the queue, own none of it.
GRANT USAGE ON SCHEMA procrastinate TO vega_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA procrastinate TO vega_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA procrastinate TO vega_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA procrastinate TO vega_api;

-- Nobody signed in through the browser has any business here.
REVOKE ALL ON SCHEMA procrastinate FROM anon, authenticated;

-- The queue must be in its own schema. If search_path did not hold, these
-- tables are sitting in public without RLS, which the baseline verifier will
-- also catch, but failing here says why.
DO $vega$
DECLARE stray text;
BEGIN
  SELECT string_agg(tablename, ', ') INTO stray
    FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'procrastinate%';
  IF stray IS NOT NULL THEN
    RAISE EXCEPTION 'job tables landed in public rather than the procrastinate schema: %', stray;
  END IF;
END
$vega$;

-- N2, asserted: the queue is not owned by the role that works it.
DO $vega$
DECLARE owned text;
BEGIN
  SELECT string_agg(c.relname, ', ') INTO owned
    FROM pg_class c
    JOIN pg_roles r ON r.oid = c.relowner
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'procrastinate'
   WHERE r.rolname = 'vega_api';
  IF owned IS NOT NULL THEN
    RAISE EXCEPTION 'vega_api owns job tables, which it must not: %', owned;
  END IF;
END
$vega$;
"""
    OUT.write_text(header + raw.strip() + "\n" + footer)
    print(f"wrote {OUT.relative_to(ROOT)} from procrastinate {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
