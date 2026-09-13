"""The eighteen month wall.

HMRC's authorisation guide says a refresh token stops working after eighteen
months and the company must authorise again. It does not say eighteen months
from what, so this assumes the stricter reading: from the original grant, not
from the current token. Under the other reading these warnings arrive early and
nothing breaks; under this one, guessing the other way means a company finds
out at a quarter end that it cannot file. See #119.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from vega_api.modules.hmrc import service

CONNECTED = datetime(2026, 1, 31, 12, 0, tzinfo=UTC)


def test_eighteen_months_is_counted_in_calendar_months() -> None:
    """Not 548 days. Eighteen months from 31 January is 31 July, and a fixed
    day count lands somewhere else."""
    assert service.grant_expires_at(CONNECTED) == datetime(2027, 7, 31, 12, 0, tzinfo=UTC)


def test_a_short_month_clamps_to_its_last_day() -> None:
    """Eighteen months from 31 August is 28 February, not the 31st, which does
    not exist and would raise."""
    assert service.grant_expires_at(datetime(2025, 8, 31, 9, 0, tzinfo=UTC)) == datetime(
        2027, 2, 28, 9, 0, tzinfo=UTC
    )


def test_a_leap_day_is_handled() -> None:
    assert service.grant_expires_at(datetime(2024, 8, 31, 9, 0, tzinfo=UTC)) == datetime(
        2026, 2, 28, 9, 0, tzinfo=UTC
    )


def test_a_fresh_connection_needs_nothing() -> None:
    assert service.reauthorisation_due(CONNECTED, now=CONNECTED) is False
    assert service.grant_has_expired(CONNECTED, now=CONNECTED) is False


def test_the_warning_arrives_a_quarter_ahead() -> None:
    """A VAT quarter is three months. A shorter warning can fall entirely
    inside one period and be seen for the first time on filing day."""
    expiry = service.grant_expires_at(CONNECTED)

    assert service.reauthorisation_due(expiry - timedelta(days=91), now=CONNECTED) is False
    assert service.reauthorisation_due(CONNECTED, now=expiry - timedelta(days=89)) is True


def test_an_expired_grant_is_reported_as_expired_not_merely_due() -> None:
    """The two are different actions: one is 'reconnect soon', the other is
    'nothing will work until you reconnect'."""
    expiry = service.grant_expires_at(CONNECTED)

    assert service.grant_has_expired(CONNECTED, now=expiry + timedelta(seconds=1)) is True
    assert service.reauthorisation_due(CONNECTED, now=expiry + timedelta(seconds=1)) is True


@pytest.mark.parametrize(
    ("connected", "expected"),
    [
        (datetime(2026, 1, 1, tzinfo=UTC), datetime(2027, 7, 1, tzinfo=UTC)),
        (datetime(2026, 6, 30, tzinfo=UTC), datetime(2027, 12, 30, tzinfo=UTC)),
        (datetime(2026, 7, 1, tzinfo=UTC), datetime(2028, 1, 1, tzinfo=UTC)),
        (datetime(2026, 12, 31, tzinfo=UTC), datetime(2028, 6, 30, tzinfo=UTC)),
    ],
)
def test_the_month_arithmetic_crosses_years(connected: datetime, expected: datetime) -> None:
    """December is the case a modulo gets wrong, so it is pinned explicitly."""
    assert service.grant_expires_at(connected) == expected
