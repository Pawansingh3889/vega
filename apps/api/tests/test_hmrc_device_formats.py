"""The browser-collected headers have to be the right shape, not just present.

Every wrong value in here is one a real collector produces by reaching for the
obvious browser API, not an invented string. That is the point: the previous
check passed all of them.
"""

from __future__ import annotations

import dataclasses

import pytest

from vega_api.modules.hmrc.contract import DeviceContext, VendorContext
from vega_api.modules.hmrc.service import fraud_headers

GOOD = DeviceContext(
    device_id="beec798b-b366-47fa-b1f8-92cede14a1ce",
    browser_js_user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    screens="width=1920&height=1080&scaling-factor=1&colour-depth=24",
    window_size="width=1256&height=803",
    timezone="UTC+01:00",
    user_ids="vega=alice123",
    multi_factor="",
)

VENDOR = VendorContext(
    client_public_ip="203.0.113.7",
    client_public_port="57181",
    client_public_ip_timestamp="2026-09-07T14:45:00Z",
    product_name="Vega",
    version="vega=0.1.0",
    license_ids="",
    public_ip="198.51.100.4",
    forwarded="by=198.51.100.4&for=203.0.113.7",
)


def test_the_good_context_is_accepted() -> None:
    headers = fraud_headers(GOOD, VENDOR)
    assert headers["Gov-Client-Timezone"] == "UTC+01:00"


@pytest.mark.parametrize(
    ("field", "value", "why"),
    [
        # Intl.DateTimeFormat().resolvedOptions().timeZone returns this. It is
        # the single likeliest wrong value in the whole set.
        ("timezone", "Europe/London", "an IANA zone name, not a UTC offset"),
        # getTimezoneOffset() gives minutes; formatting it by hand loses the colon.
        ("timezone", "UTC+0100", "no colon"),
        ("timezone", "+01:00", "no UTC prefix"),
        # A hand-rolled screen string.
        ("screens", "1920x1080", "not key-value at all"),
        ("screens", "width=1920&height=1080", "missing scaling-factor and colour-depth"),
        ("window_size", "1256x803", "not key-value at all"),
        ("window_size", "width=1256&height=803&scaling-factor=1", "extra field"),
        # crypto.randomUUID() gives a UUID; Date.now() and Math.random() do not.
        ("device_id", "1757254800000", "a timestamp, not a UUID"),
        ("device_id", "vega-device-1", "a made-up identifier"),
        ("user_ids", "alice123", "a bare value with no key"),
        ("multi_factor", "TOTP", "a bare type with no timestamp or reference"),
    ],
)
def test_a_wrongly_shaped_value_is_refused(field: str, value: str, why: str) -> None:
    device = dataclasses.replace(GOOD, **{field: value})
    with pytest.raises(ValueError) as raised:
        fraud_headers(device, VENDOR)
    message = str(raised.value)
    assert "format HMRC requires" in message, why
    # The message has to name the value, or the person reading the log cannot
    # tell which of the seven headers to go and fix.
    assert value in message


def test_the_second_screen_is_checked_too() -> None:
    """A comma separated list is only as good as its worst entry."""
    device = dataclasses.replace(
        GOOD,
        screens=(
            "width=1920&height=1080&scaling-factor=1&colour-depth=24,"
            "width=3000&height=2000&scaling-factor=oops&colour-depth=16"
        ),
    )
    with pytest.raises(ValueError, match="format HMRC requires"):
        fraud_headers(device, VENDOR)


def test_a_decimal_scaling_factor_and_a_second_screen_are_fine() -> None:
    """HMRC's own example has both, so rejecting them would be our bug."""
    device = dataclasses.replace(
        GOOD,
        screens=(
            "width=1920&height=1080&scaling-factor=1&colour-depth=16,"
            "width=3000&height=2000&scaling-factor=1.25&colour-depth=16"
        ),
    )
    assert fraud_headers(device, VENDOR)["Gov-Client-Screens"] == device.screens


def test_a_quarter_hour_offset_is_fine() -> None:
    """HMRC's own example is UTC-01:15. Assuming :00 would refuse it."""
    device = dataclasses.replace(GOOD, timezone="UTC-01:15")
    assert fraud_headers(device, VENDOR)["Gov-Client-Timezone"] == "UTC-01:15"


def test_no_multi_factor_is_still_allowed() -> None:
    """An empty list of MFA statuses is a truthful answer, not a malformed one."""
    assert fraud_headers(GOOD, VENDOR)["Gov-Client-Multi-Factor"] == ""


def test_a_real_multi_factor_entry_is_allowed() -> None:
    device = dataclasses.replace(
        GOOD,
        multi_factor="type=AUTH_CODE&timestamp=2026-09-07T13%3A23Z&unique-reference=fc4b5fd6",
    )
    assert "AUTH_CODE" in fraud_headers(device, VENDOR)["Gov-Client-Multi-Factor"]


def test_missing_still_reads_as_missing_not_as_malformed() -> None:
    """The two failures have to stay distinguishable in the message."""
    device = dataclasses.replace(GOOD, screens="")
    with pytest.raises(ValueError) as raised:
        fraud_headers(device, VENDOR)
    assert "not collected in the browser" in str(raised.value)
