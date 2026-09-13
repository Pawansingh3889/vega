"""Parsing and validating the ECB daily feed. Pure: no network, no database.

SPEC.md section 1.1 sets the rules, and every one of them is about refusing to
write rather than about writing:

  * validate the payload before anything is written;
  * refuse a stale feed or a failed parse;
  * never overwrite today's rate with an empty result.

A zero or missing rate is the dangerous case, not an obvious one: it produces an
invoice that looks settled and a VAT box that balances to nothing.
"""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from xml.etree.ElementTree import Element

from defusedxml import ElementTree as DefusedET

from .contract import FeedRejectedError, SourcedRate

# N4: caps at the boundary. The ECB daily file is a few kilobytes; anything
# approaching this is not that file.
MAX_FEED_BYTES = 1_000_000

# How old a published day may be before the feed counts as stale. The ECB
# publishes on working days, so a Monday legitimately serves Friday's rates.
MAX_FEED_AGE = timedelta(days=4)

# The ECB's ninety day file. Ninety is what they publish, and asking for the
# full window rather than a few days is deliberate: the point of the backfill is
# that nobody has to know how long the gap was before running it.
HISTORY_WINDOW = timedelta(days=90)

_CUBE = "{http://www.ecb.int/vocabulary/2002-08-01/eurofxref}Cube"


def _parse_feed(payload: bytes) -> Element:
    """Size-cap and safely parse an ECB feed, or refuse it.

    Shared so the history feed gets the same hostile-input treatment as the
    daily one (SECURITY.md N4). A backfill path that parsed XML with different
    settings would be a second front door with a weaker lock.
    """
    if not payload:
        raise FeedRejectedError("The FX feed was empty. Yesterday's rate stands.")
    if len(payload) > MAX_FEED_BYTES:
        raise FeedRejectedError(
            f"The FX feed is {len(payload)} bytes, over the {MAX_FEED_BYTES} limit. "
            "Refusing to parse it."
        )
    try:
        # defusedxml refuses entity expansion and external entity resolution,
        # so a hostile feed cannot turn a rate fetch into a file read.
        root = DefusedET.fromstring(payload)
    except Exception as exc:
        raise FeedRejectedError(f"The FX feed did not parse as XML: {exc}") from exc

    # defusedxml ships no type information, so this is Any without the check.
    # Narrowed rather than cast or ignored: if the library ever returns
    # something else this stops here instead of failing later inside .iter().
    assert isinstance(root, Element)
    return root


def parse_ecb_daily(
    payload: bytes,
    *,
    wanted: frozenset[str] = frozenset({"GBP"}),
    today: date,
) -> list[SourcedRate]:
    """Turn the ECB daily XML into rates, or refuse and say why.

    The ECB quotes everything against the euro, which is the direction Vega
    needs: an invoice raised in EUR is converted into sterling for the books.
    """
    root = _parse_feed(payload)

    rates: list[SourcedRate] = []
    for day_cube in root.iter(_CUBE):
        published = day_cube.get("time")
        if not published:
            continue
        try:
            rate_date = date.fromisoformat(published)
        except ValueError as exc:
            raise FeedRejectedError(f"The feed carries an unreadable date '{published}'.") from exc

        if rate_date > today:
            raise FeedRejectedError(
                f"The feed is dated {rate_date}, which is in the future. Refusing it."
            )
        if today - rate_date > MAX_FEED_AGE:
            raise FeedRejectedError(
                f"The feed's newest rates are from {rate_date}, more than "
                f"{MAX_FEED_AGE.days} days old. Treating it as stale."
            )

        rates.extend(_rates_in_cube(day_cube, wanted=wanted, rate_date=rate_date))

    if not rates:
        raise FeedRejectedError(
            f"The feed parsed but carried none of {sorted(wanted)}. "
            "Refusing to write an empty result over a good rate."
        )
    return rates


def _rates_in_cube(
    day_cube: Element, *, wanted: frozenset[str], rate_date: date
) -> list[SourcedRate]:
    """The currencies inside one day's Cube, validated.

    Shared by the daily and the history parsers so that a rate accepted from one
    feed is accepted from the other on identical terms. A backfill that applied
    looser validation than the live path would quietly write rates the live path
    would have refused, which is worse than the gap it filled.
    """
    found: list[SourcedRate] = []
    for entry in day_cube:
        currency = entry.get("currency")
        raw = entry.get("rate")
        if currency is None or currency not in wanted:
            continue
        if raw is None:
            raise FeedRejectedError(f"The feed lists {currency} with no rate at all.")
        try:
            value = Decimal(raw)
        except InvalidOperation as exc:
            raise FeedRejectedError(f"'{raw}' is not a usable rate for {currency}.") from exc
        if value <= 0:
            raise FeedRejectedError(
                f"The feed gives {currency} a rate of {value}. A zero or negative "
                "rate would make an invoice look settled and a VAT box balance "
                "to nothing, so it is refused."
            )
        found.append(
            SourcedRate(
                base_currency="EUR",
                quote_currency=currency,
                rate=value,
                rate_date=rate_date,
            )
        )
    return found


def parse_ecb_history(
    payload: bytes,
    *,
    wanted: frozenset[str] = frozenset({"GBP"}),
    today: date,
    window: timedelta = HISTORY_WINDOW,
) -> list[SourcedRate]:
    """Turn the ECB's ninety day history XML into rates.

    This exists because a rate missed on the day is NOT gone. The daily feed
    carries one day and was the only thing read, so a machine asleep at 16:30
    UTC lost that day permanently. The ECB also publishes the last ninety days,
    which means the same gap is recoverable and the loss was a design choice
    rather than a fact about the ECB.

    The difference from `parse_ecb_daily` is one guard, and only one. The daily
    parser refuses ANY date older than MAX_FEED_AGE, because in a one-day feed
    an old date means the feed is stale. In a history feed old dates are the
    entire point, so staleness is judged on the NEWEST date instead, and dates
    outside the window are skipped rather than refused. Everything else, the
    size cap, the defused parser, the per-rate validation, is the same code.
    """
    root = _parse_feed(payload)

    rates: list[SourcedRate] = []
    newest: date | None = None
    oldest_allowed = today - window

    for day_cube in root.iter(_CUBE):
        published = day_cube.get("time")
        if not published:
            continue
        try:
            rate_date = date.fromisoformat(published)
        except ValueError as exc:
            raise FeedRejectedError(f"The feed carries an unreadable date '{published}'.") from exc

        if rate_date > today:
            raise FeedRejectedError(
                f"The feed is dated {rate_date}, which is in the future. Refusing it."
            )
        if newest is None or rate_date > newest:
            newest = rate_date
        # Older than we asked for is not a fault in the feed, so it is skipped
        # rather than raised. The ECB decides how much history to publish.
        if rate_date < oldest_allowed:
            continue

        rates.extend(_rates_in_cube(day_cube, wanted=wanted, rate_date=rate_date))

    if newest is not None and today - newest > MAX_FEED_AGE:
        raise FeedRejectedError(
            f"The history feed's newest rates are from {newest}, more than "
            f"{MAX_FEED_AGE.days} days old. Treating it as stale."
        )

    if not rates:
        raise FeedRejectedError(
            f"The history feed parsed but carried none of {sorted(wanted)} "
            f"within the last {window.days} days."
        )
    return rates
