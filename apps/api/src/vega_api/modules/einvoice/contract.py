"""Typed shapes for PEPPOL BIS Billing 3.0 output. No I/O, no secrets."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from enum import StrEnum


class UblError(StrEnum):
    """Why a document could not be emitted. Each names something actionable."""

    NOT_ISSUED = "not_issued"
    """Only an issued invoice has a number, and a UBL document without one is
    not a document. Drafts are refused rather than emitted with a blank."""

    UNKNOWN_TREATMENT = "unknown_treatment"
    """A line carries a VAT treatment the database does not define. Refused
    rather than defaulted: guessing a category here files the wrong VAT."""

    NO_LINES = "no_lines"

    SELLER_NOT_REGISTERED = "seller_not_registered"
    """No VAT number on the seller. EN 16931 BR-CO-9 requires one."""

    MISSING_XI_VAT = "missing_xi_vat"
    """A Northern Ireland treatment on a company with no XI VAT number. The
    document would claim an NI supply from a party that cannot make one."""


@dataclass(frozen=True, slots=True)
class Treatment:
    """A VAT treatment as the database defines it.

    `category` is `vat_treatments.en16931_category`, read rather than derived.
    SPEC.md 2.4 owns that mapping and this module must not re-invent it at the
    call site.
    """

    code: str
    category: str
    is_reverse_charge: bool
    is_northern_ireland: bool
    is_ec_sales_list: bool
    """Whether this supply goes on the EC Sales List, which post-Brexit means
    goods leaving Northern Ireland for the EU. Carried because it is half of
    the test for the XI VAT number: `is_northern_ireland` alone includes
    domestic NI trade, which is invoiced under the GB number (#121)."""

    rate: Decimal


@dataclass(frozen=True, slots=True)
class Party:
    name: str
    vat_number: str | None
    xi_vat_number: str | None
    company_registration_number: str | None
    address_line1: str | None
    address_line2: str | None
    city: str | None
    postcode: str | None
    country: str
    """ISO 3166-1 alpha-2. UBL wants the code, never the printed name."""


@dataclass(frozen=True, slots=True)
class Line:
    number: int
    description: str
    item_code: str | None
    commodity_code: str | None
    quantity: Decimal
    unit_code: str
    unit_price: Decimal
    net_amount: Decimal
    treatment_code: str
    vat_rate: Decimal
    vat_amount: Decimal


@dataclass(frozen=True, slots=True)
class Invoice:
    """Everything needed to emit, already gathered. The builder reads no more."""

    number: str
    issue_date: date
    due_date: date | None
    currency: str
    fx_rate: Decimal | None
    fx_rate_date: date | None
    seller: Party
    buyer: Party
    lines: tuple[Line, ...]
    net_total: Decimal
    vat_total: Decimal
    gross_total: Decimal
    buyer_reference: str | None
