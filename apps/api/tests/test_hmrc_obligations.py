"""Fraud prevention headers, and the first HMRC call that uses them.

HMRC requires the headers on every MTD call, not only a submission. Version
3.3, connection method WEB_APP_VIA_SERVER, sixteen headers. The list and the
sourcing of each were read from HMRC's own page on 7 September 2026, not
recalled: a wrong list is a conformance failure they measure, and persistently
bad data can mean fines and API blocking.

The seven browser-collected values are inputs here, and cannot be anything
else. That is the design, not a convenience.
"""

from __future__ import annotations

from datetime import date

import httpx
import pytest

from vega_api.modules.hmrc import repository, service
from vega_api.modules.hmrc.contract import DeviceContext, HmrcError, VendorContext

DEVICE = DeviceContext(
    # A real UUID, because HMRC specifies one and the service now refuses
    # anything else. The old "dc1f-4a2b" was a placeholder that passed only
    # because the check was for emptiness rather than for shape.
    device_id="beec798b-b366-47fa-b1f8-92cede14a1ce",
    browser_js_user_agent="Mozilla/5.0 (X11; Linux x86_64)",
    screens="width=1920&height=1080&scaling-factor=1&colour-depth=24",
    window_size="width=1280&height=800",
    timezone="UTC+01:00",
    user_ids="vega=11111111-0000-4000-8000-0000000000f1",
    multi_factor="",
)
VENDOR = VendorContext(
    product_name="Vega",
    version="vega=0.1.0",
    license_ids="",
    public_ip="203.0.113.10",
    forwarded="by=203.0.113.10&for=198.51.100.7",
    client_public_ip="198.51.100.7",
    client_public_port="55123",
    client_public_ip_timestamp="2026-09-07T12:00:00.000Z",
)

# Read from HMRC's page for this connection method, not from memory.
REQUIRED = {
    "Gov-Client-Connection-Method",
    "Gov-Client-Device-ID",
    "Gov-Client-Browser-JS-User-Agent",
    "Gov-Client-Screens",
    "Gov-Client-Window-Size",
    "Gov-Client-Timezone",
    "Gov-Client-User-IDs",
    "Gov-Client-Multi-Factor",
    "Gov-Client-Public-IP",
    "Gov-Client-Public-Port",
    "Gov-Client-Public-IP-Timestamp",
    "Gov-Vendor-Product-Name",
    "Gov-Vendor-Version",
    "Gov-Vendor-License-IDs",
    "Gov-Vendor-Public-IP",
    "Gov-Vendor-Forwarded",
}


def _client(handler: object) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))  # type: ignore[arg-type]


# --- the headers -------------------------------------------------------------


def test_all_sixteen_headers_are_present() -> None:
    """The set is asserted whole. A header quietly dropped in a refactor is a
    conformance failure nobody notices until HMRC says so."""
    assert set(service.fraud_headers(DEVICE, VENDOR)) == REQUIRED


def test_the_connection_method_is_the_one_we_actually_are() -> None:
    headers = service.fraud_headers(DEVICE, VENDOR)

    assert headers["Gov-Client-Connection-Method"] == "WEB_APP_VIA_SERVER"


def test_the_clients_public_ip_is_the_one_the_server_observed() -> None:
    """Not something the browser reports about itself. It cannot reliably know,
    and a value it supplied would be a value an attacker could choose."""
    headers = service.fraud_headers(DEVICE, VENDOR)

    assert headers["Gov-Client-Public-IP"] == "198.51.100.7"
    assert headers["Gov-Vendor-Public-IP"] == "203.0.113.10"


@pytest.mark.parametrize(
    "field",
    ["device_id", "browser_js_user_agent", "screens", "window_size", "timezone", "user_ids"],
)
def test_a_missing_browser_value_refuses_rather_than_sending_a_blank(field: str) -> None:
    """A header present but empty reports as collected data that was never
    collected, which is worse than an honest failure."""
    from dataclasses import replace

    with pytest.raises(ValueError) as caught:
        service.fraud_headers(replace(DEVICE, **{field: "  "}), VENDOR)

    assert "cannot be filled in server-side" in str(caught.value)


def test_an_empty_multi_factor_is_allowed() -> None:
    """A session that used no MFA has no MFA statuses. Refusing that would push
    somebody towards inventing one."""
    from dataclasses import replace

    headers = service.fraud_headers(replace(DEVICE, multi_factor=""), VENDOR)

    assert headers["Gov-Client-Multi-Factor"] == ""


# --- obligations -------------------------------------------------------------


@pytest.mark.asyncio
async def test_obligations_are_fetched_with_the_headers_attached() -> None:
    seen: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(request.headers)
        return httpx.Response(
            200,
            json={
                "obligations": [
                    {
                        "periodKey": "18A1",
                        "start": "2026-07-01",
                        "end": "2026-09-30",
                        "due": "2026-11-07",
                        "status": "O",
                    }
                ]
            },
        )

    async with _client(handler) as client:
        result = await repository.fetch_obligations(
            client,
            service.fraud_headers(DEVICE, VENDOR),
            environment="sandbox",
            access_token="at",
            vrn="123456789",
            from_date=date(2026, 4, 1),
            to_date=date(2026, 12, 31),
        )

    assert not isinstance(result, HmrcError)
    assert result[0].period_key == "18A1"
    assert result[0].received is None
    for header in REQUIRED:
        assert header.lower() in seen, f"{header} never reached HMRC"
    assert seen["authorization"] == "Bearer at"


@pytest.mark.asyncio
async def test_a_dead_token_is_told_apart_from_an_outage() -> None:
    """401 is recoverable by refreshing. Reporting it as unavailable sends
    somebody to wait for HMRC instead."""

    async with _client(lambda r: httpx.Response(401, json={})) as client:
        dead = await repository.fetch_obligations(
            client,
            service.fraud_headers(DEVICE, VENDOR),
            environment="sandbox",
            access_token="expired",
            vrn="1",
            from_date=date(2026, 1, 1),
            to_date=date(2026, 3, 31),
        )
    async with _client(lambda r: httpx.Response(503, text="down")) as client:
        outage = await repository.fetch_obligations(
            client,
            service.fraud_headers(DEVICE, VENDOR),
            environment="sandbox",
            access_token="at",
            vrn="1",
            from_date=date(2026, 1, 1),
            to_date=date(2026, 3, 31),
        )

    assert dead is HmrcError.REFRESH_REFUSED
    assert outage is HmrcError.UNAVAILABLE


def test_a_malformed_obligation_is_refused_not_skipped() -> None:
    """A silently dropped obligation is a VAT period nobody files, and the
    first anyone hears of it is a penalty."""
    result = service.parse_obligations(
        {
            "obligations": [
                {
                    "periodKey": "18A1",
                    "start": "2026-07-01",
                    "end": "2026-09-30",
                    "due": "2026-11-07",
                    "status": "O",
                },
                {"periodKey": "18A2", "start": "not-a-date"},
            ]
        }
    )

    assert result is HmrcError.UNAVAILABLE


def test_a_fulfilled_obligation_keeps_its_received_date() -> None:
    result = service.parse_obligations(
        {
            "obligations": [
                {
                    "periodKey": "18A1",
                    "start": "2026-01-01",
                    "end": "2026-03-31",
                    "due": "2026-05-07",
                    "status": "F",
                    "received": "2026-05-02",
                }
            ]
        }
    )

    assert not isinstance(result, HmrcError)
    assert result[0].received == date(2026, 5, 2)
    assert result[0].status == "F"
