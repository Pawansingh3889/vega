"""Pure rules for the HMRC OAuth dance. No I/O, no clock reads, no secrets.

Everything here is a function of its arguments, which is what lets the whole
authorisation flow be tested without an HMRC account. That matters more than
usual: HMRC credentials are a real-world application with lead time, and a flow
that can only be checked once you have them is a flow nobody checks.
"""

from __future__ import annotations

import re
import secrets
from datetime import date, datetime, timedelta
from urllib.parse import urlencode

from .contract import DeviceContext, HmrcError, Obligation, Tokens, VendorContext

# The two scopes MTD VAT needs. Asking for more than this is asking a customer
# to grant more than the product uses, which they can see on HMRC's own consent
# screen.
SCOPES = ("read:vat", "write:vat")

SANDBOX_BASE = "https://test-api.service.hmrc.gov.uk"
PRODUCTION_BASE = "https://api.service.hmrc.gov.uk"

# HMRC's access tokens last four hours. The expiry we store is computed from
# their `expires_in` rather than assumed, and this is only the fallback for a
# response that omits it.
_DEFAULT_TTL = timedelta(hours=4)

# Refresh a little before the token actually dies, so a submission started at
# 3:59:59 does not fail mid-flight.
REFRESH_MARGIN = timedelta(minutes=5)


def base_url(environment: str) -> str:
    """Sandbox and production are different hosts, not a flag on one host.

    Returning the wrong one files a real return against a test service, or
    worse, a test return against the real one.
    """
    if environment == "production":
        return PRODUCTION_BASE
    if environment == "sandbox":
        return SANDBOX_BASE
    raise ValueError(f"unknown HMRC environment: {environment!r}")


def new_state() -> str:
    """A fresh CSRF value for one authorisation attempt.

    `secrets`, not `random`. This is the only thing standing between a customer
    and an attacker completing an OAuth flow into the attacker's HMRC account.
    """
    return secrets.token_urlsafe(32)


def authorization_url(*, environment: str, client_id: str, redirect_uri: str, state: str) -> str:
    """Where to send the person so HMRC can ask them to authorise Vega."""
    query = urlencode(
        {
            "response_type": "code",
            "client_id": client_id,
            "scope": " ".join(SCOPES),
            "state": state,
            "redirect_uri": redirect_uri,
        }
    )
    return f"{base_url(environment)}/oauth/authorize?{query}"


def check_state(*, issued: str, returned: str) -> HmrcError | None:
    """Compare in constant time and refuse anything that does not match.

    `secrets.compare_digest` rather than `==` so the comparison does not leak
    the correct prefix through timing. Cheap here, and the habit is the point.
    """
    if not issued or not returned:
        return HmrcError.STATE_MISMATCH
    if not secrets.compare_digest(issued, returned):
        return HmrcError.STATE_MISMATCH
    return None


def parse_tokens(payload: object, *, now: datetime) -> Tokens | HmrcError:
    """Turn HMRC's token response into typed values, or refuse it.

    Missing fields are refused rather than defaulted. A connection recorded with
    an empty refresh token looks connected and is not, and the person finds out
    at the moment they try to file.
    """
    if not isinstance(payload, dict):
        return HmrcError.EXCHANGE_REFUSED

    access = payload.get("access_token")
    refresh = payload.get("refresh_token")
    if not isinstance(access, str) or not access:
        return HmrcError.EXCHANGE_REFUSED
    if not isinstance(refresh, str) or not refresh:
        return HmrcError.EXCHANGE_REFUSED

    expires_in = payload.get("expires_in")
    ttl = (
        timedelta(seconds=int(expires_in))
        if isinstance(expires_in, (int, str)) and str(expires_in).isdigit()
        else _DEFAULT_TTL
    )

    scope = payload.get("scope")
    return Tokens(
        access_token=access,
        refresh_token=refresh,
        expires_at=now + ttl,
        scope=scope if isinstance(scope, str) and scope else " ".join(SCOPES),
    )


def needs_refresh(expires_at: datetime, *, now: datetime) -> bool:
    """True while there is not enough life left to start a call safely."""
    return expires_at - REFRESH_MARGIN <= now


# --- fraud prevention headers ------------------------------------------------
#
# HMRC requires these on every MTD call, not only on a submission. Version 3.3,
# connection method WEB_APP_VIA_SERVER, sixteen headers. The list and the
# sourcing of each were read from
# developer.service.hmrc.gov.uk/guides/fraud-prevention/connection-method/web-app-via-server/
# on 7 September 2026 rather than recalled, because a wrong list here is a
# conformance failure that HMRC measures.

CONNECTION_METHOD = "WEB_APP_VIA_SERVER"


def fraud_headers(device: DeviceContext, vendor: VendorContext) -> dict[str, str]:
    """Assemble the sixteen headers HMRC requires for this connection method.

    Pure, so the whole set can be asserted without a network, and so the
    browser-collected half is visibly an input rather than something this
    function could invent.
    """
    missing = _missing_device_values(device)
    if missing:
        # Refusing beats sending a blank. HMRC's conformance checks measure the
        # quality of these values, and a header present but empty is worse than
        # an honest failure: it reports as collected data that was never
        # collected.
        raise ValueError(
            "these fraud prevention values were not collected in the browser: "
            + ", ".join(missing)
            + ". They cannot be filled in server-side."
        )

    malformed = _malformed_device_values(device)
    if malformed:
        # Same reasoning as the emptiness check one step up. A wrongly shaped
        # value is not a smaller problem than an absent one: HMRC accepts the
        # submission either way and marks the header down in a conformance
        # report nobody reads until the fines arrive. Refusing here is the only
        # point at which it is still cheap to fix.
        raise ValueError(
            "these fraud prevention values are not in the format HMRC requires: "
            + "; ".join(malformed)
        )

    return {
        "Gov-Client-Connection-Method": CONNECTION_METHOD,
        # From the originating device.
        "Gov-Client-Device-ID": device.device_id,
        "Gov-Client-Browser-JS-User-Agent": device.browser_js_user_agent,
        "Gov-Client-Screens": device.screens,
        "Gov-Client-Window-Size": device.window_size,
        "Gov-Client-Timezone": device.timezone,
        "Gov-Client-User-IDs": device.user_ids,
        "Gov-Client-Multi-Factor": device.multi_factor,
        # Observed by this server about the browser's connection to it.
        "Gov-Client-Public-IP": vendor.client_public_ip,
        "Gov-Client-Public-Port": vendor.client_public_port,
        "Gov-Client-Public-IP-Timestamp": vendor.client_public_ip_timestamp,
        # About us.
        "Gov-Vendor-Product-Name": vendor.product_name,
        "Gov-Vendor-Version": vendor.version,
        "Gov-Vendor-License-IDs": vendor.license_ids,
        "Gov-Vendor-Public-IP": vendor.public_ip,
        "Gov-Vendor-Forwarded": vendor.forwarded,
    }


def _missing_device_values(device: DeviceContext) -> list[str]:
    """Which browser-collected values are absent.

    `multi_factor` is excluded: an empty list of MFA statuses is a truthful
    answer for a session that used none, and refusing it would push somebody
    towards inventing one.
    """
    required = {
        "Gov-Client-Device-ID": device.device_id,
        "Gov-Client-Browser-JS-User-Agent": device.browser_js_user_agent,
        "Gov-Client-Screens": device.screens,
        "Gov-Client-Window-Size": device.window_size,
        "Gov-Client-Timezone": device.timezone,
        "Gov-Client-User-IDs": device.user_ids,
    }
    return [name for name, value in required.items() if not value.strip()]


def parse_obligations(payload: object) -> list[Obligation] | HmrcError:
    """Read HMRC's obligations response, or refuse it.

    Refuses a malformed entry rather than skipping it. A silently dropped
    obligation is a VAT period nobody files, and the first anyone hears of it
    is a penalty.
    """
    if not isinstance(payload, dict):
        return HmrcError.UNAVAILABLE
    raw = payload.get("obligations")
    if not isinstance(raw, list):
        return HmrcError.UNAVAILABLE

    out: list[Obligation] = []
    for entry in raw:
        if not isinstance(entry, dict):
            return HmrcError.UNAVAILABLE
        try:
            out.append(
                Obligation(
                    period_key=str(entry["periodKey"]),
                    start=date.fromisoformat(str(entry["start"])),
                    end=date.fromisoformat(str(entry["end"])),
                    due=date.fromisoformat(str(entry["due"])),
                    status=str(entry["status"]),
                    received=(
                        date.fromisoformat(str(entry["received"]))
                        if entry.get("received")
                        else None
                    ),
                )
            )
        except (KeyError, ValueError):
            return HmrcError.UNAVAILABLE
    return out


# --- the eighteen month wall -------------------------------------------------
#
# HMRC's authorisation guide, read 7 September 2026:
#
#   "An access token lasts 4 hours. When it expires, you can get a new one using
#    a single-use refresh token. After 18 months, refresh tokens stop working.
#    At this point, you must go through the authorisation process again."
#
# It does not say eighteen months from WHAT, and the two readings differ:
#
#   the grant   eighteen months from the original authorisation, so a
#               connection dies on a fixed date however much it is used
#   the token   eighteen months from the issue of the current refresh token,
#               which rotates on every use, so an active connection never dies
#
# This assumes the grant, which is the stricter of the two. Under the other
# reading the warning below simply arrives early and nothing breaks. Assuming
# the looser one and being wrong means a company discovers at a quarter end
# that it cannot file. See #119.

GRANT_LIFETIME_MONTHS = 18

# Warn a quarter ahead. A VAT quarter is three months, so anything shorter can
# fall entirely inside one period and be seen for the first time on the day
# somebody needs to file.
REAUTHORISATION_WARNING = timedelta(days=90)


def grant_expires_at(connected_at: datetime) -> datetime:
    """When the authorisation stops being refreshable.

    Calendar months rather than a fixed number of days: eighteen months from
    31 January is 31 July, and 548 days is not.
    """
    month = connected_at.month - 1 + GRANT_LIFETIME_MONTHS
    year = connected_at.year + month // 12
    month = month % 12 + 1
    day = min(connected_at.day, _days_in_month(year, month))
    return connected_at.replace(year=year, month=month, day=day)


def reauthorisation_due(connected_at: datetime, *, now: datetime) -> bool:
    """True once the connection is close enough to the wall to act on."""
    return grant_expires_at(connected_at) - REAUTHORISATION_WARNING <= now


def grant_has_expired(connected_at: datetime, *, now: datetime) -> bool:
    """True when no refresh can succeed and only a person can fix it."""
    return grant_expires_at(connected_at) <= now


def _days_in_month(year: int, month: int) -> int:
    if month == 12:
        return 31
    return (date(year, month + 1, 1) - date(year, month, 1)).days


# The shapes HMRC publishes for the browser-collected headers, from the
# WEB_APP_VIA_SERVER connection method guide. These are checked because
# emptiness was the only thing checked before, and the values most likely to
# arrive are wrong-but-present rather than absent: a collector that reaches for
# the obvious browser API gets `Europe/London` from
# Intl.DateTimeFormat().resolvedOptions().timeZone, and `1920x1080` from a
# hand-rolled screen string. Both are non-empty, so both used to pass, and both
# are exactly the "persistently bad data" HMRC's conformance checks penalise.
_UUID = re.compile(r"\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z", re.I)

# UTC±hh:mm. The minutes are not always zero: HMRC's own example is UTC-01:15.
_TIMEZONE = re.compile(r"\A UTC [+-] \d{2} : \d{2} \Z", re.X)

# One screen. The header carries a comma separated list of these, and the
# scaling factor is decimal (HMRC's example has 1.25).
_SCREEN = re.compile(
    r"\A width=\d+ & height=\d+ & scaling-factor=\d+(?:\.\d+)? & colour-depth=\d+ \Z", re.X
)

_WINDOW_SIZE = re.compile(r"\A width=\d+ & height=\d+ \Z", re.X)

# key=value pairs, comma separated. Percent-encoding is expected in the value,
# so this deliberately does not try to decode or bound it.
_USER_ID = re.compile(r"\A [^=,&]+ = [^,]* \Z", re.X)

# type, timestamp and unique-reference, in that order, per the guide. The
# timestamp is yyyy-MM-ddThh:mmZ with the colon percent-encoded.
_MULTI_FACTOR = re.compile(r"\A type=[^&,]+ & timestamp=[^&,]+ & unique-reference=[^&,]+ \Z", re.X)


def _malformed_device_values(device: DeviceContext) -> list[str]:
    """Which browser-collected values are present but the wrong shape.

    Separate from `_missing_device_values` because the two failures need
    different words: one says the browser never collected it, the other says
    the browser collected something HMRC will not accept. Telling somebody a
    value is "missing" when they can see it in the request is how an afternoon
    disappears.
    """
    problems: list[str] = []

    def check(name: str, value: str, pattern: re.Pattern[str], shape: str) -> None:
        if not pattern.match(value):
            problems.append(f"{name} is {value!r}, which is not {shape}")

    def check_list(name: str, value: str, pattern: re.Pattern[str], shape: str) -> None:
        # These headers carry a comma separated list, and one bad entry makes
        # the whole header bad, so every entry is checked rather than the first.
        for entry in value.split(","):
            check(name, entry, pattern, shape)

    check(
        "Gov-Client-Device-ID",
        device.device_id,
        _UUID,
        "a UUID (HMRC's example: beec798b-b366-47fa-b1f8-92cede14a1ce)",
    )
    check_list(
        "Gov-Client-Screens",
        device.screens,
        _SCREEN,
        "width=<n>&height=<n>&scaling-factor=<n>&colour-depth=<n>",
    )
    check("Gov-Client-Window-Size", device.window_size, _WINDOW_SIZE, "width=<n>&height=<n>")
    check("Gov-Client-Timezone", device.timezone, _TIMEZONE, "UTC+hh:mm or UTC-hh:mm")
    check_list("Gov-Client-User-IDs", device.user_ids, _USER_ID, "key=value pairs")

    # Empty is a truthful answer for a session that used no second factor, and
    # `_missing_device_values` already allows it. Only a non-empty value has a
    # shape to get wrong.
    if device.multi_factor.strip():
        check_list(
            "Gov-Client-Multi-Factor",
            device.multi_factor,
            _MULTI_FACTOR,
            "type=<t>&timestamp=<t>&unique-reference=<r>",
        )

    return problems
