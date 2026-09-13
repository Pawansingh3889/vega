"""A bug in our code must not arrive as "the provider is down".

`postcode/repository.py` used to end with a bare `except Exception`, added to
"treat an unexpected error as unavailable to be safe". It was the opposite of
safe: any defect inside the try became `unavailable`, the user was told
getAddress.io was having a bad afternoon, and nobody looked at the code.

Two repositories shipped queries naming columns that do not exist on the same
day (#99, #103). Both raised, both surfaced as a 500 naming the column, and
both were found in minutes. Behind a catch-all they would have been a shrug.

These tests pin the difference between the two outcomes, because that
difference is the whole point.
"""

from __future__ import annotations

import httpx
import pytest

from vega_api.modules.postcode import repository, service
from vega_api.modules.postcode.contract import PostcodeLookupError

POSTCODE = "SW1A 1AA"


class _BoomError(Exception):
    """Stands in for a defect of ours: a typo, a KeyError, a bad column."""


@pytest.mark.asyncio
async def test_a_bug_in_our_parsing_surfaces_rather_than_becoming_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The test the bare except would have failed.

    If this returns `unavailable` instead of raising, a defect in our own code
    is being reported to the user as a third party outage.
    """

    def _explode(*args: object, **kwargs: object) -> object:
        raise _BoomError("a defect inside the try block")

    monkeypatch.setattr(service, "parse_addresses", _explode)

    async def _ok(self: object, url: str) -> httpx.Response:
        return _ok_response()

    monkeypatch.setattr(httpx.AsyncClient, "get", _ok)

    with pytest.raises(_BoomError):
        await repository.lookup_postcode(POSTCODE, "a-key")


@pytest.mark.asyncio
async def test_a_provider_outage_is_still_reported_as_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Removing the catch-all must not make real outages raise instead."""

    async def _refuse(self: object, url: str) -> httpx.Response:
        raise httpx.ConnectError("no route to host")

    monkeypatch.setattr(httpx.AsyncClient, "get", _refuse)

    assert await repository.lookup_postcode(POSTCODE, "a-key") is (PostcodeLookupError.UNAVAILABLE)


@pytest.mark.asyncio
async def test_a_200_that_is_not_json_is_the_providers_fault_not_ours(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The one unexpected-looking case that genuinely belongs with the outages,
    which is why it keeps a handler and everything else does not."""

    async def _garbage(self: object, url: str) -> httpx.Response:
        return httpx.Response(
            200,
            text="<html>not json</html>",
            request=httpx.Request("GET", url),
        )

    monkeypatch.setattr(httpx.AsyncClient, "get", _garbage)

    assert await repository.lookup_postcode(POSTCODE, "a-key") is (PostcodeLookupError.UNAVAILABLE)


def _ok_response() -> httpx.Response:
    # `request=` is required: raise_for_status() refuses to run on a response
    # with no request attached, and that RuntimeError would be indistinguishable
    # from the defect this file is about.
    return httpx.Response(
        200,
        json={
            "address_count": 1,
            "addresses": [{"formatted_address": "1 Mill Lane, Hebden Bridge"}],
        },
        request=httpx.Request("GET", "https://api.getaddress.io/probe"),
    )
