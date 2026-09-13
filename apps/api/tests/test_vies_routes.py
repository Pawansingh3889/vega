"""The VIES module is reachable over HTTP, and stays that way.

The module was complete and correct for two days while nothing could call it.
`check-reachable.py` now fails that, which is the real guard, but it only knows
that *something* imports the module. These tests pin the two paths and the fact
that both refuse an unauthenticated caller, so the routes cannot quietly become
an import that satisfies the checker while serving nobody.
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from vega_api.app import create_app, get_verifier
from vega_api.auth import TokenVerifier
from vega_api.config import Settings

CUSTOMER = "/api/v1/customers/3f2504e0-4f89-11d3-9a0c-0305e82c3301/vat-check"
SUPPLIER = "/api/v1/suppliers/3f2504e0-4f89-11d3-9a0c-0305e82c3301/vat-check"


@pytest.fixture
def app() -> FastAPI:
    """Built from settings supplied here, so no environment is needed.

    Before #83 this file set two environment variables before importing the
    app, because `app.py` called `get_settings()` at module scope. The factory
    is why that preamble is gone.
    """
    return create_app(
        Settings(
            VITE_SUPABASE_URL="https://stub.supabase.co",
            VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
        )
    )


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    """No lifespan is run, so `app.state` stays empty on purpose.

    `get_verifier` reads `app.state`, which no route reaches before refusing an
    unauthenticated caller, so the override keeps the 401 path reachable while
    still proving no collaborator got used.
    """
    app.dependency_overrides[get_verifier] = lambda: _StubVerifier()
    yield TestClient(app)
    app.dependency_overrides.clear()


class _StubVerifier(TokenVerifier):
    """Never called: these tests only ever refuse before verification."""

    def __init__(self) -> None:
        super().__init__(
            Settings(
                VITE_SUPABASE_URL="https://stub.supabase.co",
                VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
            )
        )


def test_both_vat_check_routes_are_registered(app: FastAPI) -> None:
    """Registered at the paths the frontend will call, with POST."""
    # Starlette types app.routes as BaseRoute, which declares neither `path`
    # nor `methods`; only the APIRoute subclass has them. Narrowing is the
    # house rule over casting.
    routes: set[tuple[str, tuple[str, ...]]] = set()
    for route in app.routes:
        if isinstance(route, APIRoute) and route.methods is not None:
            routes.add((route.path, tuple(sorted(route.methods))))

    assert ("/api/v1/customers/{customer_id}/vat-check", ("POST",)) in routes
    assert ("/api/v1/suppliers/{supplier_id}/vat-check", ("POST",)) in routes


@pytest.mark.parametrize("path", [CUSTOMER, SUPPLIER])
def test_a_vat_check_refuses_an_unauthenticated_caller(client: TestClient, path: str) -> None:
    """No token, no call to VIES and no database touched.

    This is the assertion that makes the test above worth having: a route
    registered but unauthenticated would satisfy the path check while letting
    anybody spend the company's VIES quota and read back who its customers are.
    """
    response = client.post(path)

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


@pytest.mark.parametrize("path", [CUSTOMER, SUPPLIER])
def test_a_bearer_token_is_required_not_just_any_header(client: TestClient, path: str) -> None:
    """`Authorization: something-else` is not a session."""
    response = client.post(path, headers={"Authorization": "Basic abc123"})

    assert response.status_code == 401
