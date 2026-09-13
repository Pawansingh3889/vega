"""PEPPOL BIS Billing 3.0 e-invoicing.

SPEC.md section 3 picks this format: already the NHS supplier standard and the
most likely shape of any wider UK mandate.

This module only emits. SECURITY.md N4 says all inbound XML is hostile, and
that does not bite yet because nothing here parses a document somebody else
wrote. When receiving lands, the parsing goes behind defusedxml the way
`modules/fx` does it, and the schematron validator stays out of this process
entirely: it is a JVM and belongs in a sandboxed sidecar with no network egress
and no database credentials.
"""

from __future__ import annotations

from uuid import UUID

import asyncpg

from ...common.errors import Result
from . import repository, service
from .contract import Invoice, Line, Party, Treatment, UblError

__all__ = [
    "PERMISSIONS",
    "Invoice",
    "Line",
    "Party",
    "Treatment",
    "UblError",
    "emit_invoice",
    "render_invoice_pdf",
]

PERMISSIONS = {"einvoice.emit": "authenticated"}

_MESSAGES = {
    UblError.NOT_ISSUED: (
        "This invoice is still a draft. Issue it first: a PEPPOL document "
        "needs the invoice number, and a draft does not have one yet."
    ),
    UblError.NO_LINES: "This invoice has no lines, so there is nothing to send.",
    UblError.UNKNOWN_TREATMENT: (
        "A line carries a VAT treatment this system does not define, so its "
        "EN 16931 category cannot be looked up. Fix the line rather than "
        "sending a document with a guessed category."
    ),
    UblError.SELLER_NOT_REGISTERED: (
        "Your company has no VAT number recorded. EN 16931 requires one on "
        "every invoice, so add it in company settings."
    ),
    UblError.MISSING_XI_VAT: (
        "This invoice uses a Northern Ireland VAT treatment, but your company "
        "has no XI VAT number recorded. An NI supply is made under the XI "
        "number and that is what identifies it."
    ),
}

# Only an issued invoice has a number. Drafts are refused rather than emitted
# with a blank, and the status set is read from the lifecycle migration rather
# than assumed here.
_ISSUED = {"issued", "finalized"}


async def emit_invoice(conn: asyncpg.Connection, invoice_id: UUID) -> Result:
    """One issued invoice as a PEPPOL BIS 3.0 UBL document.

    Returns a Result rather than raising, so the route turns a refusal into a
    status code without catching. Every refusal names something a person can
    act on, because the caller is a person about to send a document to a
    customer's accounts system.
    """
    prepared = await _prepare(conn, invoice_id)
    if isinstance(prepared, Result):
        return prepared
    invoice, treatments = prepared

    built = service.build(invoice, treatments)

    if isinstance(built, UblError):
        return Result.err(built.value, _MESSAGES[built])
    return Result.good(built)


async def render_invoice_pdf(conn: asyncpg.Connection, invoice_id: UUID) -> Result:
    """One issued invoice as a PDF, generated on demand and stored nowhere.

    #37 is explicit about not storing it: a saved PDF is a second copy of the
    truth that can drift from the row it came from. Revisit when somebody needs
    a byte-identical reproduction of what was sent, which is a different
    requirement with different rules.

    Refuses on exactly the conditions the UBL refuses on, because both go
    through `service.resolve`.
    """
    prepared = await _prepare(conn, invoice_id)
    if isinstance(prepared, Result):
        return prepared
    invoice, treatments = prepared

    html = service.build_html(invoice, treatments)
    if isinstance(html, UblError):
        return Result.err(html.value, _MESSAGES[html])

    return Result.good(repository.html_to_pdf(html))


async def _prepare(
    conn: asyncpg.Connection, invoice_id: UUID
) -> tuple[Invoice, dict[str, Treatment]] | Result:
    """Load and gate one invoice, or the refusal that stopped it.

    Shared by both renderings so they cannot disagree about which invoices are
    renderable, which would be the same defect as disagreeing about figures.
    """
    status = await repository.invoice_status(conn, invoice_id)
    if status is None:
        # Not visible to this caller. RLS decided that, and this must not
        # distinguish "does not exist" from "not yours".
        return Result.err("not_found", "No such invoice.")
    if status.lower() not in _ISSUED:
        return Result.err(UblError.NOT_ISSUED.value, _MESSAGES[UblError.NOT_ISSUED])

    invoice = await repository.load_invoice(conn, invoice_id)
    if invoice is None:
        return Result.err("not_found", "No such invoice.")

    return invoice, await repository.load_treatments(conn)
