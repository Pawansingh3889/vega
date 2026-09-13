"""Typed dataclasses for VIES VAT validation. No I/O, no secrets."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum


class ViesValidationError(StrEnum):
    """VIES validation error types."""

    MALFORMED = "malformed"
    """The VAT number format is invalid."""

    INVALID = "invalid"
    """The VAT number is not registered in VIES."""

    UNAVAILABLE = "unavailable"
    """VIES service is unavailable. Do not record as invalid."""


@dataclass(frozen=True, slots=True)
class ViesRequest:
    """Request to validate a VAT number through VIES."""

    country_code: str
    """Two-letter ISO country code (e.g., DE, FR, EL for Greece)."""

    vat_number: str
    """The VAT number to validate (without country prefix)."""


@dataclass(frozen=True, slots=True)
class ViesResponse:
    """Response from VIES validation."""

    valid: bool
    """Whether the VAT number is valid and registered."""

    country_code: str
    """The country code from VIES response."""

    vat_number: str
    """The VAT number from VIES response."""

    request_date: datetime
    """When VIES processed the request."""

    name: str | None
    """Company name, if the member state shares it."""

    address: str | None
    """Company address, if the member state shares it."""


@dataclass(frozen=True, slots=True)
class ValidationResult:
    """Result of VAT validation for storage in the database.

    Per SPEC.md 4.1, we store only three fields and nothing else.
    The response body is not evidence and is not kept.
    """

    vat_number: str
    """The VAT number that was checked."""

    checked_at: datetime
    """When the check was performed."""

    is_valid: bool | None
    """Whether the VAT number is valid (null if service unavailable)."""
