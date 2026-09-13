"""VAT: derive a return for a period.

Phase 4 adds HMRC submission. Phase 2 stops at derivation and an accountant-
ready figure, because filing requires HMRC recognition of the software, which is
an application and an approval cycle rather than a sprint.
"""

from __future__ import annotations

from datetime import date

import asyncpg

from ...common.errors import NoCompanySelectedError, Result
from . import repository, service

PERMISSIONS = {"vat.preview": "authenticated"}


async def preview_return(conn: asyncpg.Connection, period_start: date, period_end: date) -> Result:
    """Boxes 1 to 9 for a period, for whichever company the session is in."""
    if period_end < period_start:
        return Result.err(
            "invalid_period",
            f"The period ends ({period_end}) before it starts ({period_start}).",
        )

    company_id = await repository.current_company(conn)
    if company_id is None:
        raise NoCompanySelectedError(
            "No company is selected for this session. Choose one and send its id "
            "in the X-Vega-Company header."
        )

    treatments = await repository.load_treatments(conn)
    lines = await repository.load_period_lines(conn, period_start, period_end)

    try:
        vat_return = service.derive_return(
            company_id=company_id,
            period_start=period_start,
            period_end=period_end,
            lines=lines,
            treatments=treatments,
        )
    except ValueError as exc:
        return Result.err("unknown_treatment", str(exc))

    return Result.good(vat_return)
