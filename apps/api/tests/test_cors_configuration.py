"""The documented way to configure CORS must be the way that works.

`config.py` says origins come from `VEGA_CORS_ORIGINS`, comma separated. Neither
half was true (#84): `Settings` has no `env_prefix`, so pydantic read
`CORS_ORIGINS`, and `list[str]` was parsed as JSON, so the comma form raised.
Setting the documented variable did nothing at all and said nothing about it.

That is worse than an ordinary misconfiguration. `cors.py` states the
consequence itself: "A preflight this does not answer is a call the browser
never sends, and it refuses silently." Origins stuck at localhost means every
call from the deployed web origin dies at the preflight, and nothing reaches
the service to be logged.

So these tests assert against the documented contract, not against whatever the
code happens to do, and the last one goes all the way to the response header
rather than stopping at the Settings object.
"""

from __future__ import annotations

import json

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from vega_api.config import Settings
from vega_api.cors import configure_cors

DEPLOYED = "https://vega.example.com"
OTHER = "https://second.example.com"


def _settings(**overrides: object) -> Settings:
    """A Settings built from arguments, so no environment is involved."""
    base: dict[str, object] = {
        "VITE_SUPABASE_URL": "https://example.supabase.co",
        "VEGA_DATABASE_URL": "postgresql://nobody@localhost/nothing",
    }
    base.update(overrides)
    return Settings(**base)  # type: ignore[arg-type]


def test_the_documented_variable_is_the_one_that_is_read(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`VEGA_CORS_ORIGINS`, the name every doc uses."""
    monkeypatch.setenv("VITE_SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("VEGA_DATABASE_URL", "postgresql://nobody@localhost/nothing")
    monkeypatch.setenv("VEGA_CORS_ORIGINS", DEPLOYED)

    # Settings reads its required fields from the environment set above;
    # mypy cannot see that, same as config.get_settings.
    assert Settings().cors_origins == [DEPLOYED]  # type: ignore[call-arg]


def test_the_unprefixed_name_is_not_read(monkeypatch: pytest.MonkeyPatch) -> None:
    """`CORS_ORIGINS` was what actually worked, by accident. It must not now.

    Without this, adding the alias while pydantic still honoured the bare name
    would leave two ways to set one thing, and a deploy setting both would get
    whichever pydantic preferred.
    """
    monkeypatch.setenv("VITE_SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("VEGA_DATABASE_URL", "postgresql://nobody@localhost/nothing")
    monkeypatch.setenv("CORS_ORIGINS", DEPLOYED)

    assert Settings().cors_origins == ["http://localhost:8080"]  # type: ignore[call-arg]


def test_the_documented_format_is_comma_separated() -> None:
    assert _settings(VEGA_CORS_ORIGINS=f"{DEPLOYED},{OTHER}").cors_origins == [
        DEPLOYED,
        OTHER,
    ]


def test_surrounding_space_is_trimmed() -> None:
    """A deploy console pastes ` a , b `, and an origin with a space never matches."""
    assert _settings(VEGA_CORS_ORIGINS=f" {DEPLOYED} , {OTHER} ").cors_origins == [
        DEPLOYED,
        OTHER,
    ]


def test_json_is_still_accepted() -> None:
    """The only form that worked before this change keeps working."""
    assert _settings(VEGA_CORS_ORIGINS=json.dumps([DEPLOYED])).cors_origins == [DEPLOYED]


def test_malformed_json_refuses_rather_than_becoming_one_long_origin() -> None:
    """Named exception, not a bare `Exception`: a catch-all here would pass on
    any error at all, including one raised because the field stopped existing."""
    with pytest.raises(ValidationError):
        _settings(VEGA_CORS_ORIGINS=f'["{DEPLOYED}')


def test_the_configured_origin_reaches_the_preflight_response() -> None:
    """The one that matters: end to end, to the header a browser actually reads.

    Every test above stops at the Settings object, and a correct Settings that
    never reaches CORSMiddleware would satisfy all of them while the browser is
    still refused.
    """
    app = FastAPI()
    configure_cors(app, _settings(VEGA_CORS_ORIGINS=DEPLOYED))

    @app.get("/probe")
    async def probe() -> dict[str, str]:  # pragma: no cover - exercised via OPTIONS
        return {"ok": "yes"}

    response = TestClient(app).options(
        "/probe",
        headers={
            "Origin": DEPLOYED,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == DEPLOYED


def test_an_origin_that_was_not_configured_is_still_refused() -> None:
    """Otherwise the test above passes just as well against a wildcard."""
    app = FastAPI()
    configure_cors(app, _settings(VEGA_CORS_ORIGINS=DEPLOYED))

    response = TestClient(app).options(
        "/probe",
        headers={
            "Origin": "https://attacker.example.com",
            "Access-Control-Request-Method": "GET",
        },
    )

    assert "access-control-allow-origin" not in response.headers
