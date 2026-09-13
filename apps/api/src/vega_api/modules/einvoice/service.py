"""Build a PEPPOL BIS Billing 3.0 UBL invoice. Pure: no I/O, no clock.

SPEC.md section 3 picks this format. Everything the builder needs arrives as a
typed `Invoice`, so a document can be produced and asserted in a test without a
database, which is what makes the tax categories checkable at all.

The category is never decided here. It is read from `vat_treatments`
(SPEC.md 2.4) and arrives on each `Treatment`. Deriving it at the call site is
how a reduced rate ends up in its own category and the document fails
validation.
"""

from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal
from html import escape
from xml.etree.ElementTree import Element, SubElement, tostring

from .contract import Invoice, Line, Party, Treatment, UblError

CBC = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
CAC = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
UBL = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"

CUSTOMIZATION = "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
PROFILE = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

# BT-3. 380 is a commercial invoice. Credit notes are a different document type
# and a different root element, so they are not emitted by this function.
INVOICE_TYPE_COMMERCIAL = "380"

FUNCTIONAL_CURRENCY = "GBP"

PENNY = Decimal("0.01")

# BT-121. The reverse charge categories need a reason, and the text differs by
# treatment even though the category does not. Reading it from the code rather
# than the category is the point: DRC and ERC are both AE.
_EXEMPTION_REASONS = {
    "DRC": "Reverse charge",
    "ERC": "Reverse charge",
    "EXM": "Exempt from VAT",
    "EXP": "Export outside the United Kingdom",
    "OUT": "Outside the scope of VAT",
    "XI_ICS": "Intra-Community supply",
}


def _money(amount: Decimal) -> str:
    """Two decimal places, half up.

    Banker's rounding is Python's default and wrong for tax. A validator
    compares totals to the sum of lines, so the rounding used here has to be
    the same one used to compute them.
    """
    return str(amount.quantize(PENNY, rounding=ROUND_HALF_UP))


def _text(parent: Element, ns: str, name: str, value: str, **attrs: str) -> Element:
    node = SubElement(parent, f"{{{ns}}}{name}", attrs)
    node.text = value
    return node


def resolve(invoice: Invoice, treatments: dict[str, Treatment]) -> dict[str, Treatment] | UblError:
    """The checks both renderings share, run once and in one place.

    #37 asks that the PDF show the same figures the UBL carries, and a document
    disagreeing with its machine-readable twin is worse than either being wrong
    alone. Two renderers with their own copy of these rules is exactly how that
    disagreement arrives, so neither has a copy.
    """
    if not invoice.lines:
        return UblError.NO_LINES
    if not invoice.seller.vat_number:
        return UblError.SELLER_NOT_REGISTERED

    used: dict[str, Treatment] = {}
    for line in invoice.lines:
        treatment = treatments.get(line.treatment_code)
        if treatment is None:
            # Deliberately not a skip and not a default. A line whose treatment
            # this module does not recognise cannot be given a category, and
            # inventing one files the wrong VAT.
            return UblError.UNKNOWN_TREATMENT
        used[line.treatment_code] = treatment

    if (
        any(_is_eu_supply_from_northern_ireland(t) for t in used.values())
        and not invoice.seller.xi_vat_number
    ):
        # Only an EU supply needs the XI number. Refusing a domestic Northern
        # Ireland invoice for lacking one, which is what #121 did, blocks a
        # document that never needed it.
        return UblError.MISSING_XI_VAT

    return used


def build(invoice: Invoice, treatments: dict[str, Treatment]) -> str | UblError:
    """Emit one invoice as UBL, or say why it cannot be emitted.

    Returns the error rather than raising, so a caller turns it into a Result
    and an HTTP code without catching. Every refusal is a fact about the data,
    not an exception.
    """
    used = resolve(invoice, treatments)
    if isinstance(used, UblError):
        return used

    root = Element(
        f"{{{UBL}}}Invoice",
        {
            "xmlns:cbc": CBC,
            "xmlns:cac": CAC,
        },
    )
    _text(root, CBC, "CustomizationID", CUSTOMIZATION)
    _text(root, CBC, "ProfileID", PROFILE)
    _text(root, CBC, "ID", invoice.number)
    _text(root, CBC, "IssueDate", invoice.issue_date.isoformat())
    if invoice.due_date is not None:
        _text(root, CBC, "DueDate", invoice.due_date.isoformat())
    _text(root, CBC, "InvoiceTypeCode", INVOICE_TYPE_COMMERCIAL)
    _text(root, CBC, "DocumentCurrencyCode", invoice.currency)

    # BT-6. Only present when the invoice is not already in the currency the
    # tax authority is paid in. Emitting TaxCurrencyCode equal to
    # DocumentCurrencyCode is a validation failure, not a harmless repetition.
    if invoice.currency != FUNCTIONAL_CURRENCY:
        _text(root, CBC, "TaxCurrencyCode", FUNCTIONAL_CURRENCY)

    if invoice.buyer_reference:
        _text(root, CBC, "BuyerReference", invoice.buyer_reference)

    _party(root, CAC, "AccountingSupplierParty", invoice.seller, used, seller=True)
    _party(root, CAC, "AccountingCustomerParty", invoice.buyer, used, seller=False)

    _tax_total(root, invoice, used)
    _totals(root, invoice)
    for line in invoice.lines:
        _line(root, line, used[line.treatment_code], invoice.currency)

    return tostring(root, encoding="unicode", xml_declaration=True)


def _is_eu_supply_from_northern_ireland(treatment: Treatment) -> bool:
    """Whether this supply is the kind that is invoiced under the XI number.

    HMRC, *VAT on movements of goods between Northern Ireland and the EU*:

        If you make supplies to a customer in an EU country, the VAT invoice
        you issue must show the following details IN ADDITION TO the
        information normally required on a VAT invoice issued to a Northern
        Ireland customer. 1. The letters 'XI' ... as a prefix to your VAT
        registration number

    So the XI prefix follows the EU supply, not the Northern Ireland treatment.
    A domestic NI sale is invoiced under the GB number like any other UK sale.

    `is_northern_ireland` alone is too broad and is what #121 was: it put the
    XI number on domestic NI invoices. The conjunction selects XI_ICS, the
    intra-community supply, and nothing else.
    """
    return treatment.is_northern_ireland and treatment.is_ec_sales_list


def _seller_vat(party_vat: str | None, xi_vat: str | None, used: dict[str, Treatment]) -> str:
    """The VAT number this document is issued under.

    An EU supply from Northern Ireland is invoiced under the XI number, and
    that is the thing that distinguishes it. #27: those cases take the category
    their underlying treatment implies and are told apart by the identifier,
    not by a category of their own.
    """
    if any(_is_eu_supply_from_northern_ireland(t) for t in used.values()) and xi_vat:
        return xi_vat
    assert party_vat is not None  # guarded by SELLER_NOT_REGISTERED above
    return party_vat


def _party(
    root: Element,
    ns: str,
    tag: str,
    party: object,
    used: dict[str, Treatment],
    *,
    seller: bool,
) -> None:
    from .contract import Party

    assert isinstance(party, Party)
    wrapper = SubElement(root, f"{{{ns}}}{tag}")
    node = SubElement(wrapper, f"{{{CAC}}}Party")

    vat = _seller_vat(party.vat_number, party.xi_vat_number, used) if seller else party.vat_number
    if vat:
        _text(node, CBC, "EndpointID", vat, schemeID="9932" if vat.startswith("GB") else "9930")

    name_node = SubElement(node, f"{{{CAC}}}PartyName")
    _text(name_node, CBC, "Name", party.name)

    address = SubElement(node, f"{{{CAC}}}PostalAddress")
    if party.address_line1:
        _text(address, CBC, "StreetName", party.address_line1)
    if party.address_line2:
        _text(address, CBC, "AdditionalStreetName", party.address_line2)
    if party.city:
        _text(address, CBC, "CityName", party.city)
    if party.postcode:
        _text(address, CBC, "PostalZone", party.postcode)
    country = SubElement(address, f"{{{CAC}}}Country")
    _text(country, CBC, "IdentificationCode", party.country)

    if vat:
        scheme = SubElement(node, f"{{{CAC}}}PartyTaxScheme")
        _text(scheme, CBC, "CompanyID", vat)
        tax_scheme = SubElement(scheme, f"{{{CAC}}}TaxScheme")
        _text(tax_scheme, CBC, "ID", "VAT")

    legal = SubElement(node, f"{{{CAC}}}PartyLegalEntity")
    _text(legal, CBC, "RegistrationName", party.name)
    if party.company_registration_number:
        _text(legal, CBC, "CompanyID", party.company_registration_number)


def _tax_total(root: Element, invoice: Invoice, used: dict[str, Treatment]) -> None:
    """One TaxSubtotal per category and rate, never per line.

    Grouping by category alone would merge the standard and reduced rates,
    which both carry category S, into one subtotal whose Percent cannot be
    right for both. The rate is what tells them apart, so the key is the pair.
    """
    total = SubElement(root, f"{{{CAC}}}TaxTotal")
    _text(total, CBC, "TaxAmount", _money(invoice.vat_total), currencyID=invoice.currency)

    for category, rate, code, net, vat in vat_breakdown(invoice, used):
        subtotal = SubElement(total, f"{{{CAC}}}TaxSubtotal")
        _text(subtotal, CBC, "TaxableAmount", _money(net), currencyID=invoice.currency)
        _text(subtotal, CBC, "TaxAmount", _money(vat), currencyID=invoice.currency)
        _tax_category(subtotal, category, rate, code)

    if invoice.currency != FUNCTIONAL_CURRENCY and invoice.fx_rate is not None:
        # BT-111. The tax total again in the currency the return is filed in,
        # converted at the rate stored on the document at issue. Never
        # recomputed from today's rate: a reprint next year must show the same
        # sterling figure as the original.
        sterling = SubElement(root, f"{{{CAC}}}TaxTotal")
        _text(
            sterling,
            CBC,
            "TaxAmount",
            _money(invoice.vat_total * invoice.fx_rate),
            currencyID=FUNCTIONAL_CURRENCY,
        )


def vat_breakdown(
    invoice: Invoice, used: dict[str, Treatment]
) -> list[tuple[str, Decimal, str, Decimal, Decimal]]:
    """VAT grouped by category, rate and treatment: the document's tax summary.

    Shared by both renderings, and that is the point rather than tidiness. A UK
    VAT invoice has to show the taxable amount and the VAT for each rate, and
    the UBL carries the same split as TaxSubtotal. Two implementations of this
    grouping is two chances to disagree about a filed figure.

    Grouped by the triple, not by category alone. RED and STD are both category
    S, so a single S group carries a Percent that cannot be right for both.
    """
    groups: dict[tuple[str, Decimal, str], tuple[Decimal, Decimal]] = {}
    for line in invoice.lines:
        treatment = used[line.treatment_code]
        key = (treatment.category, line.vat_rate, line.treatment_code)
        net, vat = groups.get(key, (Decimal(0), Decimal(0)))
        groups[key] = (net + line.net_amount, vat + line.vat_amount)

    return [
        (category, rate, code, net, vat)
        for (category, rate, code), (net, vat) in sorted(groups.items(), key=lambda kv: kv[0][:2])
    ]


def _tax_category(parent: Element, category: str, rate: Decimal, code: str) -> None:
    node = SubElement(parent, f"{{{CAC}}}TaxCategory")
    _text(node, CBC, "ID", category)
    _text(node, CBC, "Percent", _money(rate))
    reason = _EXEMPTION_REASONS.get(code)
    if reason is not None:
        _text(node, CBC, "TaxExemptionReason", reason)
    scheme = SubElement(node, f"{{{CAC}}}TaxScheme")
    _text(scheme, CBC, "ID", "VAT")


def _totals(root: Element, invoice: Invoice) -> None:
    node = SubElement(root, f"{{{CAC}}}LegalMonetaryTotal")
    for tag in ("LineExtensionAmount", "TaxExclusiveAmount"):
        _text(node, CBC, tag, _money(invoice.net_total), currencyID=invoice.currency)
    for tag in ("TaxInclusiveAmount", "PayableAmount"):
        _text(node, CBC, tag, _money(invoice.gross_total), currencyID=invoice.currency)


def _line(root: Element, line: Line, treatment: Treatment, currency: str) -> None:
    node = SubElement(root, f"{{{CAC}}}InvoiceLine")
    _text(node, CBC, "ID", str(line.number))
    _text(node, CBC, "InvoicedQuantity", str(line.quantity), unitCode=line.unit_code)
    _text(node, CBC, "LineExtensionAmount", _money(line.net_amount), currencyID=currency)

    item = SubElement(node, f"{{{CAC}}}Item")
    _text(item, CBC, "Name", line.description)
    if line.item_code:
        ident = SubElement(item, f"{{{CAC}}}SellersItemIdentification")
        _text(ident, CBC, "ID", line.item_code)
    if line.commodity_code:
        classification = SubElement(item, f"{{{CAC}}}CommodityClassification")
        _text(classification, CBC, "ItemClassificationCode", line.commodity_code, listID="HS")
    _tax_category(item, treatment.category, line.vat_rate, line.treatment_code)
    # ClassifiedTaxCategory is the line-level element name, not TaxCategory.
    item[-1].tag = f"{{{CAC}}}ClassifiedTaxCategory"

    price = SubElement(node, f"{{{CAC}}}Price")
    _text(price, CBC, "PriceAmount", _money(line.unit_price), currencyID=currency)


# --- the human-readable document ------------------------------------------
#
# SPEC.md 3.4: HTML rendered server side, never assembled in the browser. N3 is
# the reason. The figures below come from the same `Invoice` and the same
# `resolve` as the UBL, so the document and its machine-readable twin cannot
# disagree about money without a test noticing.


def _sterling(amount: Decimal, rate: Decimal) -> str:
    return _money(amount * rate)


def build_html(invoice: Invoice, treatments: dict[str, Treatment]) -> str | UblError:
    """The invoice as a printable HTML document, or why it cannot be rendered.

    Refuses on exactly the same conditions as `build`, because both call
    `resolve`. A PDF that renders for an invoice whose UBL is refused would be
    a document the customer can act on and the tax authority cannot.
    """
    used = resolve(invoice, treatments)
    if isinstance(used, UblError):
        return used

    foreign = invoice.currency != FUNCTIONAL_CURRENCY and invoice.fx_rate is not None
    symbol = _escape(invoice.currency)

    rows = "".join(
        f"<tr>"
        f"<td>{_escape(line.description)}</td>"
        f"<td class='c'>{_escape(str(line.quantity))}</td>"
        f"<td class='r'>{_money(line.unit_price)}</td>"
        f"<td class='c'>{_escape(line.treatment_code)}</td>"
        f"<td class='r'>{_money(line.vat_rate)}%</td>"
        f"<td class='r'>{_money(line.net_amount)}</td>"
        f"</tr>"
        for line in invoice.lines
    )

    # The VAT summary. A UK VAT invoice must show the taxable amount and the
    # VAT for each rate, and this is the same grouping the UBL emits as
    # TaxSubtotal, from the same function, so the two cannot disagree.
    vat_rows = "".join(
        f"<tr>"
        f"<td>{_money(rate)}%</td>"
        f"<td class='c'>{_escape(code)}</td>"
        f"<td class='c'>{_escape(category)}</td>"
        f"<td class='r'>{_money(net)}</td>"
        f"<td class='r'>{_money(vat)}</td>"
        f"</tr>"
        for category, rate, code, net, vat in vat_breakdown(invoice, used)
    )

    # The sterling block. SPEC section 1 and #37: the euro amount is on the
    # face, the sterling equivalent and the rate sit beneath it. HMRC wants the
    # sterling equivalent and the rate used on the invoice itself, so this is
    # not decoration, it is what makes a foreign-currency invoice a valid VAT
    # invoice for a UK business.
    sterling_block = ""
    if foreign:
        assert invoice.fx_rate is not None
        rate_date = invoice.fx_rate_date.isoformat() if invoice.fx_rate_date else "the issue date"
        sterling_block = (
            "<section class='fx'>"
            f"<div class='fx-line'><span>Total in GBP</span>"
            f"<strong>GBP {_sterling(invoice.gross_total, invoice.fx_rate)}</strong></div>"
            f"<div class='fx-line'><span>of which VAT</span>"
            f"<span>GBP {_sterling(invoice.vat_total, invoice.fx_rate)}</span></div>"
            f"<div class='fx-note'>Converted at {invoice.fx_rate} "
            f"({_escape(invoice.currency)} to GBP), the rate on {_escape(rate_date)}. "
            "This rate is fixed on the invoice and does not change.</div>"
            "</section>"
        )

    seller_vat = _seller_vat(invoice.seller.vat_number, invoice.seller.xi_vat_number, used)

    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>Invoice {_escape(invoice.number)}</title>
<style>{_STYLE}</style></head>
<body>
<header>
  <div class="who">
    <h1>{_escape(invoice.seller.name)}</h1>
    <div class="addr">{_address(invoice.seller)}</div>
    <div class="reg">VAT {_escape(seller_vat)}{_crn(invoice.seller)}</div>
  </div>
  <div class="doc">
    <h2>Invoice</h2>
    <table class="meta">
      <tr><th>Number</th><td>{_escape(invoice.number)}</td></tr>
      <tr><th>Issued</th><td>{invoice.issue_date.isoformat()}</td></tr>
      {_due_row(invoice)}
      {_reference_row(invoice)}
    </table>
  </div>
</header>

<section class="bill-to">
  <h3>Billed to</h3>
  <div>{_escape(invoice.buyer.name)}</div>
  <div class="addr">{_address(invoice.buyer)}</div>
</section>

<table class="lines">
  <thead><tr>
    <th>Description</th><th class="c">Qty</th><th class="r">Unit price</th>
    <th class="c">VAT</th><th class="r">Rate</th><th class="r">Net</th>
  </tr></thead>
  <tbody>{rows}</tbody>
</table>

<table class="vat">
  <thead><tr>
    <th>VAT rate</th><th class="c">Code</th><th class="c">Category</th>
    <th class="r">Taxable</th><th class="r">VAT</th>
  </tr></thead>
  <tbody>{vat_rows}</tbody>
</table>

<section class="totals">
  <div class="t-line"><span>Net total</span>
    <span>{symbol} {_money(invoice.net_total)}</span></div>
  <div class="t-line"><span>VAT</span><span>{symbol} {_money(invoice.vat_total)}</span></div>
  <div class="t-line grand"><span>Total</span>
    <strong>{symbol} {_money(invoice.gross_total)}</strong></div>
</section>
{sterling_block}
<footer>{_reverse_charge_note(used)}</footer>
</body></html>"""


def _due_row(invoice: Invoice) -> str:
    if invoice.due_date is None:
        return ""
    return f"<tr><th>Due</th><td>{invoice.due_date.isoformat()}</td></tr>"


def _reference_row(invoice: Invoice) -> str:
    if not invoice.buyer_reference:
        return ""
    return f"<tr><th>Your reference</th><td>{_escape(invoice.buyer_reference)}</td></tr>"


def _reverse_charge_note(used: dict[str, Treatment]) -> str:
    """A reverse charge invoice must say so on its face.

    The customer accounts for the VAT, and they cannot know that from a zero in
    the VAT column. UBL carries it as BT-121; on paper it has to be words.
    """
    if not any(t.is_reverse_charge for t in used.values()):
        return ""
    return (
        "<p class='note'>Reverse charge: customer to account for VAT to HMRC. "
        "No VAT has been charged on the lines marked DRC or ERC.</p>"
    )


def _crn(party: Party) -> str:
    if not party.company_registration_number:
        return ""
    return f" &middot; Company {_escape(party.company_registration_number)}"


def _address(party: Party) -> str:
    parts = [
        party.address_line1,
        party.address_line2,
        party.city,
        party.postcode,
        party.country,
    ]
    return "<br>".join(_escape(part) for part in parts if part)


def _escape(value: str) -> str:
    """Everything interpolated goes through this.

    Customer names and item descriptions are user input, and this builds markup
    with f-strings. Without escaping, a description containing a tag would be
    rendered as markup, which is a broken document at best. `quote=True` covers
    attribute contexts even though none are interpolated today.
    """
    return escape(value, quote=True)


_STYLE = """
@page { size: A4; margin: 18mm 16mm; }
body { font: 10pt/1.45 "DejaVu Sans", sans-serif; color: #1a1a1a; }
h1 { font-size: 15pt; margin: 0 0 4px; }
h2 { font-size: 13pt; margin: 0 0 6px; text-transform: uppercase;
     letter-spacing: .06em; }
h3 { font-size: 9pt; text-transform: uppercase; letter-spacing: .08em;
     color: #666; margin: 0 0 4px; }
header { display: flex; justify-content: space-between; gap: 24px;
         border-bottom: 2px solid #1a1a1a; padding-bottom: 12px; }
.addr, .reg { color: #444; font-size: 9pt; }
.reg { margin-top: 6px; }
.meta th { text-align: left; color: #666; font-weight: normal;
           padding-right: 10px; font-size: 9pt; }
.bill-to { margin: 16px 0 20px; }
table.lines { width: 100%; border-collapse: collapse; }
table.lines th { text-align: left; font-size: 9pt; color: #666;
                 border-bottom: 1px solid #ccc; padding: 6px 4px; }
table.lines td { padding: 6px 4px; border-bottom: 1px solid #eee; }
.r { text-align: right; } .c { text-align: center; }
table.vat { width: 100%; border-collapse: collapse; margin-top: 18px; }
table.vat th { text-align: left; font-size: 9pt; color: #666;
               border-bottom: 1px solid #ccc; padding: 5px 4px; }
table.vat td { padding: 5px 4px; border-bottom: 1px solid #eee; }
.totals { margin-top: 14px; margin-left: auto; width: 46%; }
.t-line { display: flex; justify-content: space-between; padding: 3px 0; }
.grand { border-top: 2px solid #1a1a1a; margin-top: 4px; padding-top: 6px;
         font-size: 12pt; }
.fx { margin-top: 14px; margin-left: auto; width: 46%;
      border: 1px solid #ccc; padding: 8px 10px; }
.fx-line { display: flex; justify-content: space-between; }
.fx-note { color: #555; font-size: 8.5pt; margin-top: 6px; }
.note { margin-top: 22px; padding: 8px 10px; border-left: 3px solid #1a1a1a;
        background: #f6f6f6; font-size: 9pt; }
"""
