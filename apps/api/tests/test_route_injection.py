"""Routes must use the collaborators they are handed, not ones they go and find.

`app.py` calls itself the composition root and says routes "translate HTTP into
a call and a Result back into HTTP". Two of them used to reach into
`app.state` for the verifier and the database instead, which is service
location wearing injection's clothes: it looks like wiring, but nothing can
substitute the wiring.

The cost was not theoretical. Before this file existed, no test in this suite
had ever called a route, because calling one meant building an app object and
populating its state the way production does.

Each test below fails if the override is ignored, which is the only property
that makes them worth keeping. See the pull request for the runs that prove it:
pointing either provider back at `app.state` turns both green tests red.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Iterator
from contextlib import asynccontextmanager
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from vega_api.app import create_app, current_caller, get_database, get_verifier
from vega_api.auth import Caller
from vega_api.common.errors import VegaError
from vega_api.config import Settings


class _InjectedCollaboratorError(VegaError):
    """A sentinel, not a real failure mode.

    418 because no endpoint in this service returns it, so a test asserting on
    it cannot be satisfied by some other code path arriving at the same status
    for an honest reason.
    """

    code = "injected_collaborator_was_used"
    status = 418


class _RecordingDatabase:
    """Stands in for `Database`, and refuses loudly the moment it is asked.

    It does not need to behave like a database. The question is only whether
    the route asked *this* object rather than one it found for itself, and
    raising answers that in one hop without a Postgres in the room.
    """

    def __init__(self) -> None:
        self.asked_by: Caller | None = None

    @asynccontextmanager
    async def acting_as(self, caller: Caller) -> AsyncIterator[None]:
        self.asked_by = caller
        raise _InjectedCollaboratorError(
            "The route used the injected database, which is what this test asserts."
        )
        yield  # pragma: no cover - unreachable, and required to make this a generator


class _RecordingVerifier:
    def __init__(self) -> None:
        self.tokens: list[str] = []

    def verify(self, token: str, company: str | None) -> Caller:
        self.tokens.append(token)
        raise _InjectedCollaboratorError(
            "The route used the injected verifier, which is what this test asserts."
        )


@pytest.fixture
def app() -> FastAPI:
    """A fresh app per test, built from settings this test supplies.

    `create_app` takes its settings rather than reading them, so this needs no
    environment. Fresh per test because `dependency_overrides` is state on the
    app object, and a shared one leaks overrides between tests.
    """
    return create_app(
        Settings(
            VITE_SUPABASE_URL="https://example.supabase.co",
            VEGA_DATABASE_URL="postgresql://nobody@localhost/nothing",
        )
    )


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    """A client over the app with no lifespan run, deliberately.

    `TestClient` only runs `lifespan` when used as a context manager. Not
    running it means `app.state` is empty, so a route that reaches into it
    raises `AttributeError` instead of quietly working. That is what makes
    these tests able to fail.
    """
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_the_route_uses_the_database_it_is_handed(app: FastAPI, client: TestClient) -> None:
    caller = Caller(user_id=uuid4(), email="someone@example.com", requested_company=uuid4())
    database = _RecordingDatabase()
    app.dependency_overrides[current_caller] = lambda: caller
    app.dependency_overrides[get_database] = lambda: database

    response = client.get(
        "/api/v1/vat/preview",
        params={"period_start": "2026-07-01", "period_end": "2026-09-30"},
    )

    assert response.status_code == 418
    assert response.json()["error"]["code"] == "injected_collaborator_was_used"
    # The identity reached the database too, not just the object.
    assert database.asked_by == caller


def test_the_verifier_is_handed_to_current_caller(app: FastAPI, client: TestClient) -> None:
    verifier = _RecordingVerifier()
    app.dependency_overrides[get_verifier] = lambda: verifier

    response = client.get(
        "/api/v1/vat/preview",
        params={"period_start": "2026-07-01", "period_end": "2026-09-30"},
        headers={"Authorization": "Bearer a-token-this-test-made-up"},
    )

    assert response.status_code == 418
    assert response.json()["error"]["code"] == "injected_collaborator_was_used"
    assert verifier.tokens == ["a-token-this-test-made-up"]


def test_an_unauthenticated_call_still_refuses_before_any_collaborator(
    app: FastAPI,
    client: TestClient,
) -> None:
    """The 401 path must not depend on the overrides above.

    Without this, both tests could pass against a route that authenticated
    nobody, which is the shape of failure this repository keeps finding.
    """
    app.dependency_overrides[get_verifier] = lambda: _RecordingVerifier()

    response = client.get(
        "/api/v1/vat/preview",
        params={"period_start": "2026-07-01", "period_end": "2026-09-30"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"
