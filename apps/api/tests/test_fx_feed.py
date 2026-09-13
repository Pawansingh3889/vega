"""Parsing the ECB feed. Pure, so no network and no database.

SPEC.md 1.1 is almost entirely about refusing to write, so most of these assert
a refusal. That is the point: a rate ingestion that fails open writes a zero,
and a zero rate produces an invoice that looks settled and a VAT box that
balances to nothing.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from vega_api.modules.fx.contract import FeedRejectedError
from vega_api.modules.fx.service import parse_ecb_daily

TODAY = date(2026, 9, 5)
NS = 'xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref"'


def feed(day: str = "2026-09-05", body: str = '<Cube currency="GBP" rate="0.8412"/>') -> bytes:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" {NS}>
  <Cube><Cube time="{day}">{body}</Cube></Cube>
</gesmes:Envelope>""".encode()


def test_a_good_feed_parses() -> None:
    rates = parse_ecb_daily(feed(), today=TODAY)
    assert len(rates) == 1
    assert rates[0].base_currency == "EUR"
    assert rates[0].quote_currency == "GBP"
    assert rates[0].rate == Decimal("0.8412")
    assert rates[0].rate_date == date(2026, 9, 5)


def test_the_rate_is_a_decimal_not_a_float() -> None:
    """A rate parsed as a float is a rounding bug that surfaces months later on
    a restated figure."""
    assert isinstance(parse_ecb_daily(feed(), today=TODAY)[0].rate, Decimal)


def test_an_empty_feed_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="empty"):
        parse_ecb_daily(b"", today=TODAY)


def test_an_oversized_feed_is_refused_before_parsing() -> None:
    """N4: cap at the boundary. A feed this size is not the ECB's few-kilobyte
    daily file, and the refusal happens before any parser sees it."""
    with pytest.raises(FeedRejectedError, match="over the"):
        parse_ecb_daily(b"x" * 2_000_000, today=TODAY)


def test_malformed_xml_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="did not parse"):
        parse_ecb_daily(b"<not-xml", today=TODAY)


def test_an_entity_expansion_bomb_is_refused() -> None:
    """N4 in anger. stdlib ElementTree would happily expand this; defusedxml
    refuses, so a rate fetch cannot become a denial of service."""
    bomb = b"""<?xml version="1.0"?>
<!DOCTYPE lolz [
 <!ENTITY lol "lol">
 <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
 <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
]>
<lolz>&lol3;</lolz>"""
    with pytest.raises(FeedRejectedError):
        parse_ecb_daily(bomb, today=TODAY)


def test_a_stale_feed_is_refused() -> None:
    """The ECB publishes on working days, so a few days old is normal and a
    fortnight old means something upstream has stopped."""
    with pytest.raises(FeedRejectedError, match="stale"):
        parse_ecb_daily(feed(day="2026-08-20"), today=TODAY)


def test_a_weekend_gap_is_still_accepted() -> None:
    """A Monday legitimately serves Friday's rates. Refusing that would fail the
    job every Monday, which is how a useful alarm gets switched off."""
    rates = parse_ecb_daily(feed(day="2026-09-02"), today=TODAY)
    assert rates[0].rate_date == date(2026, 9, 2)


def test_a_future_dated_feed_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="future"):
        parse_ecb_daily(feed(day="2026-12-01"), today=TODAY)


def test_a_zero_rate_is_refused() -> None:
    """The dangerous case, and the one SPEC 1.1 names: a zero rate makes an
    invoice look settled and a VAT box balance to nothing."""
    with pytest.raises(FeedRejectedError, match="zero or negative"):
        parse_ecb_daily(feed(body='<Cube currency="GBP" rate="0"/>'), today=TODAY)


def test_a_negative_rate_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="zero or negative"):
        parse_ecb_daily(feed(body='<Cube currency="GBP" rate="-1.5"/>'), today=TODAY)


def test_a_missing_rate_attribute_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="no rate at all"):
        parse_ecb_daily(feed(body='<Cube currency="GBP"/>'), today=TODAY)


def test_an_unparseable_rate_is_refused() -> None:
    with pytest.raises(FeedRejectedError, match="not a usable rate"):
        parse_ecb_daily(feed(body='<Cube currency="GBP" rate="about eighty pence"/>'), today=TODAY)


def test_a_feed_without_the_currency_we_need_is_refused() -> None:
    """Parsing successfully and finding nothing is the silent failure SPEC 1.1
    is written against: it would write an empty result over a good rate."""
    with pytest.raises(FeedRejectedError, match="carried none of"):
        parse_ecb_daily(feed(body='<Cube currency="USD" rate="1.09"/>'), today=TODAY)


def test_other_currencies_are_ignored_not_stored() -> None:
    rates = parse_ecb_daily(
        feed(body='<Cube currency="USD" rate="1.09"/><Cube currency="GBP" rate="0.84"/>'),
        today=TODAY,
    )
    assert [r.quote_currency for r in rates] == ["GBP"]
