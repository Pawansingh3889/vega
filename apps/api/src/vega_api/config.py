"""Settings, read from the environment once at startup.

Nothing here has a default that would work in production by accident. A missing
Supabase URL should stop the service, not let it run against nothing.
"""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Annotated

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    # No populate_by_name, deliberately. It would let `Settings(cors_origins=...)`
    # work in Python, but pydantic-settings then also reads the bare
    # CORS_ORIGINS from the environment, leaving two variables that both
    # configure one thing. Two names is the bug in #84, not the fix for it, so
    # the alias is the only way in and construction sites pass VEGA_CORS_ORIGINS.
    #
    # The cost is that with extra="ignore" a stray `cors_origins=` keyword is
    # dropped in SILENCE. mypy strict runs over src and tests and refuses it,
    # which is the only reason that cost is acceptable: it caught exactly this
    # in test_cors.py, where the call would otherwise have kept passing purely
    # because its allowed origin happens to equal the default.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    supabase_url: str = Field(alias="VITE_SUPABASE_URL")
    """Base URL of the Supabase project. Also the JWT issuer's prefix."""

    database_url: str = Field(alias="VEGA_DATABASE_URL")
    """Connection string for the vega_api role, which owns nothing.

    Request paths should use the transaction pooler (6543); the Procrastinate
    worker needs the session pooler (5432) because LISTEN/NOTIFY does not
    survive transaction mode. See ARCHITECTURE.md section 6.
    """

    getaddress_api_key: str | None = Field(default=None, alias="GETADDRESS_API_KEY")
    """getAddress.io key for postcode lookup on address entry. Optional, per
    #92: an unset key fails the one request that needs it, loudly and with the
    variable named, instead of failing every request that does not. Held only
    by this service, never sent to the browser.
    """

    jwt_audience: str = "authenticated"
    jwt_algorithms: tuple[str, ...] = ("ES256",)
    """An allowlist, not a hint. Accepting whatever the token claims is how
    `alg: none` and HS256-with-the-public-key attacks work."""

    pool_min_size: int = 1
    pool_max_size: int = 10
    """Bounded on purpose. Fly and Supabase are different clouds and worker
    fan-out is a connection storm generator."""

    cors_origins: Annotated[list[str], NoDecode] = Field(
        default=["http://localhost:8080"], alias="VEGA_CORS_ORIGINS"
    )
    """Browser origins allowed to call this service, from VEGA_CORS_ORIGINS
    (comma separated). The web app is served from its own origin, so its
    calls are cross-origin and preflighted: the browser will not even send
    the Authorization and X-Vega-Company headers unless this service answers
    the preflight naming the web origin. Set it to the deployed web origin
    when the web deploys; localhost:8080 is the Vite dev server.

    The alias is not decoration. `Settings` has no `env_prefix`, so without it
    pydantic reads `CORS_ORIGINS` while every doc says `VEGA_CORS_ORIGINS`, and
    the documented variable is ignored in silence: origins stay at localhost,
    every call from the deployed web origin dies at the preflight, and nothing
    reaches the service to be logged. See #84.
    """

    hmrc_client_id: str | None = Field(default=None, alias="HMRC_CLIENT_ID")
    hmrc_client_secret: str | None = Field(default=None, alias="HMRC_CLIENT_SECRET")
    """Credentials for the HMRC Developer Hub application.

    Optional, and unset today: nobody has registered one yet. The OAuth flow is
    written and tested against a fake transport, so it is provable without
    them; connecting for real is not, and the route refuses with a message
    naming these rather than half working.
    """

    hmrc_environment: str = Field(default="sandbox", alias="HMRC_ENVIRONMENT")
    """`sandbox` or `production`. Defaults to sandbox on purpose: the safe
    default for a value that decides whether a filing is a rehearsal."""

    token_key: str | None = Field(default=None, alias="VEGA_TOKEN_KEY")
    """Fernet key for encrypting HMRC tokens before they reach Postgres.

    No default, ever. A default key is the same as no encryption, and it would
    be a default that looks like protection (#109 q3).
    """

    @field_validator("getaddress_api_key", mode="before")
    @classmethod
    def _blank_is_unset(cls, value: object) -> object:
        """An empty or whitespace-only key is not a key.

        Without this, `None` and `""` take different paths and only one of them
        is the fixed one. That is not a hypothetical: `.env.example` ships
        `GETADDRESS_API_KEY=` with no value, and CONTRIBUTING tells people to
        copy it, so the empty string is the likeliest way to arrive here. It
        would reach getAddress.io, be rejected, and come back as
        "Postcode lookup service is unavailable", which blames the provider for
        a deployment that was never configured. That is the exact confusion #92
        was filed about.
        """
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        """Accept the comma separated form the docstring promises.

        pydantic parses `list[str]` from JSON, so the documented
        `VEGA_CORS_ORIGINS=https://a.com,https://b.com` raised a SettingsError
        and only `["https://a.com"]` worked. A deploy console gets the comma
        form typed into it, so that is the one that has to work.

        `NoDecode` on the field is what makes this reachable at all. Without it
        `EnvSettingsSource` JSON-decodes complex fields before any validator
        runs, so the comma form failed inside the source and this never saw it.
        JSON is still accepted, handled here rather than by the source.
        """
        if not isinstance(value, str):
            return value
        text = value.strip()
        if text.startswith("["):
            # Anything already configured as JSON keeps working. Malformed JSON
            # raises here rather than being silently read as one long origin,
            # which would fail the preflight and say nothing.
            return json.loads(text)
        return [origin.strip() for origin in text.split(",") if origin.strip()]

    @property
    def jwt_issuer(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/auth/v1"

    @property
    def jwks_url(self) -> str:
        return f"{self.jwt_issuer}/.well-known/jwks.json"


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
