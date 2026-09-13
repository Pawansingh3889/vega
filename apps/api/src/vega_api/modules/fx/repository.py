"""All the FX module's I/O."""

from __future__ import annotations

from datetime import date

import asyncpg

from .contract import SourcedRate


async def store_rates(conn: asyncpg.Connection, rates: list[SourcedRate]) -> int:
    """Write rates, never overwriting a good one with a worse one.

    ON CONFLICT DO NOTHING rather than DO UPDATE, deliberately. A rate for a
    given day and source does not change; a second write for the same key means
    the feed was re-read, not that the number moved. Leaving the first one
    standing is what SPEC 1.1 asks for.
    """
    if not rates:
        # Unreachable via the task, which raises before this. Belt and braces:
        # an empty write is the exact failure the spec names.
        raise ValueError("refusing to write an empty set of rates")

    # Count what was actually INSERTED, not what was offered.
    #
    # ON CONFLICT DO NOTHING means a re-read of the same day writes nothing, and
    # returning len(rates) reported "accepted 1 rate" either way. That is the
    # kind of message that makes somebody believe they captured a day they did
    # not, which for FX is unrecoverable: the ECB does not republish.
    stored = 0
    for r in rates:
        row = await conn.fetchval(
            """
            INSERT INTO public.fx_rates
                (base_currency, quote_currency, rate, rate_date, source)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (base_currency, quote_currency, rate_date, source) DO NOTHING
            RETURNING id
            """,
            r.base_currency,
            r.quote_currency,
            r.rate,
            r.rate_date,
            r.source,
        )
        if row is not None:
            stored += 1
    return stored


async def latest_rate_date(conn: asyncpg.Connection, base: str, quote: str) -> object:
    """The most recent day we hold, so a caller can see what standing means."""
    return await conn.fetchval(
        """SELECT max(rate_date) FROM public.fx_rates
            WHERE base_currency = $1 AND quote_currency = $2""",
        base,
        quote,
    )


async def missing_working_days(
    conn: asyncpg.Connection, base: str = "EUR", quote: str = "GBP"
) -> list[date]:
    """Working days since the first held rate that have no rate.

    Weekends are excluded because the ECB does not publish on them, so counting
    all days would report a gap every Saturday and train whoever reads it to
    ignore the alarm.

    Today is excluded too: the feed publishes mid-afternoon CET, so a morning
    check would otherwise report a gap that is merely early.
    """
    rows = await conn.fetch(
        """
        WITH held AS (
          SELECT rate_date FROM public.fx_rates
           WHERE base_currency = $1 AND quote_currency = $2
        )
        SELECT d::date AS day
          FROM generate_series(
                 (SELECT min(rate_date) FROM held),
                 current_date - 1,
                 interval '1 day') d
         WHERE extract(isodow FROM d) < 6
           AND NOT EXISTS (SELECT 1 FROM held h WHERE h.rate_date = d::date)
         ORDER BY 1
        """,
        base,
        quote,
    )
    return [r["day"] for r in rows]
