"""Typed values for FX ingestion. No I/O."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal


@dataclass(frozen=True, slots=True)
class SourcedRate:
    """One rate, as published, with the day it belongs to.

    Decimal throughout. A rate parsed into a float is a rounding bug that only
    shows up on a restated figure months later.
    """

    base_currency: str
    quote_currency: str
    rate: Decimal
    rate_date: date
    source: str = "ECB"


class FeedRejectedError(Exception):
    """The feed was not usable, and the reason says which of SPEC 1.1's rules
    it broke.

    Deliberately an exception rather than an empty list. SPEC 1.1 requires that
    a failed update leaves yesterday's rate standing and raises; returning
    nothing would let the caller write nothing and call it a success.
    """
