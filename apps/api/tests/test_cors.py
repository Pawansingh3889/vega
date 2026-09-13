"""The preflight answers, or the browser never sends the call.

A preflight this service does not answer is a request the browser refuses
without any error the page can see, which is how an endpoint can work in curl
and fail in a browser with nothing in the logs. These tests pin the contract:
an allowed origin gets the headers that let its call through, an unknown
origin gets nothing that does.

The settings are constructed here rather than read from the environment, so
the tests hold whether or not the process has real credentials.
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient

from vega_api.config import Settings
from vega_api.cors import configure_cors

ALLOWED = "http://localhost:8080"
FORBIDDEN = "https://evil.example"


def _client() -> TestClient:
    settings = Settings(
        VITE_SUPABASE_URL="https://stub.supabase.co",
        VEGA_DATABASE_URL="postgresql://stub",
        # By alias, not by field name. #84 gave cors_origins an alias so the
        # documented VEGA_CORS_ORIGINS is the one that is read; with
        # extra="ignore" the field name would be dropped in silence, and this
        # test would keep passing because ALLOWED equals the default.
        VEGA_CORS_ORIGINS=[ALLOWED],
    )
    app = FastAPI()

    @app.get("/probe")
    async def probe() -> dict[str, str]:
        return {"status": "ok"}

    configure_cors(app, settings)
    return TestClient(app)


def test_preflight_from_an_allowed_origin_carries_the_contract() -> None:
    response = _client().options(
        "/probe",
        headers={
            "Origin": ALLOWED,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization,x-vega-company",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == ALLOWED
    allowed_headers = response.headers["access-control-allow-headers"].lower()
    assert "authorization" in allowed_headers
    assert "x-vega-company" in allowed_headers


def test_preflight_from_an_unknown_origin_gets_nothing() -> None:
    response = _client().options(
        "/probe",
        headers={
            "Origin": FORBIDDEN,
            "Access-Control-Request-Method": "GET",
        },
    )
    assert "access-control-allow-origin" not in response.headers


def test_the_vat_call_itself_is_answered_for_the_web_origin() -> None:
    """A simple GET with the two headers the VAT screen sends."""
    response = _client().get(
        "/probe",
        headers={
            "Origin": ALLOWED,
            "Authorization": "Bearer whatever",
            "X-Vega-Company": "00000000-0000-0000-0000-000000000000",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == ALLOWED


def test_a_call_without_an_origin_is_not_a_browser_call() -> None:
    """curl and the worker send no Origin. CORS is browser policy; it must
    not gate a server-to-server call."""
    response = _client().get("/probe")
    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers
