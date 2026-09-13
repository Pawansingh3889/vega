"""SECURITY.md N2 part two: issued invoices and confirmed credit notes are frozen.

The suite runs as the table owner. That is the point, not an accident: a
connection as postgres owns every table here, and the owner is the role that
bypasses row level security. If append-only only held for ordinary roles it
would be worthless exactly when it matters, so the refusal tests deliberately
make no SET ROLE at all.

Every refusal test seeds its row first and asserts it exists. A BEFORE ROW
trigger never fires on an empty table and DELETE over nothing is a no-op, so a
test that skips that step passes against no protection at all. That failure
has already happened once in this repository.
"""

from __future__ import annotations

import uuid

import asyncpg
import pytest

from .conftest import Tenants, act_as

pytestmark = pytest.mark.asyncio

REFUSAL = "append-only once issued"


async def seed_invoice(
    db: asyncpg.Connection, tenants: Tenants, *, issue: bool = False
) -> tuple[uuid.UUID, uuid.UUID]:
    """A draft invoice with one line, optionally issued. Returns (invoice, line)."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    invoice_id = await db.fetchval(
        """INSERT INTO public.sales_invoices (company_id, customer_id, customer_name, created_by)
           VALUES ($1, $2, 'Probe Customer', $3) RETURNING id""",
        tenants.company_a,
        customer_id,
        tenants.solo_user,
    )
    item_id = await db.fetchval(
        """INSERT INTO public.sales_invoice_items
               (sales_invoice_id, product_id, item_code, item_description)
           SELECT $2, p.id, 'PROBE-1', 'probe line'
             FROM public.products p WHERE p.company_id = $1 LIMIT 1
           RETURNING id""",
        tenants.company_a,
        invoice_id,
    )
    assert invoice_id is not None and item_id is not None
    if issue:
        await db.execute(
            "UPDATE public.sales_invoices SET status = 'issued' WHERE id = $1", invoice_id
        )
        assert (
            await db.fetchval("SELECT status FROM public.sales_invoices WHERE id = $1", invoice_id)
            == "issued"
        ), "seed failed to issue the invoice, the test would prove nothing"
    assert isinstance(invoice_id, uuid.UUID)
    return invoice_id, item_id


async def seed_credit_note(
    db: asyncpg.Connection, tenants: Tenants, *, confirm: bool = False
) -> uuid.UUID:
    """A credit note through the inherited chain: bin, return order, note."""
    customer_id = await db.fetchval(
        "INSERT INTO public.customers (company_id, name) VALUES ($1, 'Probe Customer')"
        " RETURNING id",
        tenants.company_a,
    )
    bin_id = await db.fetchval(
        """INSERT INTO public.warehouse_bins (company_id, wh_bin_code, bin_name)
           VALUES ($1, 'LDN1', 'Main') RETURNING id""",
        tenants.company_a,
    )
    rso_id = await db.fetchval(
        """INSERT INTO public.return_order_header
               (company_id, rso_number, customer_id, customer_name, invoice_id,
                invoice_number, invoice_date, reason_for_credit, created_by)
           VALUES ($1, 'RSO-PROBE', $2, 'Probe Customer', gen_random_uuid(),
                   'INV-PROBE', current_date, 'Others', $3) RETURNING id""",
        tenants.company_a,
        customer_id,
        tenants.solo_user,
    )
    cn_id = await db.fetchval(
        """INSERT INTO public.credit_notes
               (company_id, cn_number, rso_id, status, default_warehouse_id,
                customer_id, customer_name, created_by)
           VALUES ($1, 'CN-PROBE', $2, 'Draft', $3, $4, 'Probe Customer', $5)
           RETURNING id""",
        tenants.company_a,
        rso_id,
        bin_id,
        customer_id,
        tenants.solo_user,
    )
    assert cn_id is not None
    if confirm:
        await db.execute("UPDATE public.credit_notes SET status = 'Confirmed' WHERE id = $1", cn_id)
        assert (
            await db.fetchval("SELECT status FROM public.credit_notes WHERE id = $1", cn_id)
            == "Confirmed"
        ), "seed failed to confirm the credit note"
    assert isinstance(cn_id, uuid.UUID)
    return cn_id


# --- drafts live: the refusal must be about status, not about the trigger ----


async def test_a_draft_is_editable(db: asyncpg.Connection, tenants: Tenants) -> None:
    invoice_id, _ = await seed_invoice(db, tenants)
    await db.execute(
        "UPDATE public.sales_invoices SET notes = 'still drafting' WHERE id = $1", invoice_id
    )
    assert (
        await db.fetchval("SELECT notes FROM public.sales_invoices WHERE id = $1", invoice_id)
        == "still drafting"
    )


async def test_a_draft_line_is_editable(db: asyncpg.Connection, tenants: Tenants) -> None:
    _, item_id = await seed_invoice(db, tenants)
    await db.execute(
        "UPDATE public.sales_invoice_items SET quantity_invoiced = 3 WHERE id = $1", item_id
    )
    assert (
        await db.fetchval(
            "SELECT quantity_invoiced FROM public.sales_invoice_items WHERE id = $1", item_id
        )
        == 3
    )


async def test_an_abandoned_draft_can_be_deleted(db: asyncpg.Connection, tenants: Tenants) -> None:
    invoice_id, _ = await seed_invoice(db, tenants)
    await db.execute("DELETE FROM public.sales_invoices WHERE id = $1", invoice_id)
    assert (
        await db.fetchval("SELECT count(*) FROM public.sales_invoices WHERE id = $1", invoice_id)
        == 0
    )


async def test_issuing_works(db: asyncpg.Connection, tenants: Tenants) -> None:
    """The allowed path stays allowed. A protection that also blocks the
    transition it exists to protect gets removed by whoever hits it at 2am."""
    invoice_id, _ = await seed_invoice(db, tenants)
    await db.execute("UPDATE public.sales_invoices SET status = 'issued' WHERE id = $1", invoice_id)
    assert (
        await db.fetchval("SELECT status FROM public.sales_invoices WHERE id = $1", invoice_id)
        == "issued"
    )


# --- issued is frozen, including for the owner -------------------------------


async def test_an_issued_invoice_refuses_an_update(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    invoice_id, _ = await seed_invoice(db, tenants, issue=True)
    assert (
        await db.fetchval("SELECT count(*) FROM public.sales_invoices WHERE id = $1", invoice_id)
        == 1
    ), "no row to protect, so this test would pass against no protection at all"
    with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
        async with db.transaction():
            await db.execute(
                "UPDATE public.sales_invoices SET notes = 'tampered' WHERE id = $1", invoice_id
            )
    assert (
        await db.fetchval("SELECT notes FROM public.sales_invoices WHERE id = $1", invoice_id)
        is None
    )


async def test_an_issued_invoice_refuses_the_backtrack(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The transition is one-way (SPEC 3.1). Un-issuing is a rewrite, so the
    same refusal catches it without a rule of its own."""
    invoice_id, _ = await seed_invoice(db, tenants, issue=True)
    with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
        async with db.transaction():
            await db.execute(
                "UPDATE public.sales_invoices SET status = 'draft' WHERE id = $1", invoice_id
            )
    assert (
        await db.fetchval("SELECT status FROM public.sales_invoices WHERE id = $1", invoice_id)
        == "issued"
    )


async def test_an_issued_invoice_refuses_a_delete(db: asyncpg.Connection, tenants: Tenants) -> None:
    invoice_id, _ = await seed_invoice(db, tenants, issue=True)
    assert (
        await db.fetchval("SELECT count(*) FROM public.sales_invoices WHERE id = $1", invoice_id)
        == 1
    )
    with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
        async with db.transaction():
            await db.execute("DELETE FROM public.sales_invoices WHERE id = $1", invoice_id)
    assert (
        await db.fetchval("SELECT count(*) FROM public.sales_invoices WHERE id = $1", invoice_id)
        == 1
    )


async def test_the_refusal_names_the_table_and_the_way_out(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """N6: an error saying only 'not permitted' leaves the reader guessing."""
    invoice_id, _ = await seed_invoice(db, tenants, issue=True)
    try:
        async with db.transaction():
            await db.execute(
                "UPDATE public.sales_invoices SET notes = 'x' WHERE id = $1", invoice_id
            )
    except asyncpg.PostgresError as exc:
        message = str(exc)
    else:
        pytest.fail("the update was not refused")
    assert "sales_invoices" in message
    assert "UPDATE" in message
    assert "credit note" in message


# --- the lines, frozen through their parent ----------------------------------


@pytest.mark.parametrize("operation", ["update", "delete", "insert"])
async def test_lines_of_an_issued_invoice_are_frozen(
    db: asyncpg.Connection, tenants: Tenants, operation: str
) -> None:
    invoice_id, item_id = await seed_invoice(db, tenants, issue=True)
    assert (
        await db.fetchval("SELECT count(*) FROM public.sales_invoice_items WHERE id = $1", item_id)
        == 1
    ), "no row to protect, so this test would pass against no protection at all"
    if operation == "update":
        statement = "UPDATE public.sales_invoice_items SET quantity_invoiced = 99 WHERE id = $1"
    elif operation == "delete":
        statement = "DELETE FROM public.sales_invoice_items WHERE id = $1"
    else:
        statement = (
            "INSERT INTO public.sales_invoice_items"
            " (sales_invoice_id, product_id, item_code, item_description)"
            " SELECT $2, p.id, 'PROBE-2', 'smuggled line'"
            " FROM public.products p WHERE p.company_id = $1 LIMIT 1"
        )
        with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
            async with db.transaction():
                await db.execute(statement, tenants.company_a, invoice_id)
        return
    with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
        async with db.transaction():
            await db.execute(statement, item_id)
    if operation == "update":
        assert (
            await db.fetchval(
                "SELECT quantity_invoiced FROM public.sales_invoice_items WHERE id = $1", item_id
            )
            == 0
        ), "the refusal must leave the row as it was"


# --- credit notes: Confirmed is the frozen state ------------------------------


async def test_a_draft_credit_note_is_editable(db: asyncpg.Connection, tenants: Tenants) -> None:
    cn_id = await seed_credit_note(db, tenants)
    await db.execute("UPDATE public.credit_notes SET notes = 'still drafting' WHERE id = $1", cn_id)
    assert await db.fetchval("SELECT notes FROM public.credit_notes WHERE id = $1", cn_id) == (
        "still drafting"
    )


async def test_a_confirmed_credit_note_refuses_an_update(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    cn_id = await seed_credit_note(db, tenants, confirm=True)
    assert (
        await db.fetchval("SELECT count(*) FROM public.credit_notes WHERE id = $1", cn_id) == 1
    ), "no row to protect, so this test would pass against no protection at all"
    with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
        async with db.transaction():
            await db.execute("UPDATE public.credit_notes SET total_amount = 1 WHERE id = $1", cn_id)


async def test_a_confirmed_credit_note_refuses_a_delete(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    cn_id = await seed_credit_note(db, tenants, confirm=True)
    assert await db.fetchval("SELECT count(*) FROM public.credit_notes WHERE id = $1", cn_id) == 1
    with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
        async with db.transaction():
            await db.execute("DELETE FROM public.credit_notes WHERE id = $1", cn_id)
    assert await db.fetchval("SELECT count(*) FROM public.credit_notes WHERE id = $1", cn_id) == 1


# --- the boundary for a signed-in user, not only the owner --------------------


async def test_the_refusal_holds_for_a_signed_in_user(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The trigger binds every role. This proves it for one that is not the
    owner; the tests above prove it for the owner, who is the harder case."""
    invoice_id, _ = await seed_invoice(db, tenants, issue=True)
    async with db.transaction():
        await act_as(db, tenants.solo_user, tenants.company_a)
        with pytest.raises(asyncpg.PostgresError, match=REFUSAL):
            async with db.transaction():
                await db.execute(
                    "UPDATE public.sales_invoices SET notes = 'tampered' WHERE id = $1",
                    invoice_id,
                )
