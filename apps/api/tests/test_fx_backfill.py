"""The history parser, checked against the ECB's real file.

A rate was actually lost on 2026-09-07: the laptop running the worker suspended
at 21:53:05 IST and resumed at 22:37:25, so it was asleep at 22:00 IST, which is
the 16:30 UTC schedule. The daily feed carries one day and had moved on. These
tests cover the path that gets that day back.

The fixture is the ECB's own ninety day file, trimmed to six days. Hand-writing
one would test my idea of the format rather than the format.
"""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

import pytest

from vega_api.modules.fx.contract import FeedRejectedError
from vega_api.modules.fx.service import (
    HISTORY_WINDOW,
    MAX_FEED_BYTES,
    parse_ecb_daily,
    parse_ecb_history,
)

FIXTURE = Path(__file__).parent / "fixtures" / "ecb-hist-90d-trimmed.xml"
REAL_FEED = FIXTURE.read_bytes()

# The newest day in the fixture, which is the day that was lost.
LOST_DAY = date(2026, 9, 7)


def test_the_real_feed_yields_every_working_day_it_carries() -> None:
    rates = parse_ecb_history(REAL_FEED, today=LOST_DAY)

    days = {rate.rate_date for rate in rates}
    assert days == {
        date(2026, 9, 7),
        date(2026, 9, 4),
        date(2026, 9, 3),
        date(2026, 9, 2),
        date(2026, 9, 1),
        date(2026, 8, 31),
    }
    assert all(rate.quote_currency == "GBP" for rate in rates)
    assert all(rate.base_currency == "EUR" for rate in rates)


def test_the_day_that_was_actually_lost_is_recovered() -> None:
    """The whole point. This rate existed and was unreachable via the daily feed."""
    rates = parse_ecb_history(REAL_FEED, today=LOST_DAY)

    lost = [rate for rate in rates if rate.rate_date == LOST_DAY]
    assert len(lost) == 1
    assert lost[0].rate == Decimal("0.85894")


def test_the_daily_parser_refuses_this_same_feed() -> None:
    """Which is why a second parser exists rather than a wider constant.

    parse_ecb_daily treats an old date as evidence the feed is stale, correctly,
    because in a one-day file it is. Loosening that to accept history would have
    turned off staleness detection on the live path to fix the backfill path.
    """
    with pytest.raises(FeedRejectedError, match=r"stale|days old"):
        parse_ecb_daily(REAL_FEED, today=LOST_DAY)


def test_days_outside_the_window_are_skipped_not_refused() -> None:
    """How much history the ECB publishes is not our business to object to."""
    rates = parse_ecb_history(REAL_FEED, today=LOST_DAY, window=timedelta(days=4))

    # Four days back from the 7th reaches the 3rd, inclusive. The 2nd, 1st and
    # 31st are outside it and are dropped without complaint.
    assert {rate.rate_date for rate in rates} == {
        date(2026, 9, 7),
        date(2026, 9, 4),
        date(2026, 9, 3),
    }


def test_a_stale_history_feed_is_still_refused() -> None:
    """Skipping old days must not disable staleness detection entirely.

    If the newest day in the file is ancient, the feed is broken and writing
    from it would report a successful backfill that recovered nothing current.
    """
    much_later = LOST_DAY + timedelta(days=30)
    with pytest.raises(FeedRejectedError, match="newest rates are from"):
        parse_ecb_history(REAL_FEED, today=much_later)


def test_a_future_dated_feed_is_refused() -> None:
    earlier = date(2026, 9, 1)
    with pytest.raises(FeedRejectedError, match="in the future"):
        parse_ecb_history(REAL_FEED, today=earlier)


def test_an_empty_feed_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="empty"):
        parse_ecb_history(b"", today=LOST_DAY)


def test_an_oversized_feed_is_refused_before_parsing() -> None:
    """SECURITY.md N4. The history feed gets the same cap as the daily one."""
    with pytest.raises(FeedRejectedError, match="over the"):
        parse_ecb_history(b"<x/>" + b" " * MAX_FEED_BYTES, today=LOST_DAY)


def test_entity_expansion_is_refused_on_this_path_too() -> None:
    """A backfill parser with weaker XML settings would be a second front door."""
    bomb = b"""<?xml version="1.0"?>
    <!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;">]>
    <Envelope><Cube time="2026-09-07">&lol2;</Cube></Envelope>"""
    with pytest.raises(FeedRejectedError):
        parse_ecb_history(bomb, today=LOST_DAY)


def test_a_feed_with_no_wanted_currency_is_refused_not_silently_empty() -> None:
    """SECURITY.md N6. A backfill that stored nothing must not look successful."""
    with pytest.raises(FeedRejectedError, match="carried none of"):
        parse_ecb_history(REAL_FEED, today=LOST_DAY, wanted=frozenset({"XYZ"}))


def test_the_window_default_is_the_ninety_days_the_ecb_publishes() -> None:
    assert timedelta(days=90) == HISTORY_WINDOW


def test_both_parsers_validate_a_rate_identically() -> None:
    """A backfill accepting what the live path refuses would write bad rates.

    Asserted by feeding the same broken cube to both and requiring both to
    refuse, rather than by reading the two functions and believing they match.
    """
    broken = b"""<?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01"
      xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
      <Cube><Cube time="2026-09-07"><Cube currency="GBP" rate="-1"/></Cube></Cube>
    </gesmes:Envelope>"""

    with pytest.raises(FeedRejectedError, match="zero or negative"):
        parse_ecb_daily(broken, today=LOST_DAY)
    with pytest.raises(FeedRejectedError, match="zero or negative"):
        parse_ecb_history(broken, today=LOST_DAY)
