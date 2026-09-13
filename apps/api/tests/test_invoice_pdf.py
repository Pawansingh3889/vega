"""The printed invoice, and the property that matters most about it.

#37: "The PDF shows the same figures the UBL output carries. A document and its
machine-readable twin disagreeing is worse than either being wrong alone."

That is not a thing you get by being careful twice. Both renderings take the
same `Invoice` and go through the same `service.resolve`, and the first test
below is the one that would notice if that ever stopped being true.
"""

from __future__ import annotations

import re
from dataclasses import replace
from datetime import date
from decimal import Decimal
from xml.etree.ElementTree import fromstring

from vega_api.modules.einvoice import repository, service
from vega_api.modules.einvoice.contract import UblError

from .test_ubl_output import SELLER, TREATMENTS, _invoice, _line

CBC = "{urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2}"
CAC = "{urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2}"

MIXED = [
    _line(1, "STD", "20.00", "100.00", "20.00"),
    _line(2, "RED", "5.00", "80.00", "4.00"),
    _line(3, "ZER", "0.00", "40.00", "0.00"),
]


def _html(invoice: object) -> str:
    result = service.build_html(invoice, TREATMENTS)  # type: ignore[arg-type]
    assert not isinstance(result, UblError), f"expected HTML, got {result}"
    return result


def _amounts(text: str) -> set[str]:
    """Every money-shaped string in a document, without its currency."""
    return set(re.findall(r"\d+\.\d{2}", text))


# --- the one that matters -------------------------------------------------


def test_the_pdf_and_the_ubl_show_the_same_figures() -> None:
    """#37's second acceptance item, asserted rather than intended."""
    invoice = _invoice(MIXED)

    xml = service.build(invoice, TREATMENTS)
    assert isinstance(xml, str)
    html = _html(invoice)

    root = fromstring(xml)
    ubl_amounts = {
        node.text for node in root.iter() if node.text and re.fullmatch(r"\d+\.\d{2}", node.text)
    }

    missing = ubl_amounts - _amounts(html)
    assert not missing, f"figures in the UBL that the PDF does not show: {sorted(missing)}"


def test_both_renderings_refuse_the_same_invoices() -> None:
    """A PDF that renders where the UBL is refused would be a document the
    customer can act on and the tax authority cannot."""
    cases = [
        (_invoice([]), UblError.NO_LINES),
        (_invoice([_line(1, "MADE_UP", "20.00", "100.00", "20.00")]), UblError.UNKNOWN_TREATMENT),
        (
            _invoice(MIXED, seller=replace(SELLER, vat_number=None, xi_vat_number=None)),
            UblError.SELLER_NOT_REGISTERED,
        ),
        (
            _invoice(
                [_line(1, "XI_ICS", "0.00", "100.00", "0.00")],
                seller=replace(SELLER, xi_vat_number=None),
            ),
            UblError.MISSING_XI_VAT,
        ),
    ]

    for invoice, expected in cases:
        assert service.build(invoice, TREATMENTS) is expected
        assert service.build_html(invoice, TREATMENTS) is expected


# --- the currency face ----------------------------------------------------


def test_a_eur_invoice_shows_sterling_and_the_rate_beneath() -> None:
    """SPEC section 1 and #37. HMRC wants the sterling equivalent and the rate
    on the invoice itself, so this is what makes it a valid VAT invoice."""
    html = _html(
        _invoice(
            MIXED,
            currency="EUR",
            fx_rate=Decimal("0.85"),
            fx_rate_date=date(2026, 9, 4),
        )
    )

    assert "EUR 244.00" in html, "the euro total is on the face"
    assert "GBP 207.40" in html, "the sterling equivalent beneath it"
    assert "0.85" in html and "2026-09-04" in html, "the rate and its date"


def test_a_gbp_invoice_shows_no_conversion_block() -> None:
    """A rate of 1.0 printed on a domestic invoice is noise that reads as a
    foreign-currency document."""
    html = _html(_invoice(MIXED))

    assert "Converted at" not in html
    assert "Total in GBP" not in html


def test_the_stored_rate_is_used_never_a_recomputed_one() -> None:
    """Changing only the stored rate must change only the sterling figures."""
    html = _html(
        _invoice(MIXED, currency="EUR", fx_rate=Decimal("0.50"), fx_rate_date=date(2026, 9, 4))
    )

    assert "GBP 122.00" in html, "244.00 at 0.50"


# --- things the paper document must say -----------------------------------


def test_a_reverse_charge_invoice_says_so_in_words() -> None:
    """The customer accounts for the VAT and cannot learn that from a zero."""
    html = _html(_invoice([_line(1, "DRC", "0.00", "100.00", "0.00")]))

    assert "Reverse charge" in html
    assert "customer to account for VAT" in html


def test_an_ordinary_invoice_carries_no_reverse_charge_note() -> None:
    assert "customer to account for VAT" not in _html(_invoice(MIXED))


def test_an_eu_supply_from_northern_ireland_prints_the_xi_number() -> None:
    """XI_ICS, the intra-community supply. HMRC ties the XI prefix to supplies
    to an EU customer, not to Northern Ireland trade generally (#121)."""
    html = _html(_invoice([_line(1, "XI_ICS", "0.00", "100.00", "0.00")]))

    assert "VAT XI123456789" in html
    assert "GB123456789" not in html


def test_a_domestic_ni_invoice_prints_the_gb_number() -> None:
    """The paper document must agree with the UBL about which registration
    filed it, and #121 had both of them wrong the same way."""
    html = _html(_invoice([_line(1, "XI_STD", "20.00", "100.00", "20.00")]))

    assert "VAT GB123456789" in html
    assert "XI123456789" not in html


def test_a_description_containing_markup_is_escaped() -> None:
    """Item descriptions are user input and this builds markup with f-strings."""
    hostile = replace(MIXED[0], description="<script>alert(1)</script> & co")

    html = _html(_invoice([hostile]))

    assert "<script>" not in html
    assert "&lt;script&gt;" in html
    assert "&amp; co" in html


# --- the renderer ---------------------------------------------------------


def test_the_html_renders_to_a_pdf() -> None:
    pdf = repository.html_to_pdf(_html(_invoice(MIXED)))

    assert pdf.startswith(b"%PDF-")
    assert len(pdf) > 1000, "a PDF this small would be an empty page"
