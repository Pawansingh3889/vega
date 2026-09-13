"""The postcode endpoint answers, refuses a stranger, and names a missing key.

`check-reachable.py` proves something imports the module. It does not prove a
deployment without a key answers with something an operator can act on, nor
that a configured one actually returns addresses, so these do.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from vega_api.app import create_app, current_caller, get_database, get_verifier
from vega_api.auth import Caller
from vega_api.common.errors import Result
from vega_api.config import Settings
from vega_api.modules.postcode.contract import Address, PostcodeLookupResult

PATH = "/api/v1/postcode/lookup"


@pytest.fixture
def app() -> FastAPI:
    settings = Settings(
        VITE_SUPABASE_URL="https://stub.supabase.co",
        VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
        GETADDRESS_API_KEY="stub-key",
    )
    application = create_app(settings)
    # `lifespan` does this in production; the test client never runs it.
    application.state.settings = settings
    return application


@pytest.fixture
def unconfigured_app() -> FastAPI:
    """A deployment that chose not to use postcode lookup. Normal case."""
    settings = Settings(
        VITE_SUPABASE_URL="https://stub.supabase.co",
        VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
    )
    application = create_app(settings)
    application.state.settings = settings
    return application


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def unconfigured_client(unconfigured_app: FastAPI) -> Iterator[TestClient]:
    yield TestClient(unconfigured_app)
    unconfigured_app.dependency_overrides.clear()


class _Database:
    """Yields a sentinel connection. No test here needs a real one."""

    @asynccontextmanager
    async def acting_as(self, caller: Caller) -> AsyncIterator[object]:
        self.asked_by = caller
        yield object()


def _authenticate(app: FastAPI) -> _Database:
    app.dependency_overrides[current_caller] = lambda: Caller(
        user_id=uuid4(), email="someone@example.com", requested_company=uuid4()
    )
    database = _Database()
    app.dependency_overrides[get_database] = lambda: database
    return database


def test_the_route_is_registered_as_a_get(app: FastAPI) -> None:
    paths = {
        route.path
        for route in app.routes
        if isinstance(route, APIRoute) and route.methods == {"GET"}
    }
    assert "/api/v1/postcode/lookup" in paths


def test_a_configured_lookup_returns_addresses(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A real PostcodeLookupResult, not a dict standing in for one: a dict was
    # what this test used until it was found not to be what the route
    # actually receives, which is the reason it never caught the 500 fixed
    # alongside it. See test_a_real_dataclass_result_serialises_without_500ing.
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.app.lookup_postcode",
        _returning(Result.good(PostcodeLookupResult(postcode="SW1A2AA", addresses=[], count=0))),
    )

    response = client.get(PATH, params={"postcode": "SW1A 2AA"})

    assert response.status_code == 200
    assert response.json()["data"]["postcode"] == "SW1A2AA"


def test_a_real_dataclass_result_serialises_without_500ing(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The regression this file's own mock hid.

    `test_a_configured_lookup_returns_addresses` above passes a plain dict
    through `Result.good(...)`, which is not what `lookup_postcode` actually
    returns: the real function answers with a `PostcodeLookupResult`
    dataclass, holding `Address` dataclasses. `JSONResponse(content={"data":
    result.value})` handed one straight to `json.dumps`, which cannot
    serialise a dataclass at all, so every SUCCESSFUL lookup 500d and nothing
    in this file, mocking a dict throughout, could have said so.
    """
    _authenticate(app)
    address = Address(
        line_1="Flat 2",
        line_2="14 Mill Road",
        line_3=None,
        line_4=None,
        town_or_city="Hebden Bridge",
        county="West Yorkshire",
        postcode="HX76AB",
        formatted_address="Flat 2, 14 Mill Road, Hebden Bridge, HX7 6AB",
    )
    monkeypatch.setattr(
        "vega_api.app.lookup_postcode",
        _returning(
            Result.good(PostcodeLookupResult(postcode="HX76AB", addresses=[address], count=1))
        ),
    )

    response = client.get(PATH, params={"postcode": "HX7 6AB"})

    assert response.status_code == 200
    body = response.json()["data"]
    assert body["postcode"] == "HX76AB"
    assert body["count"] == 1
    assert (
        body["addresses"][0]["formatted_address"] == "Flat 2, 14 Mill Road, Hebden Bridge, HX7 6AB"
    )
    assert body["addresses"][0]["town_or_city"] == "Hebden Bridge"


def test_an_unconfigured_key_is_503_naming_the_variable(
    unconfigured_app: FastAPI,
    unconfigured_client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """503, not 422: the problem is deployment configuration, not the request.

    The message names GETADDRESS_API_KEY, because that is what the operator
    can act on. And the lookup is never attempted, so a missing key cannot
    read like "the service tried and found nothing".
    """

    def _refuse(postcode: str, api_key: str) -> Result:
        raise AssertionError("no lookup was attempted with no key")

    monkeypatch.setattr("vega_api.app.lookup_postcode", _refuse)
    _authenticate(unconfigured_app)

    response = unconfigured_client.get(PATH, params={"postcode": "SW1A 2AA"})

    assert response.status_code == 503
    body = response.json()["error"]
    assert body["code"] == "not_configured"
    assert "GETADDRESS_API_KEY" in body["message"]


def test_a_refusal_from_the_lookup_is_422(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.app.lookup_postcode",
        _returning(Result.err("not_found", "No addresses.")),
    )

    response = client.get(PATH, params={"postcode": "XX99 9XX"})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "not_found"


def test_an_unauthenticated_caller_gets_nothing(app: FastAPI, client: TestClient) -> None:
    """Without this the tests above would pass against an endpoint that hands
    any stranger the lookup."""
    app.dependency_overrides[get_verifier] = lambda: _NeverCalledVerifier()

    response = client.get(PATH, params={"postcode": "SW1A 2AA"})

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


class _NeverCalledVerifier:
    """Refuses if reached. No token was sent, so nothing should verify one."""

    def verify(self, token: str, company: str | None) -> Caller:
        raise AssertionError("the verifier was called for a request with no token")


def _returning(result: Result):  # type: ignore[no-untyped-def]
    async def _lookup(postcode: str, api_key: str) -> Result:
        return result

    return _lookup


@pytest.mark.parametrize(
    ("raw", "label"),
    [("", "empty string"), ("   ", "whitespace only")],
)
def test_a_blank_key_is_treated_as_unset(raw: str, label: str) -> None:
    """`.env.example` ships `GETADDRESS_API_KEY=` with no value.

    So the empty string is not an edge case, it is the likeliest way to arrive
    here: CONTRIBUTING tells people to copy that file. Left as `""` it is not
    `None`, so the 503 above never fires, the empty key reaches getAddress.io,
    and the rejection comes back as "Postcode lookup service is unavailable",
    blaming the provider for a deployment that was never configured. That is
    the confusion #92 was filed about, arriving by the other door.
    """
    settings = Settings(
        VITE_SUPABASE_URL="https://stub.supabase.co",
        VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
        GETADDRESS_API_KEY=raw,
    )

    assert settings.getaddress_api_key is None, f"{label} should read as unset"


def test_a_real_key_is_not_blanked() -> None:
    """The guard above must not eat a key that has one."""
    settings = Settings(
        VITE_SUPABASE_URL="https://stub.supabase.co",
        VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
        GETADDRESS_API_KEY="a-real-key",
    )

    assert settings.getaddress_api_key == "a-real-key"


# An end-to-end version of the two tests above, building the app with a blank
# key and asserting the route answers 503, cannot be written yet: `create_app`
# uses the settings it is handed only for CORS, and the routes read
# `app.state.settings`, which only `lifespan` populates. That is #102, not this
# issue. The existing 503 route test above covers the route half by overriding
# the dependency directly.
