"""Every repository query runs against the real schema.

Twice now a repository has named a column that does not exist, and both got
through review, mypy, the whole suite and CI:

    vat/repository.py       p.line_subtotal   the table has taxable_value   #99
    einvoice/repository.py  invoice_id        the column is sales_invoice_id #103

The cause is structural rather than careless. `service.py` is pure, so its
tests hand it typed rows and never touch SQL. `repository.py` holds the SQL,
and until this file nothing executed it. The layering that makes a VAT figure
testable without a database is exactly what left the SQL unexercised, and every
module written to the contract has the same hole.

These tests assert almost nothing about results. They do not need to:
`UndefinedColumnError` and `UndefinedTableError` are raised when Postgres
prepares the statement, so running each query against an empty database built
from the migrations catches the whole class in milliseconds. An empty result is
a pass. A query that cannot be prepared is not.
"""

from __future__ import annotations

import inspect
from datetime import date
from decimal import Decimal
from uuid import uuid4

import asyncpg
import pytest

from vega_api.modules import einvoice, fx, postcode, vat, vies

pytestmark = pytest.mark.asyncio

# Modules whose repository talks to Postgres. `postcode` is here so that the
# check below stays honest about which modules were considered, even though its
# only repository function is an HTTP call.
DB_MODULES = (vat, fx, einvoice, vies)


async def test_vat_queries_prepare_against_the_schema(db: asyncpg.Connection) -> None:
    """This is the query #99 was found by, and it 500'd in production shape."""
    from vega_api.modules.vat import repository

    assert await repository.load_treatments(db) is not None
    await repository.load_period_lines(db, date(2026, 7, 1), date(2026, 9, 30))
    await repository.current_company(db)


async def test_einvoice_queries_prepare_against_the_schema(
    db: asyncpg.Connection,
) -> None:
    """#103. `load_invoice` joined on a column that does not exist, so both
    the UBL and the PDF route would have 500'd on their first real call."""
    from vega_api.modules.einvoice import repository

    assert await repository.load_treatments(db) is not None
    assert await repository.invoice_status(db, uuid4()) is None

    # An invoice has to exist. `load_invoice` returns early when the head row is
    # missing, so calling it with a random id never reaches the lines query,
    # which is where #103 was. The first version of this test did exactly that
    # and passed with the bug put back.
    company, customer, invoice, author, product = (uuid4() for _ in range(5))
    await db.execute("INSERT INTO auth.users (id, email) VALUES ($1, 'sql@example.test')", author)
    await db.execute(
        "INSERT INTO public.companies (id, name) VALUES ($1, 'SQL Probe Ltd')", company
    )
    await db.execute(
        "INSERT INTO public.customers (id, company_id, name) VALUES ($1, $2, 'A Customer')",
        customer,
        company,
    )
    await db.execute(
        "INSERT INTO public.products (id, company_id, sku, name)"
        " VALUES ($1, $2, 'SKU-1', 'A Product')",
        product,
        company,
    )
    await db.execute(
        # A draft, with invoice_number left NULL: the counter allocates it and
        # supplying one is refused (SECURITY.md N5). `load_invoice` does not
        # gate on status, so a draft exercises the same SQL.
        """INSERT INTO public.sales_invoices
             (id, company_id, customer_id, customer_name, created_by,
              invoice_date, currency, subtotal_amount, total_amount, status)
           VALUES ($1, $2, $3, 'A Customer', $4,
                   DATE '2026-09-07', 'GBP', 100, 120, 'draft')""",
        invoice,
        company,
        customer,
        author,
    )
    await db.execute(
        """INSERT INTO public.sales_invoice_items
             (id, sales_invoice_id, product_id, item_code, item_description, quantity_invoiced,
              unit_price, line_subtotal, vat_treatment_code, vat_rate, vat_amount)
           VALUES (gen_random_uuid(), $1, $2, 'SKU-1', 'A line', 1, 100, 100, 'STD', 20, 20)""",
        invoice,
        product,
    )

    loaded = await repository.load_invoice(db, invoice)
    assert loaded is not None
    # The line query ran and returned the row, which is the assertion #103 needed.
    assert len(loaded.lines) == 1


async def test_fx_queries_prepare_against_the_schema(db: asyncpg.Connection) -> None:
    from vega_api.modules.fx import repository
    from vega_api.modules.fx.contract import SourcedRate

    await repository.latest_rate_date(db, "GBP", "EUR")
    await repository.missing_working_days(db, "EUR", "GBP")
    # store_rates refuses an empty write on purpose: SPEC 1.1 says a day that
    # was not captured is unrecoverable, so "accepted 0 rates" must never read
    # like success. Asserting the refusal keeps that guard honest.
    with pytest.raises(ValueError):
        await repository.store_rates(db, [])

    stored = await repository.store_rates(
        db,
        [
            SourcedRate(
                base_currency="EUR",
                quote_currency="GBP",
                rate=Decimal("0.85"),
                rate_date=date(2026, 9, 7),
            )
        ],
    )
    assert stored == 1


async def test_vies_queries_prepare_against_the_schema(db: asyncpg.Connection) -> None:
    from vega_api.modules.vies import repository

    await repository.get_vat_validation_status(db, "customers", uuid4())


async def test_every_database_module_has_its_queries_exercised() -> None:
    """Adding a module and forgetting this must fail, not pass quietly.

    The same bargain `test_every_module_is_covered_by_the_independence_contract`
    makes for the layering contract. Without it, the next module's SQL is
    unexercised again and the two defects above happen a third time.
    """
    tested = {
        name.removeprefix("test_").removesuffix("_queries_prepare_against_the_schema")
        for name, obj in globals().items()
        if name.startswith("test_") and name.endswith("_against_the_schema")
    }

    for module in DB_MODULES:
        short = module.__name__.rsplit(".", 1)[-1]
        assert short in tested, (
            f"{short} has a repository that talks to Postgres and no test here "
            f"runs its queries. Add one: an empty result is a pass, an "
            f"unpreparable statement is not."
        )


async def test_postcode_repository_is_http_only_and_needs_no_query_test() -> None:
    """Stated rather than assumed, so a future database query there is noticed.

    If someone gives postcode a Postgres query, this fails and they add it to
    DB_MODULES, instead of the query going unexercised because the module was
    once HTTP-only.
    """
    source = inspect.getsource(postcode.repository)

    assert "asyncpg" not in source, (
        "postcode/repository.py now talks to Postgres. Add it to DB_MODULES "
        "and give it a query test."
    )
