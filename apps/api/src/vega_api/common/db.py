"""Database access, and the impersonation that makes RLS apply to this service.

The service connects as `vega_api`, a role that owns nothing and, on its own,
sees nothing: every policy in this schema names `authenticated`. So for the
duration of a request it BECOMES that role and presents the caller's claims,
which is exactly what PostgREST does.

The consequence worth being clear about: the tenant boundary for this service is
enforced by the same policies, evaluated by the same database, as for the
browser. There is no second implementation of tenancy in Python to drift out of
step, and the tenant isolation suite already covers both.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from urllib.parse import quote

import asyncpg

from ..auth import Caller
from ..config import Settings


class Database:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        self._pool = await asyncpg.create_pool(
            self._settings.database_url,
            min_size=self._settings.pool_min_size,
            max_size=self._settings.pool_max_size,
            # Supabase's pooler does its own statement caching, and asyncpg's
            # prepared statements do not survive it.
            statement_cache_size=0,
        )

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None

    @property
    def pool(self) -> asyncpg.Pool:
        if self._pool is None:
            raise RuntimeError("the database pool is not open; call connect() first")
        return self._pool

    @asynccontextmanager
    async def acting_as(self, caller: Caller) -> AsyncIterator[asyncpg.Connection]:
        """Run inside a transaction that impersonates the caller.

        SET LOCAL and set_config(..., true) are both transaction-scoped, so the
        identity cannot leak into the next borrower of this pooled connection.
        That is not a detail: a leaked role on a shared pool is one tenant
        reading another's rows.
        """
        async with self.pool.acquire() as conn, conn.transaction():
            await conn.execute("SET LOCAL ROLE authenticated")
            await conn.execute(
                "SELECT set_config('request.jwt.claim.sub', $1, true)", str(caller.user_id)
            )
            headers = (
                json.dumps({"x-vega-company": str(caller.requested_company)})
                if caller.requested_company
                else "{}"
            )
            await conn.execute("SELECT set_config('request.headers', $1, true)", headers)
            yield conn

    @asynccontextmanager
    async def as_service(self) -> AsyncIterator[asyncpg.Connection]:
        """Run as vega_api itself, with no user.

        Only for work where no user is present, such as the FX ingestion job.
        It reaches exactly what 0014 granted the role and nothing else.
        """
        async with self.pool.acquire() as conn, conn.transaction():
            yield conn


def with_schema(dsn: str, schema: str = "procrastinate") -> str:
    """Put a schema on a connection's search_path.

    Procrastinate's SQL uses unqualified names and its App takes no schema
    argument, so search_path is how its tables are found. It goes in the DSN
    rather than the connector's kwargs, because the connector passes conninfo
    itself and psycopg refuses the duplicate.

    `public` stays on the path: the tasks read business tables too.
    """
    # quote, not quote_plus: libpq does not read "+" as a space, so a
    # plus-encoded option arrives as the parameter "+search_path".
    option = quote(f"-c search_path={schema},public", safe="")
    separator = "&" if "?" in dsn else "?"
    return f"{dsn}{separator}options={option}"
