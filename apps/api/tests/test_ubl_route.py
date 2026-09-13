"""The UBL endpoint is reachable, returns XML, and refuses a stranger.

`check-reachable.py` proves something imports the module. It does not prove a
document can be fetched, nor that fetching one needs a session, so these do.
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

INVOICE = uuid4()
PATH = f"/api/v1/invoices/{INVOICE}/ubl"
PDF_PATH = f"/api/v1/invoices/{INVOICE}/pdf"


@pytest.fixture
def app() -> FastAPI:
    return create_app(
        Settings(
            VITE_SUPABASE_URL="https://stub.supabase.co",
            VEGA_DATABASE_URL="postgresql://stub@localhost/stub",
            # Optional since #92. Nothing here cares about postcode lookup.
        )
    )


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    yield TestClient(app)
    app.dependency_overrides.clear()


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
    assert "/api/v1/invoices/{invoice_id}/ubl" in paths


def test_a_document_comes_back_as_xml_not_json(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The bytes are the product.

    A JSON envelope would make every consumer unwrap and re-encode, and
    re-encoding XML is how a document stops matching the one that was
    validated.
    """
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.modules.einvoice.emit_invoice",
        _returning(Result.good("<Invoice/>")),
    )

    response = client.get(PATH)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/xml")
    assert response.text == "<Invoice/>"
    assert "attachment" in response.headers["content-disposition"]


def test_a_refusal_comes_back_as_json_with_a_code(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A refusal is not a document, so it is not XML."""
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.modules.einvoice.emit_invoice",
        _returning(Result.err("not_issued", "This invoice is still a draft.")),
    )

    response = client.get(PATH)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "not_issued"


def test_an_invoice_the_caller_cannot_see_is_404_not_403(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """RLS decided this, and the response must not distinguish "not yours"
    from "does not exist"."""
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.modules.einvoice.emit_invoice",
        _returning(Result.err("not_found", "No such invoice.")),
    )

    assert client.get(PATH).status_code == 404


def test_an_unauthenticated_caller_gets_nothing(app: FastAPI, client: TestClient) -> None:
    """Without this the tests above would pass against an endpoint that hands
    any stranger a customer's invoice.

    The verifier is stubbed rather than left out. `current_caller` depends on
    it, so FastAPI resolves it before the missing-token check runs, and an app
    built without `lifespan` has nothing on `app.state`. Leaving it out tests
    an AttributeError, not a refusal.
    """
    app.dependency_overrides[get_verifier] = lambda: _NeverCalledVerifier()

    response = client.get(PATH)

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


class _NeverCalledVerifier:
    """Refuses if reached. No token was sent, so nothing should verify one."""

    def verify(self, token: str, company: str | None) -> Caller:
        raise AssertionError("the verifier was called for a request with no token")


def _returning(result: Result):  # type: ignore[no-untyped-def]
    async def _emit(conn: object, invoice_id: object) -> Result:
        return result

    return _emit


def test_the_pdf_route_is_registered_as_a_get(app: FastAPI) -> None:
    paths = {
        route.path
        for route in app.routes
        if isinstance(route, APIRoute) and route.methods == {"GET"}
    }
    assert "/api/v1/invoices/{invoice_id}/pdf" in paths


def test_a_pdf_comes_back_as_pdf_bytes_shown_inline(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """inline, not attachment: this one is meant to be looked at before it is
    sent, where the XML is only ever a file."""
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.modules.einvoice.render_invoice_pdf",
        _returning(Result.good(b"%PDF-1.7 stub")),
    )

    response = client.get(PDF_PATH)

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert response.content == b"%PDF-1.7 stub"
    assert response.headers["content-disposition"].startswith("inline")


def test_a_pdf_refusal_is_json_not_a_broken_document(
    app: FastAPI, client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A viewer handed application/pdf that is not a PDF shows an error box
    with nothing in it, and the reason is lost."""
    _authenticate(app)
    monkeypatch.setattr(
        "vega_api.modules.einvoice.render_invoice_pdf",
        _returning(Result.err("not_issued", "This invoice is still a draft.")),
    )

    response = client.get(PDF_PATH)

    assert response.status_code == 422
    assert response.headers["content-type"].startswith("application/json")
    assert response.json()["error"]["code"] == "not_issued"


def test_an_unauthenticated_caller_gets_no_pdf(app: FastAPI, client: TestClient) -> None:
    app.dependency_overrides[get_verifier] = lambda: _NeverCalledVerifier()

    response = client.get(PDF_PATH)

    assert response.status_code == 401
