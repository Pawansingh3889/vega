"""All the VAT module's I/O. Nothing here decides anything."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import UUID

import asyncpg

from .contract import TaxLine, Treatment


async def load_treatments(conn: asyncpg.Connection) -> dict[str, Treatment]:
    """Reference data, identical for every tenant.

    charges_output_vat is derived here rather than stored: a treatment charges
    output VAT when it is neither a reverse charge nor outside the scope, and
    its current rate is above zero. Storing it as a column would let it drift
    away from the rate it is supposed to follow.
    """
    rows = await conn.fetch(
        """
        SELECT t.code,
               t.is_reverse_charge,
               t.is_northern_ireland,
               t.is_ec_sales_list,
               COALESCE(r.rate, 0) AS rate
          FROM public.vat_treatments t
          LEFT JOIN public.vat_rates r
                 ON r.treatment_code = t.code
                AND r.effective_to IS NULL
        """
    )
    treatments: dict[str, Treatment] = {}
    for row in rows:
        outside_scope = row["code"] == "OUT"
        treatments[row["code"]] = Treatment(
            code=row["code"],
            charges_output_vat=(
                Decimal(row["rate"]) > 0 and not row["is_reverse_charge"] and not outside_scope
            ),
            is_reverse_charge=row["is_reverse_charge"],
            is_northern_ireland=row["is_northern_ireland"],
            is_ec_sales_list=row["is_ec_sales_list"],
            outside_scope=outside_scope,
        )
    return treatments


async def load_period_lines(
    conn: asyncpg.Connection, period_start: date, period_end: date
) -> list[TaxLine]:
    """Every taxable line in the period, sales and purchases.

    No company filter. That is deliberate: the connection is already acting as
    the caller with RLS applied, so the company boundary is enforced by the same
    policies the browser gets. Adding a WHERE company_id here would be a second
    implementation of tenancy, free to drift away from the first.
    """
    sales = await conn.fetch(
        """
        SELECT i.vat_treatment_code AS treatment_code,
               i.line_subtotal      AS net,
               i.vat_amount         AS vat
          FROM public.sales_invoice_items i
          JOIN public.sales_invoices inv ON inv.id = i.sales_invoice_id
         WHERE inv.invoice_date BETWEEN $1 AND $2
        """,
        period_start,
        period_end,
    )
    purchases = await conn.fetch(
        """
        SELECT p.vat_treatment_code AS treatment_code,
               p.line_subtotal      AS net,
               p.vat_amount         AS vat
          FROM public.purchase_order_items p
          JOIN public.purchase_orders po ON po.id = p.purchase_order_id
         WHERE po.order_date BETWEEN $1 AND $2
        """,
        period_start,
        period_end,
    )

    lines = [
        TaxLine(
            treatment_code=r["treatment_code"],
            net=Decimal(r["net"] or 0),
            vat=Decimal(r["vat"] or 0),
            is_sale=True,
        )
        for r in sales
    ]
    lines += [
        TaxLine(
            treatment_code=r["treatment_code"],
            net=Decimal(r["net"] or 0),
            vat=Decimal(r["vat"] or 0),
            is_sale=False,
        )
        for r in purchases
    ]
    return lines


async def current_company(conn: asyncpg.Connection) -> UUID | None:
    """Which company this session resolved to, or None if it chose nothing."""
    value = await conn.fetchval("SELECT public.current_company_id()")
    if value is None:
        return None
    # asyncpg types fetchval as Any. Narrow rather than cast, so a driver that
    # ever hands back something else fails here instead of three layers up.
    assert isinstance(value, UUID), f"current_company_id() returned {type(value)!r}"
    return value
