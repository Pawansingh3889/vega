"""The HMRC status endpoint answers, scopes to a company, and leaks no tokens.

The module had no route at all until now: `check-reachable.py` could not say so
because `modules/hmrc` had no `__init__.py`, so nothing treated it as a module.
Seven hundred lines of tested OAuth logic that nothing called still passed every
gate. These tests exist so the first route is more than an import that silences
the reachability check.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from vega_api.app import create_app, current_caller, get_database
from vega_api.auth import Caller
from vega_api.config import Settings
from vega_api.modules.hmrc.contract import Connection

PATH = "/api/v1/hmrc/status"


@pytest.fixture
def app() -> FastAPI:
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


class _Database:
    @asynccontextmanager
    async def acting_as(self, caller: Caller) -> AsyncIterator[object]:
        self.asked_by = caller
        yield object()


def _authenticate(app: FastAPI, company: UUID | None = None) -> _Database:
    app.dependency_overrides[current_caller] = lambda: Caller(
        user_id=uuid4(),
        email="someone@example.com",
        requested_company=uuid4() if company is None else company,
    )
    database = _Database()
    app.dependency_overrides[get_database] = lambda: database
    return database


def _connected(connected_at: datetime, expires_at: datetime) -> Connection:
    return Connection(
        company_id=str(uuid4()),
        expires_at=expires_at,
        scope="read:vat write:vat",
        environment="sandbox",
        connected_at=connected_at,
        refreshed_at=None,
    )


class _Loader:
    """A stand-in for `load_connection` that remembers what it was asked for.

    A class rather than a closure with an attribute bolted on: the attribute
    is then a declared field mypy can see, and the two `type: ignore` comments
    the closure needed are not a genuine external-library gap.
    """

    def __init__(self, connection: Connection | None) -> None:
        self.connection = connection
        self.asked_for: UUID | None = None

    async def __call__(self, conn: object, company_id: UUID) -> Connection | None:
        self.asked_for = company_id
        return self.connection


def test_the_route_is_registered_as_a_get(app: FastAPI) -> None:
    paths = {
        route.path
        for route in app.routes
        if isinstance(route, APIRoute) and route.methods == {"GET"}
    }
    assert PATH in paths


def test_a_company_with_no_connection_says_so_plainly(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Not connected is a normal answer, not an error."""
    _authenticate(app)
    monkeypatch.setattr("vega_api.app.hmrc_repository.load_connection", _Loader(None))

    response = client.get(PATH)

    assert response.status_code == 200
    assert response.json()["data"] == {"connected": False}


def test_a_live_connection_reports_the_grant_wall(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    now = datetime.now(UTC)
    connection = _connected(
        connected_at=now - timedelta(days=30), expires_at=now + timedelta(hours=3)
    )
    _authenticate(app)
    monkeypatch.setattr("vega_api.app.hmrc_repository.load_connection", _Loader(connection))

    body = client.get(PATH).json()["data"]

    assert body["connected"] is True
    assert body["environment"] == "sandbox"
    # A month in, with eighteen to run: nothing due and nothing expired.
    assert body["reauthorisation_due"] is False
    assert body["grant_has_expired"] is False
    assert body["access_token_needs_refresh"] is False


def test_a_grant_inside_its_last_ninety_days_is_flagged_before_it_dies(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The whole point of the endpoint.

    Tokens keep refreshing right up until the grant dies, so nothing else in
    the system notices. A company that finds out at the filing deadline has
    missed it.
    """
    now = datetime.now(UTC)
    connection = _connected(
        connected_at=now - timedelta(days=17 * 30), expires_at=now + timedelta(hours=3)
    )
    _authenticate(app)
    monkeypatch.setattr("vega_api.app.hmrc_repository.load_connection", _Loader(connection))

    body = client.get(PATH).json()["data"]

    assert body["reauthorisation_due"] is True
    assert body["grant_has_expired"] is False


def test_an_expired_grant_reports_expired_not_merely_due(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    now = datetime.now(UTC)
    connection = _connected(
        connected_at=now - timedelta(days=19 * 31), expires_at=now + timedelta(hours=3)
    )
    _authenticate(app)
    monkeypatch.setattr("vega_api.app.hmrc_repository.load_connection", _Loader(connection))

    body = client.get(PATH).json()["data"]

    assert body["grant_has_expired"] is True


def test_a_stale_access_token_is_reported_as_needing_refresh(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    now = datetime.now(UTC)
    connection = _connected(
        connected_at=now - timedelta(days=30), expires_at=now + timedelta(minutes=1)
    )
    _authenticate(app)
    monkeypatch.setattr("vega_api.app.hmrc_repository.load_connection", _Loader(connection))

    assert client.get(PATH).json()["data"]["access_token_needs_refresh"] is True


def test_the_response_carries_exactly_these_keys_and_no_others(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """SECURITY.md N2, as an allowlist rather than a substring search.

    The first version of this test grepped the body for "access_token" and
    failed on `access_token_expires_at`, which is a key name and not a secret.
    Loosening the grep would have been the wrong repair: it would keep the
    false positive out and let a real token through under a key nobody thought
    to search for.

    An allowlist has neither problem. A field added to `Connection` and passed
    through here fails this test until somebody writes it down, which is the
    moment to notice it is a credential.
    """
    now = datetime.now(UTC)
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.app.hmrc_repository.load_connection",
        _Loader(_connected(now - timedelta(days=30), now + timedelta(hours=3))),
    )

    keys = set(client.get(PATH).json()["data"])

    assert keys == {
        "connected",
        "environment",
        "scope",
        "connected_at",
        "access_token_expires_at",
        "access_token_needs_refresh",
        "grant_expires_at",
        "reauthorisation_due",
        "grant_has_expired",
    }


def test_the_connection_contract_holds_no_secret_to_leak() -> None:
    """The route is safe because the type it returns cannot carry a token.

    Checked on the dataclass rather than on one response, so it holds for every
    route that ever returns a `Connection`, including ones not written yet.
    """
    import dataclasses

    names = {field.name for field in dataclasses.fields(Connection)}
    forbidden = {"access_token", "refresh_token", "token", "secret", "client_secret"}
    assert not (names & forbidden), (
        f"Connection gained a credential field: {sorted(names & forbidden)}. "
        "Tokens are fetched, decrypted and used inside one function. They do "
        "not travel in a dataclass that a route hands back or a log records."
    )


def test_the_connection_is_loaded_for_the_company_the_caller_asked_for(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Otherwise one company could read another's connection status."""
    company = uuid4()
    now = datetime.now(UTC)
    _authenticate(app, company)
    load = _Loader(_connected(now - timedelta(days=30), now + timedelta(hours=3)))
    monkeypatch.setattr("vega_api.app.hmrc_repository.load_connection", load)

    client.get(PATH)

    assert load.asked_for == company


def test_no_company_header_is_refused_rather_than_guessed(app: FastAPI, client: TestClient) -> None:
    _authenticate(app, company=None)
    app.dependency_overrides[current_caller] = lambda: Caller(
        user_id=uuid4(), email="someone@example.com", requested_company=None
    )

    response = client.get(PATH)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "company_required"
