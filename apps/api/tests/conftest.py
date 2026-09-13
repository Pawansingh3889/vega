"""A real Postgres, built from the migration set, for the tenant isolation suite.

SECURITY.md N1 requires that tenant isolation is proven rather than asserted, and
row level security cannot be exercised against a mock: policies are enforced by
the database, for a specific role, or not at all. So these tests run against a
throwaway container built the same way `make db-verify` builds one.

The container is session-scoped. Building it costs a few seconds once; running
the suite against a shared long-lived database would let one test's rows leak
into another's assertions, which is exactly the failure mode being tested for.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import uuid
import zlib
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import asyncpg
import pytest

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "supabase" / "migrations"
SHIM = ROOT / "scripts" / "supabase-shim.sql"


def _worktree_id() -> str:
    """This worktree's identity, from the file scripts/worktree-id.sh writes.

    Read rather than recomputed: `cksum` and Python's crc32 are different
    algorithms, so deriving it in both places gave one worktree two identities.

    Without an identity at all, two checkouts running the suite at once share a
    container name and a port, and whichever starts second does `rm -f` on the
    first one's database mid-test. That surfaces as a flaky test rather than as
    a collision, which is the worst way for it to appear.
    """
    marker = ROOT / ".vega-worktree-id"
    if marker.exists():
        return marker.read_text().strip()
    generated = f"{zlib.crc32(str(ROOT).encode()) % 90:02d}"
    marker.write_text(generated)
    return generated


WORKTREE = _worktree_id()
CONTAINER = f"vega-{WORKTREE}-pytest-rls"
PORT = int(os.environ.get("VEGA_TEST_PGPORT", str(54400 + int(WORKTREE) * 100 + 5)))
IMAGE = "docker.io/library/postgres:17"


def _runtime() -> str | None:
    return shutil.which("docker") or shutil.which("podman")


def _psql(runtime: str, sql_file: Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [
            runtime,
            "exec",
            "-i",
            CONTAINER,
            "psql",
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
        ],
        stdin=sql_file.open("rb"),
        capture_output=True,
        check=False,
    )


@pytest.fixture(scope="session")
def database_dsn() -> Iterator[str]:
    runtime = _runtime()
    if runtime is None:
        # Skipping locally is a convenience. Skipping in CI would silently drop
        # the only tests that prove the tenant boundary, and a suite that can
        # quietly not run is the same failure as a typecheck that compiles no
        # files. CI sets VEGA_REQUIRE_DB=1 so absence is a failure there.
        if os.environ.get("VEGA_REQUIRE_DB") == "1":
            pytest.fail("VEGA_REQUIRE_DB=1 but no container runtime is available")
        pytest.skip("no container runtime; the isolation suite needs a real Postgres")

    subprocess.run([runtime, "rm", "-f", CONTAINER], capture_output=True, check=False)
    subprocess.run(
        [
            runtime,
            "run",
            "-d",
            "--name",
            CONTAINER,
            "-e",
            "POSTGRES_PASSWORD=postgres",
            "-p",
            f"{PORT}:5432",
            IMAGE,
        ],
        capture_output=True,
        check=True,
    )
    try:
        # pg_isready alone is not enough. The official image starts Postgres to
        # run its init scripts, then restarts it, so pg_isready can succeed
        # against the first instance moments before the socket disappears. Wait
        # for a real query to succeed twice a second apart instead.
        stable = 0
        for _ in range(90):
            ok = subprocess.run(
                [
                    runtime,
                    "exec",
                    CONTAINER,
                    "psql",
                    "-U",
                    "postgres",
                    "-d",
                    "postgres",
                    "-tAc",
                    "SELECT 1",
                ],
                capture_output=True,
                check=False,
            )
            stable = stable + 1 if ok.returncode == 0 else 0
            if stable >= 2:
                break
            time.sleep(1)
        else:
            pytest.fail("Postgres did not become ready")

        result = _psql(runtime, SHIM)
        assert result.returncode == 0, result.stderr.decode()[-2000:]

        for migration in sorted(MIGRATIONS.glob("*.sql")):
            result = _psql(runtime, migration)
            assert result.returncode == 0, (
                f"{migration.name} failed:\n{result.stderr.decode()[-2000:]}"
            )

        yield f"postgresql://postgres:postgres@127.0.0.1:{PORT}/postgres"
    finally:
        if os.environ.get("VEGA_KEEP_TEST_DB") != "1":
            subprocess.run([runtime, "rm", "-f", CONTAINER], capture_output=True, check=False)


@pytest.fixture
async def db(database_dsn: str) -> AsyncIterator[asyncpg.Connection]:
    """A connection whose whole test runs inside one transaction, rolled back.

    Deleting the fixture rows by hand does not work: audit triggers write into
    transaction_audit_log, which holds a foreign key back to companies, so
    teardown fails on the reference. Chasing the delete order would encode the
    trigger graph into the tests and break every time it changes. Rolling back
    removes the question. Tests that open their own transaction get a savepoint.
    """
    conn = await asyncpg.connect(database_dsn)
    transaction = conn.transaction()
    await transaction.start()
    try:
        yield conn
    finally:
        await transaction.rollback()
        await conn.close()


class Tenants:
    """Two companies and the people in them.

    company_a and company_b are separate tenants. solo_user belongs to A only.
    dual_user belongs to both, which is the case N1 exists to cover: Rigel's
    accounts are multi-business, so the realistic tenancy defect is one person
    whose boundary must follow the session rather than their profile row.
    """

    def __init__(
        self,
        company_a: uuid.UUID,
        company_b: uuid.UUID,
        solo_user: uuid.UUID,
        dual_user: uuid.UUID,
        outsider: uuid.UUID,
    ) -> None:
        self.company_a = company_a
        self.company_b = company_b
        self.solo_user = solo_user
        self.dual_user = dual_user
        self.outsider = outsider


@pytest.fixture
async def tenants(db: asyncpg.Connection) -> AsyncIterator[Tenants]:
    company_a, company_b = uuid.uuid4(), uuid.uuid4()
    solo, dual, outsider = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()

    # auth.users first: profiles.user_id and company_users.user_id both point at
    # it, and Supabase owns that table, so a test identity has to exist there
    # before it can exist anywhere else.
    await db.execute(
        """INSERT INTO auth.users (id, email) VALUES
             ($1, 'solo@example.test'), ($2, 'dual@example.test'), ($3, 'outsider@example.test')""",
        solo,
        dual,
        outsider,
    )
    await db.execute(
        "INSERT INTO public.companies (id, name) VALUES ($1, 'Alpha Foods'), ($2, 'Beta Bakery')",
        company_a,
        company_b,
    )
    # solo_user gets a profile only; dual_user gets memberships in both. Between
    # them they cover the inherited schema's two sources of company membership.
    await db.execute(
        "INSERT INTO public.profiles (user_id, company_id) VALUES ($1, $2)", solo, company_a
    )
    await db.execute(
        # Distinct username and email per row: company_users carries uniqueness on
        # both, so the same person in two companies needs two credentials rows.
        # That is itself a smell in the inherited model, noted for Phase 2.
        """INSERT INTO public.company_users
             (company_id, user_id, username, email, password_hash, status)
           VALUES ($1, $2, 'dual-a', 'dual+a@example.test', 'x', 'ACTIVE'),
                  ($3, $2, 'dual-b', 'dual+b@example.test', 'x', 'ACTIVE')""",
        company_a,
        dual,
        company_b,
    )
    # One product per company, so a leak is visible as a row rather than a count.
    await db.execute(
        """INSERT INTO public.products (company_id, sku, name) VALUES
           ($1, 'A-001', 'Alpha Sourdough'), ($2, 'B-001', 'Beta Baguette')""",
        company_a,
        company_b,
    )
    # No teardown: the db fixture rolls the whole transaction back.
    yield Tenants(company_a, company_b, solo, dual, outsider)


async def act_as(
    conn: asyncpg.Connection,
    user: uuid.UUID | None,
    company: uuid.UUID | None = None,
    role: str = "authenticated",
) -> None:
    """Take on a signed-in user's identity for the current transaction.

    auth.uid() reads request.jwt.claim.sub and current_company_id() reads the
    x-vega-company request header, so setting those two GUCs reproduces exactly
    what PostgREST would present. SET LOCAL ROLE matters as much: RLS is not
    enforced for the owner, so a test that forgets it passes while proving
    nothing.
    """
    await conn.execute(f"SET LOCAL ROLE {role}")
    await conn.execute(
        "SELECT set_config('request.jwt.claim.sub', $1, true)", str(user) if user else ""
    )
    headers = json.dumps({"x-vega-company": str(company)}) if company else "{}"
    await conn.execute("SELECT set_config('request.headers', $1, true)", headers)
