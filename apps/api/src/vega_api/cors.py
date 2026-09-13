"""CORS answers for the browser origins allowed to call this service.

Its own module because the composition root must stay importable without
environment: the settings here are injected, never read. Tests build a Settings
and pass it in; the running service passes the one it booted with.

The web app is served from its own origin, so its calls are cross-origin and
preflighted before the browser will carry the Authorization and X-Vega-Company
headers. Everything is explicit rather than wildcarded: an origin list, one
method, two headers. A preflight this does not answer is a call the browser
never sends, and it refuses silently.
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings


def configure_cors(app: FastAPI, settings: Settings) -> None:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET"],
        allow_headers=["authorization", "x-vega-company"],
        allow_credentials=False,
        max_age=600,
    )
