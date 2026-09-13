"""FX: fetch, validate and store the ECB daily rates."""

from __future__ import annotations

from datetime import date

import asyncpg
import httpx

from .contract import FeedRejectedError, SourcedRate
from .repository import missing_working_days
from .service import parse_ecb_daily, parse_ecb_history

ECB_DAILY_URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"

# The same numbers, ninety days of them. This is the file that makes a missed
# day recoverable, and not reading it is why one was lost on 2026-09-07: the
# machine was asleep at 16:30 UTC, the daily feed had moved on by the time it
# woke, and nothing ever looked backwards.
ECB_HISTORY_URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml"

PERMISSIONS = {"fx.ingest": "service"}

__all__ = [
    "ECB_DAILY_URL",
    "ECB_HISTORY_URL",
    "FeedRejectedError",
    "SourcedRate",
    "backfill",
    "ingest",
    "missing_working_days",
    "parse_ecb_daily",
    "parse_ecb_history",
]


async def ingest(
    conn: asyncpg.Connection,
    *,
    today: date,
    url: str = ECB_DAILY_URL,
    timeout: float = 20.0,
) -> int:
    """Fetch, validate, store. Returns how many rates were newly STORED.

    Zero is a normal answer, not a failure: re-reading a day already held writes
    nothing. It is only a problem if the day was never captured, which is what
    `make fx-status` reports.

    Raises FeedRejectedError when the feed is unusable, which is the point: the
    job must fail loudly so Procrastinate retries and the failure is visible,
    rather than returning zero and letting a bad day look like a quiet one.
    See SECURITY.md N6.
    """
    from . import repository

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise FeedRejectedError(
                f"Could not fetch the ECB feed: {exc}. Yesterday's rate stands."
            ) from exc

    rates = parse_ecb_daily(response.content, today=today)
    return await repository.store_rates(conn, rates)


async def backfill(
    conn: asyncpg.Connection,
    *,
    today: date,
    url: str = ECB_HISTORY_URL,
    timeout: float = 30.0,
) -> int:
    """Fill any gap in the last ninety days. Returns how many rates were STORED.

    Zero is the normal answer and means there was no gap, because `store_rates`
    is ON CONFLICT DO NOTHING and counts inserts rather than offers.

    This exists because of a real loss, not a theoretical one. The daily job is
    scheduled for 16:30 UTC and the worker runs on a laptop. On 2026-09-07 that
    laptop suspended at 21:53:05 IST and woke at 22:37:25, so it was asleep at
    22:00 IST, which is 16:30 UTC. The day's rate was simply never fetched, and
    with only the one-day feed being read there was no way back to it.

    The ECB does not republish the daily file, which is where "a missed rate is
    gone" came from. It does publish ninety days of history, so the rate was
    recoverable the whole time. Running this makes the gap heal itself instead
    of needing somebody to notice it.

    Deliberately NOT a replacement for the daily job. The daily feed is the one
    that captures the day AS the day, which matters for an invoice raised that
    afternoon. This is the net underneath it.
    """
    from . import repository

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False) as client:
        try:
            response = await client.get(url)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise FeedRejectedError(
                f"Could not fetch the ECB history feed: {exc}. Existing rates stand."
            ) from exc

    rates = parse_ecb_history(response.content, today=today)
    return await repository.store_rates(conn, rates)
