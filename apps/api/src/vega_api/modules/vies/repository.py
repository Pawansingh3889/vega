"""Database I/O for VIES VAT validation. All SQL and HTTP calls live here."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import asyncpg
import httpx

from . import service
from .contract import (
    ValidationResult,
    ViesRequest,
    ViesValidationError,
)

VIES_API_URL = "https://ec.europa.eu/taxation_customs/vies/rest-api/check-vat-number"


async def update_vat_validation(
    conn: asyncpg.Connection,
    table: str,
    entity_id: UUID,
    result: ValidationResult,
) -> None:
    """Update VAT validation result for a customer or supplier.

    Args:
        conn: Database connection
        table: Either "customers" or "suppliers"
        entity_id: The customer or supplier ID
        result: The validation result from VIES

    Raises:
        ValueError: If table is not "customers" or "suppliers"
    """
    if table not in ("customers", "suppliers"):
        raise ValueError(f"Invalid table: {table}. Must be 'customers' or 'suppliers'")

    if result.is_valid is None:
        # Service unavailable - do not update (per issue requirements)
        return

    await conn.execute(
        f"""
        UPDATE public.{table}
        SET vat_number_checked_at = $1,
            vat_number_valid = $2
        WHERE id = $3
        """,
        result.checked_at,
        result.is_valid,
        entity_id,
    )


async def get_vat_validation_status(
    conn: asyncpg.Connection,
    table: str,
    entity_id: UUID,
) -> tuple[str | None, datetime | None, bool | None]:
    """Get current VAT validation status for a customer or supplier.

    Args:
        conn: Database connection
        table: Either "customers" or "suppliers"
        entity_id: The customer or supplier ID

    Returns:
        Tuple of (vat_number, checked_at, is_valid)
    """
    if table not in ("customers", "suppliers"):
        raise ValueError(f"Invalid table: {table}. Must be 'customers' or 'suppliers'")

    row = await conn.fetchrow(
        f"""
        SELECT vat_number, vat_number_checked_at, vat_number_valid
        FROM public.{table}
        WHERE id = $1
        """,
        entity_id,
    )

    if row is None:
        return None, None, None

    return row["vat_number"], row["vat_number_checked_at"], row["vat_number_valid"]


async def call_vies_api(request: ViesRequest) -> ValidationResult | ViesValidationError:
    """Call VIES API to validate a VAT number.

    Args:
        request: The VAT number to validate

    Returns:
        ValidationResult if successful, ViesValidationError if failed
    """
    # Validate format first
    format_error = service.validate_vat_format(request)
    if format_error:
        return format_error

    # Normalize country code
    normalized_country = service.normalize_country_code(request.country_code)

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                VIES_API_URL,
                json={
                    "countryCode": normalized_country,
                    "vatNumber": request.vat_number,
                },
            )
            response.raise_for_status()
            data = response.json()

            vies_response = service.parse_vies_response(data, request)

            return ValidationResult(
                vat_number=request.vat_number,
                checked_at=datetime.now(UTC),
                is_valid=vies_response.valid,
            )

    except httpx.HTTPStatusError:
        # VIES returned 4xx or 5xx - treat as unavailable
        return ViesValidationError.UNAVAILABLE

    except httpx.TimeoutException:
        # VIES timed out - treat as unavailable
        return ViesValidationError.UNAVAILABLE

    except httpx.RequestError:
        # Network error - treat as unavailable
        return ViesValidationError.UNAVAILABLE

    except ValueError:
        # Response parsing failed - treat as unavailable
        return ViesValidationError.UNAVAILABLE

    except Exception:
        # Unexpected error - treat as unavailable to be safe
        return ViesValidationError.UNAVAILABLE
