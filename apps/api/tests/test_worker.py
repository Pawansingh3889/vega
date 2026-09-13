"""Procrastinate: does a job actually wake, and does it actually retry?

ROADMAP Phase 2's exit asks for a job that wakes on NOTIFY and retries. Both
halves matter and both are easy to believe without evidence:

  * A worker pointed at the transaction pooler still runs jobs, just on the poll
    interval. That looks like "slow", not "broken", and nobody diagnoses it for
    a week. So the wake has to be measured, not assumed.
  * A task decorated with retry=3 proves nothing until something fails.

These run against the same container the isolation suite uses, so the
procrastinate schema comes from migration 0016 rather than from Procrastinate's
CLI, which is what keeps the tables owned by the migration role (N2).
"""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncIterator

import asyncpg
import procrastinate
import pytest

from vega_api.common.db import with_schema

pytestmark = pytest.mark.asyncio

ATTEMPTS: list[int] = []


@pytest.fixture
async def worker_app(database_dsn: str) -> AsyncIterator[procrastinate.App]:
    app = procrastinate.App(
        connector=procrastinate.PsycopgConnector(conninfo=with_schema(database_dsn)),
    )
    async with app.open_async():
        yield app


async def test_the_schema_came_from_the_migration_not_the_cli(
    db: asyncpg.Connection,
) -> None:
    """N2: the worker must not own its own queue."""
    tables = await db.fetchval("SELECT count(*) FROM pg_tables WHERE schemaname = 'procrastinate'")
    assert tables == 4
    stray = await db.fetchval(
        "SELECT count(*) FROM pg_tables"
        " WHERE schemaname = 'public' AND tablename LIKE 'procrastinate%'"
    )
    assert stray == 0, "job tables leaked into public, where they would have no RLS"


async def test_a_job_wakes_promptly_and_retries_after_failing(
    worker_app: procrastinate.App,
) -> None:
    """One job, failing once on purpose, then succeeding.

    The elapsed time is the NOTIFY evidence. Procrastinate's default poll
    interval is seconds; a job picked up in well under that was woken, not
    polled.
    """
    ATTEMPTS.clear()

    @worker_app.task(name="test.flaky", retry=2, queue="test")
    async def flaky() -> str:
        ATTEMPTS.append(len(ATTEMPTS) + 1)
        if len(ATTEMPTS) == 1:
            raise RuntimeError("failing on purpose so the retry has something to do")
        return "ok"

    worker = asyncio.create_task(
        worker_app.run_worker_async(queues=["test"], wait=True, install_signal_handlers=False)
    )
    await asyncio.sleep(0.5)  # let the worker reach its LISTEN

    loop = asyncio.get_running_loop()
    start = loop.time()
    await flaky.defer_async()

    for _ in range(200):
        if len(ATTEMPTS) >= 2:
            break
        await asyncio.sleep(0.05)
    elapsed = loop.time() - start

    worker.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await worker

    assert len(ATTEMPTS) >= 2, (
        f"the job ran {len(ATTEMPTS)} time(s); a retry never happened, so retry=2 is decorative"
    )
    assert elapsed < 5.0, (
        f"first attempt took {elapsed:.1f}s. That is poll-interval latency, not a NOTIFY wake: "
        "check the worker is on the session pooler (5432), not the transaction pooler (6543)."
    )
