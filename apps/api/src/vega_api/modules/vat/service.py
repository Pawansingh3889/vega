"""Deriving a VAT return. Pure: no I/O, no clock, no database.

SPEC.md section 2.2: boxes 1 to 9 are derived from treatment codes over a
period. No box is typed by a human and no box is stored as an editable figure,
so this function is the only place the arithmetic lives.

Purity is enforced by import-linter, not by good intentions. It also means every
rule below is testable against a list of dataclasses, which is what makes a
filing figure something you can actually pin down in a test.
"""

from __future__ import annotations

from datetime import date
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from .contract import TaxLine, Treatment, VatReturn

PENNY = Decimal("0.01")


def _round(amount: Decimal) -> Decimal:
    """Round to the penny, half up.

    Banker's rounding is the Python default and is wrong here: HMRC and every
    accountant expect half up, and a systematic half-penny drift across a
    quarter is a discrepancy somebody has to explain.
    """
    return amount.quantize(PENNY, rounding=ROUND_HALF_UP)


def derive_return(
    *,
    company_id: UUID,
    period_start: date,
    period_end: date,
    lines: list[TaxLine],
    treatments: dict[str, Treatment],
) -> VatReturn:
    """Turn a period's lines into the nine boxes.

    Unknown treatment codes raise rather than defaulting. A line whose treatment
    this function does not recognise cannot be silently dropped into box 6: that
    is how a return quietly under-declares.
    """
    unknown = sorted({line.treatment_code for line in lines} - treatments.keys())
    if unknown:
        raise ValueError(
            f"cannot derive a return with unrecognised VAT treatments: {', '.join(unknown)}"
        )

    zero = Decimal("0.00")
    box_1 = box_2 = box_4 = box_6 = box_7 = box_8 = box_9 = zero

    for line in lines:
        t = treatments[line.treatment_code]

        # Outside the scope of UK VAT is not zero-rated: it does not belong in
        # the totals at all, which is precisely the distinction the OUT code was
        # renamed to keep clear.
        if t.outside_scope:
            continue

        if line.is_sale:
            box_6 += line.net
            if t.charges_output_vat:
                box_1 += line.vat
            if t.is_northern_ireland and t.is_ec_sales_list:
                box_8 += line.net
        else:
            box_7 += line.net
            box_4 += line.vat
            if t.is_northern_ireland and t.is_ec_sales_list:
                box_9 += line.net
                # An acquisition accounts for the VAT on both sides: due in box
                # 2 and reclaimed in box 4. Recording only one side is the
                # classic acquisition error.
                box_2 += line.vat

    box_3 = box_1 + box_2
    box_5 = box_3 - box_4

    return VatReturn(
        period_start=period_start,
        period_end=period_end,
        company_id=company_id,
        box_1_vat_due_sales=_round(box_1),
        box_2_vat_due_acquisitions=_round(box_2),
        box_3_total_vat_due=_round(box_3),
        box_4_vat_reclaimed=_round(box_4),
        box_5_net_vat=_round(box_5),
        # Boxes 6 to 9 are whole pounds on the return itself, but rounding here
        # would lose pennies before anyone has checked the figure. The
        # submission step rounds; the derivation keeps what it was given.
        box_6_total_sales_ex_vat=_round(box_6),
        box_7_total_purchases_ex_vat=_round(box_7),
        box_8_goods_to_eu=_round(box_8),
        box_9_goods_from_eu=_round(box_9),
        line_count=len(lines),
    )
