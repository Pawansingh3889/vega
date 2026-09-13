"""All the HMRC module's I/O: the token endpoint, and the credential row."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import date, datetime
from uuid import UUID

import asyncpg
import httpx

from ...common.crypto import SecretBox
from . import service
from .contract import Connection, HmrcError, Obligation, Tokens

TIMEOUT_SECONDS = 20.0


async def exchange_code(
    client: httpx.AsyncClient,
    *,
    environment: str,
    client_id: str,
    client_secret: str,
    redirect_uri: str,
    code: str,
    now: datetime,
) -> Tokens | HmrcError:
    """Trade the one-time authorisation code for tokens."""
    return await _token_call(
        client,
        environment=environment,
        now=now,
        form={
            "grant_type": "authorization_code",
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "code": code,
        },
        on_refusal=HmrcError.EXCHANGE_REFUSED,
    )


async def refresh_tokens(
    client: httpx.AsyncClient,
    *,
    environment: str,
    client_id: str,
    client_secret: str,
    refresh_token: str,
    now: datetime,
) -> Tokens | HmrcError:
    """Trade a refresh token for a new pair.

    HMRC rotates the refresh token, so the response's new one replaces the old.
    Keeping the old one would work until it silently stopped.
    """
    return await _token_call(
        client,
        environment=environment,
        now=now,
        form={
            "grant_type": "refresh_token",
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
        },
        on_refusal=HmrcError.REFRESH_REFUSED,
    )


async def _token_call(
    client: httpx.AsyncClient,
    *,
    environment: str,
    now: datetime,
    form: dict[str, str],
    on_refusal: HmrcError,
) -> Tokens | HmrcError:
    """One place that talks to the token endpoint.

    Nothing here stringifies the exception or the request. The form carries
    `client_secret` and, on a refresh, the refresh token itself, so `str(exc)`
    on an httpx error would put a live credential in the logs.
    """
    url = f"{service.base_url(environment)}/oauth/token"
    try:
        response = await client.post(
            url,
            data=form,
            headers={"Accept": "application/vnd.hmrc.1.0+json"},
            timeout=TIMEOUT_SECONDS,
        )
    except httpx.TimeoutException:
        return HmrcError.UNAVAILABLE
    except httpx.RequestError:
        return HmrcError.UNAVAILABLE

    if response.status_code >= 400:
        # 4xx means HMRC refused this grant; 5xx means they are having a bad
        # day. Told apart because one asks the person to reconnect and the
        # other asks them to wait.
        return on_refusal if response.status_code < 500 else HmrcError.UNAVAILABLE

    try:
        payload = response.json()
    except ValueError:
        return HmrcError.UNAVAILABLE

    return service.parse_tokens(payload, now=now)


async def store(
    conn: asyncpg.Connection,
    box: SecretBox,
    *,
    company_id: UUID,
    tokens: Tokens,
    environment: str,
    connected_by: UUID,
) -> None:
    """Write the connection, encrypting before the value leaves this process."""
    await conn.execute(
        """
        INSERT INTO public.hmrc_credentials
            (company_id, access_token_ciphertext, refresh_token_ciphertext,
             access_token_expires_at, scope, environment, connected_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (company_id) DO UPDATE SET
            access_token_ciphertext  = EXCLUDED.access_token_ciphertext,
            refresh_token_ciphertext = EXCLUDED.refresh_token_ciphertext,
            access_token_expires_at  = EXCLUDED.access_token_expires_at,
            scope                    = EXCLUDED.scope,
            environment              = EXCLUDED.environment,
            refreshed_at             = now()
        """,
        company_id,
        box.seal(tokens.access_token),
        box.seal(tokens.refresh_token),
        tokens.expires_at,
        tokens.scope,
        environment,
        connected_by,
    )


async def load_connection(conn: asyncpg.Connection, company_id: UUID) -> Connection | None:
    """What a caller may know. No tokens, encrypted or otherwise."""
    row = await conn.fetchrow(
        """SELECT company_id, access_token_expires_at, scope, environment,
                  connected_at, refreshed_at
             FROM public.hmrc_credentials WHERE company_id = $1""",
        company_id,
    )
    if row is None:
        return None
    return Connection(
        company_id=str(row["company_id"]),
        expires_at=row["access_token_expires_at"],
        scope=row["scope"],
        environment=row["environment"],
        connected_at=row["connected_at"],
        refreshed_at=row["refreshed_at"],
    )


async def load_refresh_token(
    conn: asyncpg.Connection, box: SecretBox, company_id: UUID
) -> str | None:
    """Read and decrypt one refresh token, for one use, at the point of use."""
    row = await conn.fetchrow(
        "SELECT refresh_token_ciphertext FROM public.hmrc_credentials WHERE company_id = $1",
        company_id,
    )
    if row is None:
        return None
    return box.open(row["refresh_token_ciphertext"])


async def fetch_obligations(
    client: httpx.AsyncClient,
    fraud_headers: Mapping[str, str],
    *,
    environment: str,
    access_token: str,
    vrn: str,
    from_date: date,
    to_date: date,
) -> list[Obligation] | HmrcError:
    """The VAT periods HMRC expects returns for.

    `fraud_headers` is positional and required, deliberately. Every MTD call
    needs them, not only a submission, and a signature with a default or an
    optional would let a caller omit them and still compile. The one way to be
    sure they are never fabricated is to make them impossible to leave out.

    Read-only, which is why this is the first HMRC call to build: it teaches
    the API's shape without filing anything.
    """
    url = (
        f"{service.base_url(environment)}/organisations/vat/{vrn}/obligations"
        f"?from={from_date.isoformat()}&to={to_date.isoformat()}"
    )
    headers = {
        **dict(fraud_headers),
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/vnd.hmrc.1.0+json",
    }
    try:
        response = await client.get(url, headers=headers, timeout=TIMEOUT_SECONDS)
    except httpx.TimeoutException:
        return HmrcError.UNAVAILABLE
    except httpx.RequestError:
        return HmrcError.UNAVAILABLE

    if response.status_code == 401:
        # The token is dead. Distinct from an outage: this one is recoverable
        # by refreshing, and reporting it as unavailable would send somebody to
        # wait for HMRC instead.
        return HmrcError.REFRESH_REFUSED
    if response.status_code >= 400:
        return HmrcError.UNAVAILABLE

    try:
        payload = response.json()
    except ValueError:
        return HmrcError.UNAVAILABLE

    return service.parse_obligations(payload)
