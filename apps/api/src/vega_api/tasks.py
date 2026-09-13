"""Background work.

Procrastinate keeps jobs as rows in the same Postgres, so there is no Redis to
run and a job's history is queryable next to the data it touched.

CONNECTION MODE MATTERS HERE. The worker wakes on LISTEN/NOTIFY, which does not
survive Supabase's transaction pooler on 6543. The worker therefore needs the
session pooler on 5432. Point it at 6543 and jobs still run, but only when the
poll interval comes round, which looks like "slow" rather than "broken" and is
the kind of thing nobody diagnoses for a week. See ARCHITECTURE.md section 6.
"""

from __future__ import annotations

import os
from datetime import UTC, datetime

import asyncpg
import procrastinate

from .common.db import with_schema
from .config import get_settings
from .modules import fx


def _worker_dsn() -> str:
    """The session-pooler connection, which is not the request path's."""
    dsn = os.environ.get("VEGA_WORKER_DATABASE_URL") or get_settings().database_url
    return with_schema(dsn)


# Procrastinate's SQL uses unqualified names and its App takes no schema
# argument, so the schema is chosen by the connection's search_path. Its tables
# live in `procrastinate`, created by migration 0016 and owned by the migration
# role rather than by the worker (N2). `public` stays on the path because the
# tasks themselves read business tables.
app = procrastinate.App(
    connector=procrastinate.PsycopgConnector(conninfo=_worker_dsn()),
)


# The ECB publishes once a working day, mid-afternoon CET. 16:30 UTC is after
# that on both sides of a clock change, and re-running is harmless: the insert
# is ON CONFLICT DO NOTHING, so a second read of the same day writes nothing.
#
# periodic() needs the timestamp argument: Procrastinate passes the scheduled
# time, which is also what makes a late run store the day it was FOR rather than
# the day it happened to execute.
@app.periodic(cron="30 16 * * *")
@app.task(name="fx.ingest_ecb_daily", retry=3, queue="fx")
async def ingest_ecb_daily(timestamp: int | None = None) -> int:
    """Pull today's ECB rates.

    Retries three times because the failure this most often hits is a transient
    fetch, and a missing day is a real gap: an invoice raised that day has no
    rate to store on it.

    It deliberately does NOT swallow a rejection. A feed that parsed to nothing,
    or arrived stale, must surface as a failed job rather than a successful run
    that wrote nothing (SECURITY.md N6).
    """
    # Procrastinate hands periodic tasks the scheduled unix time. Using it rather
    # than "now" means a run delayed by a restart still records the day it was
    # scheduled for, instead of quietly filing yesterday's rates under today.
    today = (
        datetime.fromtimestamp(timestamp, UTC).date()
        if timestamp is not None
        else datetime.now(UTC).date()
    )

    conn = await asyncpg.connect(get_settings().database_url)
    try:
        return await fx.ingest(conn, today=today)
    finally:
        await conn.close()


# Checked on a schedule rather than by somebody remembering to look.
#
# The worker runs on one machine, so a day it was asleep is a day with no rate,
# and the ECB does not republish: that gap is permanent. A human habit of
# running `make fx-status` is exactly the control that lapses first, so the job
# raises instead (SECURITY.md N6: a control that cannot report its own failure
# is not a control).
#
# Runs after the ingestion window so a same-day gap is real rather than early.
# Hourly, and this is the schedule that actually protects the data.
#
# The daily job at 16:30 UTC assumes the worker is running at 16:30 UTC. It runs
# on a laptop. On 2026-09-07 that laptop suspended at 21:53:05 IST and resumed
# at 22:37:25, so it was asleep at 22:00 IST, which IS 16:30 UTC, and the day
# was missed. The watchdog reported the worker healthy one second before the
# machine went down, then restarted it 59 minutes after it came back, and
# `make fx-status` said "0 working days missing" throughout because it excludes
# today by design.
#
# Nothing in that chain was going to catch it, so the fix is not another alarm.
# Procrastinate defers a periodic schedule that passed while the worker was
# down, so an hourly backfill means a machine that wakes at any point in the
# next ninety days recovers every day it slept through, without anybody
# noticing it had.
@app.periodic(cron="15 * * * *")
@app.task(name="fx.backfill_history", retry=2, queue="fx")
async def backfill_fx_history(timestamp: int | None = None) -> int:
    """Fill any gap in the last ninety days of ECB rates.

    Returns how many rates were newly stored. Zero is the normal answer and
    means there was no gap: the insert is ON CONFLICT DO NOTHING, so re-reading
    ninety days that are already held writes nothing.
    """
    when = (
        datetime.fromtimestamp(timestamp, tz=UTC).date()
        if timestamp is not None
        else datetime.now(UTC).date()
    )
    conn = await asyncpg.connect(_worker_dsn())
    try:
        return await fx.backfill(conn, today=when)
    finally:
        await conn.close()


@app.periodic(cron="0 18 * * 1-5")
@app.task(name="fx.check_for_gaps", retry=1, queue="fx")
async def check_for_gaps(timestamp: int | None = None) -> int:
    """Fail loudly when a working day has no rate."""
    del timestamp

    conn = await asyncpg.connect(get_settings().database_url)
    try:
        missing = await fx.missing_working_days(conn)
    finally:
        await conn.close()

    if missing:
        shown = ", ".join(d.isoformat() for d in missing[:10])
        more = f" and {len(missing) - 10} more" if len(missing) > 10 else ""
        raise RuntimeError(
            f"{len(missing)} working day(s) have no EUR/GBP rate: {shown}{more}. "
            "The ECB does not republish, so these are permanent unless sourced "
            "elsewhere. Check the worker was running on those days."
        )
    return 0
