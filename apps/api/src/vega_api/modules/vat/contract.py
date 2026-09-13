"""Typed rows and results for the VAT module. No I/O, no secrets."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from uuid import UUID


@dataclass(frozen=True, slots=True)
class TaxLine:
    """One invoice line, reduced to what a VAT return cares about.

    Money is Decimal throughout. These figures are filed with HMRC, and the
    float form of 1.005 rounds the wrong way at a half penny, which is the
    rounding bug already documented in the Rigel export.
    """

    treatment_code: str
    """Why this rate applied, not just what it was. The return is derived from
    treatments, because a rate alone cannot tell you which box a line belongs in."""

    net: Decimal
    vat: Decimal
    is_sale: bool
    """Sales feed the output boxes, purchases the input boxes."""


@dataclass(frozen=True, slots=True)
class Treatment:
    """A VAT treatment and the behaviour that decides its boxes."""

    code: str
    charges_output_vat: bool
    is_reverse_charge: bool
    is_northern_ireland: bool
    is_ec_sales_list: bool
    outside_scope: bool


@dataclass(frozen=True, slots=True)
class VatReturn:
    """Boxes 1 to 9, derived. No box is ever typed by a human."""

    period_start: date
    period_end: date
    company_id: UUID

    box_1_vat_due_sales: Decimal
    box_2_vat_due_acquisitions: Decimal
    box_3_total_vat_due: Decimal
    box_4_vat_reclaimed: Decimal
    box_5_net_vat: Decimal
    box_6_total_sales_ex_vat: Decimal
    box_7_total_purchases_ex_vat: Decimal
    box_8_goods_to_eu: Decimal
    box_9_goods_from_eu: Decimal

    line_count: int
    """How many lines produced these figures. A return derived from nothing is
    a different thing from a return that is genuinely zero, and the caller
    should be able to tell them apart."""
