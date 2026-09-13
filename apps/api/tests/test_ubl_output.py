"""PEPPOL BIS Billing 3.0 emission, and the three ways a category collides.

#27 names two traps and the database holds a third. All of them have the same
shape: the EN 16931 category does not identify the treatment, so a document
built from the category alone is wrong in a way that still looks like a
document.

    RED, STD and XI_STD  ->  S     told apart by the rate
    DRC and ERC          ->  AE    told apart by the exemption reason
    ZER and XI_ZER       ->  Z     told apart by the party identifier

These tests are against the pure builder, so they need no database. That is
the point of `service.py` being pure: a filed tax figure is checkable without
a container.
"""

from __future__ import annotations

from dataclasses import replace
from datetime import date
from decimal import Decimal
from xml.etree.ElementTree import fromstring

import pytest

from vega_api.modules.einvoice import service
from vega_api.modules.einvoice.contract import Invoice, Line, Party, Treatment, UblError

CBC = "{urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2}"
CAC = "{urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2}"

# code, EN 16931 category, reverse charge, northern ireland, EC sales list, rate.
# The flags mirror the live vat_treatments rows: only XI_ICS is both NI and on
# the EC Sales List, which is what earns the XI VAT number (#121).
TREATMENTS = {
    "STD": Treatment("STD", "S", False, False, False, Decimal("20.00")),
    "RED": Treatment("RED", "S", False, False, False, Decimal("5.00")),
    "ZER": Treatment("ZER", "Z", False, False, False, Decimal("0.00")),
    "DRC": Treatment("DRC", "AE", True, False, False, Decimal("0.00")),
    "ERC": Treatment("ERC", "AE", True, False, True, Decimal("0.00")),
    "XI_STD": Treatment("XI_STD", "S", False, True, False, Decimal("20.00")),
    "XI_ZER": Treatment("XI_ZER", "Z", False, True, False, Decimal("0.00")),
    "XI_ICS": Treatment("XI_ICS", "K", False, True, True, Decimal("0.00")),
}

SELLER = Party(
    name="Vega Foods Ltd",
    vat_number="GB123456789",
    xi_vat_number="XI123456789",
    company_registration_number="12345678",
    address_line1="1 Mill Lane",
    address_line2=None,
    city="Birmingham",
    postcode="B1 1AA",
    country="GB",
)
BUYER = Party(
    name="Acme Wholesale BV",
    vat_number="NL987654321B01",
    xi_vat_number=None,
    company_registration_number=None,
    address_line1="9 Kade",
    address_line2=None,
    city="Rotterdam",
    postcode="3011 AA",
    country="NL",
)


def _line(number: int, code: str, rate: str, net: str, vat: str) -> Line:
    return Line(
        number=number,
        description=f"Item {number}",
        item_code=f"SKU-{number}",
        commodity_code="19053199",
        quantity=Decimal("1"),
        unit_code="C62",
        unit_price=Decimal(net),
        net_amount=Decimal(net),
        treatment_code=code,
        vat_rate=Decimal(rate),
        vat_amount=Decimal(vat),
    )


def _invoice(lines: list[Line], **over: object) -> Invoice:
    net = sum((line.net_amount for line in lines), Decimal(0))
    vat = sum((line.vat_amount for line in lines), Decimal(0))
    fields: dict[str, object] = {
        "number": "INV-2026-000123",
        "issue_date": date(2026, 9, 7),
        "due_date": date(2026, 10, 7),
        "currency": "GBP",
        "fx_rate": None,
        "fx_rate_date": None,
        "seller": SELLER,
        "buyer": BUYER,
        "lines": tuple(lines),
        "net_total": net,
        "vat_total": vat,
        "gross_total": net + vat,
        "buyer_reference": "PO-77",
    }
    fields.update(over)
    return Invoice(**fields)  # type: ignore[arg-type]


def _build(invoice: Invoice) -> str:
    result = service.build(invoice, TREATMENTS)
    assert not isinstance(result, UblError), f"expected XML, got {result}"
    return result


def _subtotals(xml: str) -> list[tuple[str, str, str | None]]:
    """(category, percent, exemption reason) for each document-level subtotal."""
    root = fromstring(xml)
    out = []
    for subtotal in root.findall(f"{CAC}TaxTotal/{CAC}TaxSubtotal"):
        category = subtotal.find(f"{CAC}TaxCategory")
        assert category is not None
        ident = category.find(f"{CBC}ID")
        percent = category.find(f"{CBC}Percent")
        reason = category.find(f"{CBC}TaxExemptionReason")
        assert ident is not None and percent is not None
        out.append(
            (ident.text or "", percent.text or "", reason.text if reason is not None else None)
        )
    return out


# --- the collisions -------------------------------------------------------


def test_standard_and_reduced_share_category_s_and_are_split_by_rate() -> None:
    """The first trap in #27. One category, two subtotals, two percents.

    Merging these into one S subtotal is the failure mode: its Percent cannot
    be right for both, and the document validates as a single rate applied to
    money that was taxed at two.
    """
    xml = _build(
        _invoice(
            [
                _line(1, "STD", "20.00", "100.00", "20.00"),
                _line(2, "RED", "5.00", "100.00", "5.00"),
            ]
        )
    )

    subtotals = _subtotals(xml)

    assert [s[0] for s in subtotals] == ["S", "S"], "both must stay category S"
    assert sorted(s[1] for s in subtotals) == ["20.00", "5.00"]


def test_a_reduced_rate_never_gets_a_category_of_its_own() -> None:
    """Stated separately because it is the mistake, not the fix.

    An implementation that invents a category for the reduced rate produces a
    document that fails validation, and the failure is a long way from the
    line that caused it.
    """
    xml = _build(_invoice([_line(1, "RED", "5.00", "100.00", "5.00")]))

    assert [s[0] for s in _subtotals(xml)] == ["S"]


def test_domestic_and_eu_reverse_charge_share_ae_and_differ_by_reason() -> None:
    """The second trap in #27. DRC and ERC are both AE."""
    xml = _build(
        _invoice(
            [
                _line(1, "DRC", "0.00", "100.00", "0.00"),
                _line(2, "ERC", "0.00", "200.00", "0.00"),
            ]
        )
    )

    subtotals = _subtotals(xml)

    assert [s[0] for s in subtotals] == ["AE", "AE"]
    assert all(s[2] == "Reverse charge" for s in subtotals), "AE needs a reason (BT-121)"


def test_reverse_charge_lines_are_not_merged_into_one_subtotal() -> None:
    """They feed different VAT return boxes, so they stay separable."""
    xml = _build(
        _invoice(
            [
                _line(1, "DRC", "0.00", "100.00", "0.00"),
                _line(2, "ERC", "0.00", "200.00", "0.00"),
            ]
        )
    )

    root = fromstring(xml)
    taxable = [
        node.text or ""
        for node in root.findall(f"{CAC}TaxTotal/{CAC}TaxSubtotal/{CBC}TaxableAmount")
    ]
    assert sorted(taxable) == ["100.00", "200.00"]


# --- Northern Ireland -----------------------------------------------------


def test_an_eu_supply_from_northern_ireland_is_issued_under_the_xi_number() -> None:
    """#27: it takes the category its treatment implies, and is told apart by
    the endpoint identifier.

    XI_ICS, the intra-community supply, because HMRC ties the XI prefix to
    supplies to an EU customer rather than to Northern Ireland trade generally.
    """
    xml = _build(_invoice([_line(1, "XI_ICS", "0.00", "100.00", "0.00")]))

    root = fromstring(xml)
    endpoint = root.find(f"{CAC}AccountingSupplierParty/{CAC}Party/{CBC}EndpointID")
    assert endpoint is not None
    assert endpoint.text == "XI123456789"
    assert [s[0] for s in _subtotals(xml)] == ["K"], "the category its treatment implies"


def test_a_gb_supply_is_issued_under_the_gb_number() -> None:
    xml = _build(_invoice([_line(1, "STD", "20.00", "100.00", "20.00")]))

    root = fromstring(xml)
    endpoint = root.find(f"{CAC}AccountingSupplierParty/{CAC}Party/{CBC}EndpointID")
    assert endpoint is not None
    assert endpoint.text == "GB123456789"


def test_an_eu_supply_from_ni_without_an_xi_number_is_refused() -> None:
    """The document would claim an EU supply from a party that cannot make one."""
    seller = replace(SELLER, xi_vat_number=None)

    result = service.build(
        _invoice([_line(1, "XI_ICS", "0.00", "100.00", "0.00")], seller=seller),
        TREATMENTS,
    )

    assert result is UblError.MISSING_XI_VAT


def test_a_domestic_ni_invoice_uses_the_gb_number_not_the_xi_one() -> None:
    """#121. HMRC ties the XI prefix to supplies to an EU customer, and says so
    explicitly as being *in addition to* what a normal invoice to a Northern
    Ireland customer carries. A domestic NI sale is invoiced under GB.
    """
    xml = _build(_invoice([_line(1, "XI_STD", "20.00", "100.00", "20.00")]))

    root = fromstring(xml)
    endpoint = root.find(f"{CAC}AccountingSupplierParty/{CAC}Party/{CBC}EndpointID")
    assert endpoint is not None
    assert endpoint.text == "GB123456789"


def test_a_domestic_ni_invoice_is_not_refused_for_lacking_an_xi_number() -> None:
    """An NI company with no XI number must still be able to invoice its
    neighbours. Refusing that was the other half of #121."""
    seller = replace(SELLER, xi_vat_number=None)

    result = service.build(
        _invoice([_line(1, "XI_STD", "20.00", "100.00", "20.00")], seller=seller),
        TREATMENTS,
    )

    assert not isinstance(result, UblError)


# --- currency -------------------------------------------------------------


def test_a_gbp_invoice_carries_no_tax_currency_code() -> None:
    """BT-6 present and equal to the document currency is a validation failure,
    not a harmless repetition."""
    xml = _build(_invoice([_line(1, "STD", "20.00", "100.00", "20.00")]))
    root = fromstring(xml)

    assert root.find(f"{CBC}TaxCurrencyCode") is None


def test_a_eur_invoice_carries_the_vat_total_in_sterling_at_the_stored_rate() -> None:
    """The rate stored on the document at issue, never today's.

    A reprint next year has to show the same sterling figure as the original,
    which is why #89 froze the rate on the document and why nothing here
    re-fetches one.
    """
    xml = _build(
        _invoice(
            [_line(1, "STD", "20.00", "100.00", "20.00")],
            currency="EUR",
            fx_rate=Decimal("0.85"),
            fx_rate_date=date(2026, 9, 7),
        )
    )
    root = fromstring(xml)

    code = root.find(f"{CBC}TaxCurrencyCode")
    assert code is not None and code.text == "GBP"

    totals = root.findall(f"{CAC}TaxTotal/{CBC}TaxAmount")
    assert len(totals) == 2, "one in the invoice currency, one in sterling"
    assert totals[0].get("currencyID") == "EUR" and totals[0].text == "20.00"
    assert totals[1].get("currencyID") == "GBP" and totals[1].text == "17.00"


# --- refusals -------------------------------------------------------------


def test_an_unknown_treatment_is_refused_rather_than_defaulted() -> None:
    """Guessing a category here files the wrong VAT."""
    result = service.build(_invoice([_line(1, "MADE_UP", "20.00", "100.00", "20.00")]), TREATMENTS)

    assert result is UblError.UNKNOWN_TREATMENT


def test_an_invoice_with_no_lines_is_refused() -> None:
    assert service.build(_invoice([]), TREATMENTS) is UblError.NO_LINES


def test_a_seller_with_no_vat_number_is_refused() -> None:
    """EN 16931 BR-CO-9."""
    seller = replace(SELLER, vat_number=None, xi_vat_number=None)

    result = service.build(
        _invoice([_line(1, "STD", "20.00", "100.00", "20.00")], seller=seller), TREATMENTS
    )

    assert result is UblError.SELLER_NOT_REGISTERED


# --- shape ----------------------------------------------------------------


@pytest.mark.parametrize(
    ("tag", "expected"),
    [
        ("CustomizationID", service.CUSTOMIZATION),
        ("ProfileID", service.PROFILE),
        ("InvoiceTypeCode", "380"),
        ("ID", "INV-2026-000123"),
        ("IssueDate", "2026-09-07"),
    ],
)
def test_the_document_header_identifies_itself_as_peppol(tag: str, expected: str) -> None:
    xml = _build(_invoice([_line(1, "STD", "20.00", "100.00", "20.00")]))
    root = fromstring(xml)

    node = root.find(f"{CBC}{tag}")
    assert node is not None and node.text == expected


def test_money_rounds_half_up_not_bankers() -> None:
    """Python rounds 0.125 to 0.12. HMRC and every accountant expect 0.13.

    A validator compares the document total against the sum of its lines, so
    the rounding here has to match the one that produced them.
    """
    assert service._money(Decimal("0.125")) == "0.13"
    assert service._money(Decimal("0.135")) == "0.14"
