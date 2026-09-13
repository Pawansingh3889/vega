"""SECURITY.md N5: gapless invoice numbering, proven under contention.

The defect this guards only appears under concurrent load, so the main test
issues invoices through a pool of real connections at once. A gather of
coroutines over one connection serialises itself and proves nothing; the
first attempt at this issue made exactly that mistake.

One structural consequence: this file seeds with commits rather than inside
the `db` fixture's transaction, because pool connections cannot see another
connection's uncommitted rows. The session-scoped container therefore keeps
the seeded companies after these tests run; they are fresh UUIDs that no
other test enumerates.
"""

from __future__ import annotations

import asyncio
import uuid

import asyncpg
import pytest

from .conftest import Tenants, act_as

pytestmark = pytest.mark.asyncio

DRAFT = (
    "INSERT INTO public.sales_invoices"
    " (company_id, customer_id, customer_name, created_by)"
    " VALUES ($1, $2, 'Probe Customer', gen_random_uuid()) RETURNING id"
)


def year_of(number: str) -> int:
    return int(number.split("-")[0])


async def test_numbers_are_consecutive_for_one_company(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The quiet case first: three issues, one company, one after another."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    numbers: list[str] = []
    for _ in range(3):
        invoice_id = await db.fetchval(DRAFT, tenants.company_a, customer_id)
        assert invoice_id is not None
        number = await db.fetchval(
            """UPDATE public.sales_invoices SET status = 'issued'
               WHERE id = $1 RETURNING invoice_number""",
            invoice_id,
        )
        assert isinstance(number, str)
        numbers.append(number)
    assert numbers == [f"2026-{n:06d}" for n in (1, 2, 3)]


async def test_an_issued_invoice_carries_a_number_and_a_draft_has_none(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The consistency constraint, from both sides."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    invoice_id = await db.fetchval(DRAFT, tenants.company_a, customer_id)
    assert (
        await db.fetchval(
            "SELECT invoice_number FROM public.sales_invoices WHERE id = $1", invoice_id
        )
        is None
    ), "a draft must be unnumbered, or abandoning it burns a gap"
    await db.execute("UPDATE public.sales_invoices SET status = 'issued' WHERE id = $1", invoice_id)
    assert (
        await db.fetchval(
            "SELECT invoice_number FROM public.sales_invoices WHERE id = $1", invoice_id
        )
        is not None
    )


async def test_a_client_supplied_number_is_refused(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """A number that does not come from the counter is a claim, not a result."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    with pytest.raises(asyncpg.PostgresError, match="allocated here, not supplied"):
        async with db.transaction():
            await db.execute(
                "INSERT INTO public.sales_invoices"
                " (company_id, customer_id, customer_name, created_by, status, invoice_number)"
                " VALUES ($1, $2, 'Probe Customer', gen_random_uuid(), 'issued', '2026-999999')",
                tenants.company_a,
                customer_id,
            )


async def test_renumbering_is_refused_independently_of_the_freeze(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The allocation trigger refuses a number change on its own, so the
    property survives whichever of the two controls lands or is dropped. The
    freeze trigger from #26 would catch this first, so it is disabled for the
    duration: that is the point of the test, and it is put back before the
    fixture's rollback."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    invoice_id = await db.fetchval(DRAFT, tenants.company_a, customer_id)
    await db.execute("UPDATE public.sales_invoices SET status = 'issued' WHERE id = $1", invoice_id)
    before = await db.fetchval(
        "SELECT invoice_number FROM public.sales_invoices WHERE id = $1", invoice_id
    )
    await db.execute("ALTER TABLE public.sales_invoices DISABLE TRIGGER sales_invoices_append_only")
    try:
        with pytest.raises(asyncpg.PostgresError, match="renumbering is not permitted"):
            async with db.transaction():
                await db.execute(
                    "UPDATE public.sales_invoices SET invoice_number = '2026-999999' WHERE id = $1",
                    invoice_id,
                )
    finally:
        await db.execute(
            "ALTER TABLE public.sales_invoices ENABLE TRIGGER sales_invoices_append_only"
        )
    assert (
        await db.fetchval(
            "SELECT invoice_number FROM public.sales_invoices WHERE id = $1", invoice_id
        )
        == before
    )


async def test_the_counter_sits_behind_row_level_security(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """N1: the counter is tenant data. A member reads their own and nobody
    else's; a direct write from a signed-in user is refused twice over, by
    grants and by a policy set that permits no writes at all."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    invoice_id = await db.fetchval(DRAFT, tenants.company_a, customer_id)
    await db.execute("UPDATE public.sales_invoices SET status = 'issued' WHERE id = $1", invoice_id)
    async with db.transaction():
        await act_as(db, tenants.dual_user, tenants.company_a)
        rows = await db.fetch("SELECT company_id, next_number FROM public.invoice_counters")
        assert len(rows) == 1, "a member saw a counter that is not their company's"
        assert rows[0]["company_id"] == tenants.company_a
        with pytest.raises(asyncpg.PostgresError):
            async with db.transaction():
                await db.execute(
                    "UPDATE public.invoice_counters SET next_number = 999 WHERE company_id = $1",
                    tenants.company_a,
                )


async def seed_issuable(dsn: str, count: int) -> tuple[uuid.UUID, list[uuid.UUID]]:
    """A company, a customer, and `count` draft invoices, committed.

    Committed because the contention test reads them from pool connections,
    which share nothing with the fixture transaction.
    """
    company_id = uuid.uuid4()
    conn = await asyncpg.connect(dsn)
    try:
        async with conn.transaction():
            await conn.execute(
                "INSERT INTO public.companies (id, name) VALUES ($1, 'Numbering Probe')",
                company_id,
            )
            customer_id = await conn.fetchval(
                "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
                " RETURNING id",
                company_id,
            )
            invoice_ids = []
            for _ in range(count):
                invoice_id = await conn.fetchval(DRAFT, company_id, customer_id)
                assert isinstance(invoice_id, uuid.UUID)
                invoice_ids.append(invoice_id)
    finally:
        await conn.close()
    return company_id, invoice_ids


async def test_contention_produces_no_gap_and_no_duplicate(database_dsn: str) -> None:
    """The test the issue refuses to ship without: ADR 0006 says a sequential
    issue proves nothing, because the defect only exists under contention.

    Twelve pool connections issue twelve drafts of one company at the same
    moment. With the row lock, the numbers are consecutive and unique, and the
    counter advanced by exactly twelve.
    """
    count = 12
    company_id, invoice_ids = await seed_issuable(database_dsn, count)

    pool = await asyncpg.create_pool(database_dsn, min_size=1, max_size=count)
    try:

        async def issue(invoice_id: uuid.UUID) -> object:
            async with pool.acquire() as conn:
                return await conn.fetchval(
                    """UPDATE public.sales_invoices SET status = 'issued'
                       WHERE id = $1 RETURNING invoice_number""",
                    invoice_id,
                )

        raw = await asyncio.gather(*(issue(i) for i in invoice_ids))
    finally:
        await pool.close()

    numbers: list[str] = []
    for n in raw:
        assert isinstance(n, str), "an invoice issued without a number"
        numbers.append(n)
    years = {year_of(n) for n in numbers}
    assert len(years) == 1, "numbers straddled a year boundary mid-test"
    seqs = sorted(int(n.split("-")[1]) for n in numbers)
    assert len(set(seqs)) == count, f"duplicate numbers under contention: {sorted(numbers)}"
    assert seqs == list(range(seqs[0], seqs[0] + count)), f"a gap under contention: {seqs}"

    conn = await asyncpg.connect(database_dsn)
    try:
        counter = await conn.fetchval(
            "SELECT next_number FROM public.invoice_counters WHERE company_id = $1",
            company_id,
        )
    finally:
        await conn.close()
    assert counter == seqs[0] + count
