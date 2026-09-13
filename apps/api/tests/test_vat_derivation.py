"""Deriving boxes 1 to 9.

Pure arithmetic, so these run without a database. That is the point of keeping
service.py pure: a figure that gets filed with HMRC should be pinnable in a test
that takes milliseconds, not one that needs a container.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest

from vega_api.modules.vat.contract import TaxLine, Treatment, VatReturn
from vega_api.modules.vat.service import derive_return

COMPANY = uuid4()
PERIOD = (date(2026, 7, 1), date(2026, 9, 30))


def treatments() -> dict[str, Treatment]:
    """The eleven seeded treatments, reduced to their behaviour."""
    return {
        "STD": Treatment("STD", True, False, False, False, False),
        "RED": Treatment("RED", True, False, False, False, False),
        "ZER": Treatment("ZER", False, False, False, False, False),
        "EXM": Treatment("EXM", False, False, False, False, False),
        "OUT": Treatment("OUT", False, False, False, False, True),
        "DRC": Treatment("DRC", False, True, False, False, False),
        "ERC": Treatment("ERC", False, True, False, True, False),
        "EXP": Treatment("EXP", False, False, False, False, False),
        "XI_STD": Treatment("XI_STD", True, False, True, False, False),
        "XI_ICS": Treatment("XI_ICS", False, False, True, True, False),
    }


def run(lines: list[TaxLine]) -> VatReturn:
    return derive_return(
        company_id=COMPANY,
        period_start=PERIOD[0],
        period_end=PERIOD[1],
        lines=lines,
        treatments=treatments(),
    )


def test_the_seeded_invoice() -> None:
    """The exact figures from the seeded bakery invoice: 120 zero-rated loaves
    at 3.20 and 10 standard-rated brownie trays at 12.50."""
    r = run(
        [
            TaxLine("ZER", Decimal("384.00"), Decimal("0.00"), is_sale=True),
            TaxLine("STD", Decimal("125.00"), Decimal("25.00"), is_sale=True),
        ]
    )
    assert r.box_1_vat_due_sales == Decimal("25.00")
    assert r.box_6_total_sales_ex_vat == Decimal("509.00")
    assert r.box_3_total_vat_due == Decimal("25.00")
    assert r.box_5_net_vat == Decimal("25.00")
    assert r.line_count == 2


def test_zero_rated_belongs_in_box_6_but_charges_no_vat() -> None:
    """Bread is zero rated, not exempt and not outside the scope. Its value
    counts towards total sales; its VAT does not."""
    r = run([TaxLine("ZER", Decimal("1000.00"), Decimal("0.00"), is_sale=True)])
    assert r.box_1_vat_due_sales == Decimal("0.00")
    assert r.box_6_total_sales_ex_vat == Decimal("1000.00")


def test_outside_the_scope_is_excluded_entirely() -> None:
    """OUT is not a zero rate. It does not appear in the totals at all, which is
    exactly the distinction the rename from OSS was meant to protect."""
    r = run(
        [
            TaxLine("STD", Decimal("100.00"), Decimal("20.00"), is_sale=True),
            TaxLine("OUT", Decimal("999.00"), Decimal("0.00"), is_sale=True),
        ]
    )
    assert r.box_6_total_sales_ex_vat == Decimal("100.00")
    assert r.box_1_vat_due_sales == Decimal("20.00")


def test_reverse_charge_declares_no_output_vat() -> None:
    """Under a reverse charge the customer accounts for the VAT, so the supplier
    reports the value and not the tax."""
    r = run([TaxLine("DRC", Decimal("5000.00"), Decimal("0.00"), is_sale=True)])
    assert r.box_1_vat_due_sales == Decimal("0.00")
    assert r.box_6_total_sales_ex_vat == Decimal("5000.00")


def test_purchases_feed_the_input_boxes() -> None:
    r = run(
        [
            TaxLine("STD", Decimal("200.00"), Decimal("40.00"), is_sale=True),
            TaxLine("STD", Decimal("50.00"), Decimal("10.00"), is_sale=False),
        ]
    )
    assert r.box_4_vat_reclaimed == Decimal("10.00")
    assert r.box_7_total_purchases_ex_vat == Decimal("50.00")
    assert r.box_5_net_vat == Decimal("30.00")


def test_northern_ireland_acquisition_accounts_for_both_sides() -> None:
    """An acquisition is due in box 2 and reclaimed in box 4. Recording one side
    only is the classic acquisition error, and it nets to the wrong figure."""
    r = run([TaxLine("XI_ICS", Decimal("800.00"), Decimal("160.00"), is_sale=False)])
    assert r.box_2_vat_due_acquisitions == Decimal("160.00")
    assert r.box_4_vat_reclaimed == Decimal("160.00")
    assert r.box_9_goods_from_eu == Decimal("800.00")
    assert r.box_5_net_vat == Decimal("0.00")


def test_northern_ireland_dispatch_reaches_box_8() -> None:
    r = run([TaxLine("XI_ICS", Decimal("1200.00"), Decimal("0.00"), is_sale=True)])
    assert r.box_8_goods_to_eu == Decimal("1200.00")
    assert r.box_1_vat_due_sales == Decimal("0.00")


def test_box_3_and_5_are_derived_not_asserted() -> None:
    r = run(
        [
            TaxLine("STD", Decimal("1000.00"), Decimal("200.00"), is_sale=True),
            TaxLine("XI_ICS", Decimal("500.00"), Decimal("100.00"), is_sale=False),
            TaxLine("STD", Decimal("300.00"), Decimal("60.00"), is_sale=False),
        ]
    )
    assert r.box_3_total_vat_due == r.box_1_vat_due_sales + r.box_2_vat_due_acquisitions
    assert r.box_5_net_vat == r.box_3_total_vat_due - r.box_4_vat_reclaimed


def test_rounding_is_half_up_not_bankers() -> None:
    """Python rounds half to even by default, which drifts against every
    accountant's expectation. Three lines of 0.125 must reach 0.38, not 0.37."""
    r = run([TaxLine("STD", Decimal("1.00"), Decimal("0.125"), is_sale=True) for _ in range(3)])
    assert r.box_1_vat_due_sales == Decimal("0.38")


def test_an_unrecognised_treatment_stops_the_return() -> None:
    """Dropping an unknown line into box 6 is how a return quietly
    under-declares, so this raises instead."""
    with pytest.raises(ValueError, match="unrecognised VAT treatments: MYSTERY"):
        run([TaxLine("MYSTERY", Decimal("100.00"), Decimal("20.00"), is_sale=True)])


def test_an_empty_period_is_distinguishable_from_no_data() -> None:
    """A genuinely nil return and a period nobody has any lines for produce the
    same boxes, so line_count is what tells them apart."""
    r = run([])
    assert r.box_5_net_vat == Decimal("0.00")
    assert r.line_count == 0
