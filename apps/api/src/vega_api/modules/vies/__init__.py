"""VIES adapter for EU VAT number validation.

Phase 4 owns this adapter because reverse charge needs it at invoice time.
Phase 5 reuses it for onboarding autofill rather than building a second one.
"""

from __future__ import annotations

from uuid import UUID

import asyncpg

from ...common.errors import Result
from . import repository
from .contract import ViesRequest, ViesValidationError

PERMISSIONS = {
    "vies.validate": "authenticated",
}


async def validate_customer_vat(
    conn: asyncpg.Connection,
    customer_id: UUID,
) -> Result:
    """Validate a customer's VAT number through VIES and record the result.

    Args:
        conn: Database connection
        customer_id: The customer ID

    Returns:
        Result with validation status or error
    """
    # Get customer's VAT number
    vat_number = await conn.fetchval(
        "SELECT vat_number FROM public.customers WHERE id = $1",
        customer_id,
    )

    if not vat_number:
        return Result.err("no_vat_number", "Customer has no VAT number to validate")

    # Parse country code and number
    # VAT numbers are typically formatted as "CC123456789"
    if len(vat_number) < 3:
        return Result.err("invalid_format", "VAT number too short")

    country_code = vat_number[:2].upper()
    vat_number_only = vat_number[2:]

    request = ViesRequest(country_code=country_code, vat_number=vat_number_only)

    # Validate through VIES
    result = await repository.call_vies_api(request)

    if isinstance(result, ViesValidationError):
        if result == ViesValidationError.MALFORMED:
            return Result.err("malformed", "VAT number format is invalid")
        elif result == ViesValidationError.UNAVAILABLE:
            return Result.err("unavailable", "VIES service is unavailable")
        else:
            return Result.err("invalid", "VAT number is invalid")

    # Record the result
    await repository.update_vat_validation(
        conn,
        "customers",
        customer_id,
        result,
    )

    return Result.good(
        {
            "vat_number": result.vat_number,
            "checked_at": result.checked_at.isoformat(),
            "is_valid": result.is_valid,
        }
    )


async def validate_supplier_vat(
    conn: asyncpg.Connection,
    supplier_id: UUID,
) -> Result:
    """Validate a supplier's VAT number through VIES and record the result.

    Args:
        conn: Database connection
        supplier_id: The supplier ID

    Returns:
        Result with validation status or error
    """
    # Get supplier's VAT number
    vat_number = await conn.fetchval(
        "SELECT vat_number FROM public.suppliers WHERE id = $1",
        supplier_id,
    )

    if not vat_number:
        return Result.err("no_vat_number", "Supplier has no VAT number to validate")

    # Parse country code and number
    if len(vat_number) < 3:
        return Result.err("invalid_format", "VAT number too short")

    country_code = vat_number[:2].upper()
    vat_number_only = vat_number[2:]

    request = ViesRequest(country_code=country_code, vat_number=vat_number_only)

    # Validate through VIES
    result = await repository.call_vies_api(request)

    if isinstance(result, ViesValidationError):
        if result == ViesValidationError.MALFORMED:
            return Result.err("malformed", "VAT number format is invalid")
        elif result == ViesValidationError.UNAVAILABLE:
            return Result.err("unavailable", "VIES service is unavailable")
        else:
            return Result.err("invalid", "VAT number is invalid")

    # Record the result
    await repository.update_vat_validation(
        conn,
        "suppliers",
        supplier_id,
        result,
    )

    return Result.good(
        {
            "vat_number": result.vat_number,
            "checked_at": result.checked_at.isoformat(),
            "is_valid": result.is_valid,
        }
    )
