"""All the einvoice module's I/O. Nothing here decides anything."""

from __future__ import annotations

from decimal import Decimal
from uuid import UUID

import asyncpg

from .contract import Invoice, Line, Party, Treatment


async def load_treatments(conn: asyncpg.Connection) -> dict[str, Treatment]:
    """The EN 16931 category per treatment, as the database defines it.

    SPEC.md 2.4 owns this mapping. Reading it rather than hardcoding it is what
    stops a category being invented at the call site, which is the failure
    #27 opens by warning about.
    """
    rows = await conn.fetch(
        """
        SELECT t.code,
               t.en16931_category,
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
    return {
        row["code"]: Treatment(
            code=row["code"],
            category=row["en16931_category"],
            is_reverse_charge=row["is_reverse_charge"],
            is_northern_ireland=row["is_northern_ireland"],
            is_ec_sales_list=row["is_ec_sales_list"],
            rate=Decimal(str(row["rate"])),
        )
        for row in rows
    }


async def load_invoice(conn: asyncpg.Connection, invoice_id: UUID) -> Invoice | None:
    """One issued invoice with its lines and both parties.

    Returns None when the invoice is not visible to this caller. That is RLS
    doing its job, not an error to distinguish: a caller who may not see an
    invoice must not learn whether it exists.
    """
    head = await conn.fetchrow(
        """
        SELECT i.invoice_number,
               i.invoice_date,
               i.due_date,
               i.currency,
               i.fx_rate,
               i.fx_rate_date,
               i.status,
               i.customer_po_reference,
               i.subtotal_amount,
               i.total_amount,
               c.name                        AS seller_name,
               c.vat_number                  AS seller_vat,
               c.xi_vat_number               AS seller_xi_vat,
               c.company_registration_number AS seller_crn,
               c.address_line1               AS seller_address1,
               c.address_line2               AS seller_address2,
               c.city                        AS seller_city,
               c.postcode                    AS seller_postcode,
               COALESCE(c.country, 'GB')     AS seller_country,
               i.customer_name               AS buyer_name
          FROM public.sales_invoices i
          JOIN public.companies c ON c.id = i.company_id
         WHERE i.id = $1
        """,
        invoice_id,
    )
    if head is None:
        return None

    rows = await conn.fetch(
        """
        SELECT item_description,
               item_code,
               commodity_code,
               quantity_invoiced,
               unit_of_measure,
               unit_price,
               line_subtotal,
               vat_treatment_code,
               vat_rate,
               vat_amount
          FROM public.sales_invoice_items
         WHERE sales_invoice_id = $1
         ORDER BY created_at, item_code
        """,
        invoice_id,
    )

    lines = tuple(
        Line(
            number=index,
            description=row["item_description"] or row["item_code"] or "Item",
            item_code=row["item_code"],
            commodity_code=row["commodity_code"],
            quantity=Decimal(str(row["quantity_invoiced"] or 0)),
            # C62 is "one" in UNECE Rec 20. The column is free text and a
            # PEPPOL document needs a code, so an unrecognised unit becomes
            # C62 rather than being passed through and failing validation.
            unit_code=_unit_code(row["unit_of_measure"]),
            unit_price=Decimal(str(row["unit_price"] or 0)),
            net_amount=Decimal(str(row["line_subtotal"] or 0)),
            treatment_code=row["vat_treatment_code"],
            vat_rate=Decimal(str(row["vat_rate"] or 0)),
            vat_amount=Decimal(str(row["vat_amount"] or 0)),
        )
        for index, row in enumerate(rows, start=1)
    )

    net = Decimal(str(head["subtotal_amount"] or 0))
    gross = Decimal(str(head["total_amount"] or 0))

    return Invoice(
        number=head["invoice_number"] or "",
        issue_date=head["invoice_date"],
        due_date=head["due_date"],
        currency=head["currency"] or "GBP",
        fx_rate=Decimal(str(head["fx_rate"])) if head["fx_rate"] is not None else None,
        fx_rate_date=head["fx_rate_date"],
        seller=Party(
            name=head["seller_name"],
            vat_number=head["seller_vat"],
            xi_vat_number=head["seller_xi_vat"],
            company_registration_number=head["seller_crn"],
            address_line1=head["seller_address1"],
            address_line2=head["seller_address2"],
            city=head["seller_city"],
            postcode=head["seller_postcode"],
            country=head["seller_country"],
        ),
        buyer=Party(
            name=head["buyer_name"] or "",
            vat_number=None,
            xi_vat_number=None,
            company_registration_number=None,
            address_line1=None,
            address_line2=None,
            city=None,
            postcode=None,
            country="GB",
        ),
        lines=lines,
        net_total=net,
        vat_total=gross - net,
        gross_total=gross,
        buyer_reference=head["customer_po_reference"],
    )


async def invoice_status(conn: asyncpg.Connection, invoice_id: UUID) -> str | None:
    row = await conn.fetchrow("SELECT status FROM public.sales_invoices WHERE id = $1", invoice_id)
    return None if row is None else str(row["status"])


_UNITS = {
    "each": "C62",
    "ea": "C62",
    "unit": "C62",
    "kg": "KGM",
    "g": "GRM",
    "l": "LTR",
    "ml": "MLT",
    "box": "BX",
    "case": "CS",
    "pallet": "PF",
}


def _unit_code(unit: str | None) -> str:
    return _UNITS.get((unit or "").strip().lower(), "C62")


def html_to_pdf(html: str) -> bytes:
    """Render a self-contained HTML document to PDF bytes.

    Here rather than in `service.py` because rendering touches the filesystem
    for fonts, which is I/O, and `service.py` is the pure one. Keeping the
    document's markup pure is what lets the figures on it be asserted without
    a renderer in the room.

    `base_url` is deliberately not set. Without it WeasyPrint has no base to
    resolve a relative URL against, so a document cannot be made to fetch a
    remote stylesheet or image. Nothing here needs one: the CSS is inline and
    there are no images. See SECURITY.md N4 in spirit, a renderer that can be
    made to make requests is a request forgery waiting for an invoice
    description that contains a tag.
    """
    from weasyprint import HTML

    return bytes(HTML(string=html).write_pdf())
