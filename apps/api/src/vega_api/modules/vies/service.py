"""VIES VAT validation service. Pure business logic, no I/O."""

from __future__ import annotations

from .contract import (
    ViesRequest,
    ViesResponse,
    ViesValidationError,
)


def validate_vat_format(request: ViesRequest) -> ViesValidationError | None:
    """Validate VAT number format before calling VIES.

    Args:
        request: The VAT number to validate

    Returns:
        None if format is valid, ViesValidationError.MALFORMED if not
    """
    if not _is_valid_vat_format(request.country_code, request.vat_number):
        return ViesValidationError.MALFORMED
    return None


def normalize_country_code(country_code: str) -> str:
    """Normalize country code for VIES API.

    Args:
        country_code: Two-letter ISO country code

    Returns:
        Normalized country code (GR -> EL for Greece, uppercase)
    """
    country_code = country_code.upper()
    return "EL" if country_code == "GR" else country_code


def parse_vies_response(data: dict[str, object], request: ViesRequest) -> ViesResponse:
    """Parse VIES API response into a ViesResponse.

    Args:
        data: Raw JSON response from VIES
        request: Original request

    Returns:
        Parsed ViesResponse

    Raises:
        ValueError: If required fields are missing
    """
    try:
        valid = data["valid"]
        country_code = data["countryCode"]
        vat_number = data["vatNumber"]
        request_date_str = data["requestDate"]
    except KeyError as e:
        raise ValueError(f"Missing required field in VIES response: {e}") from e

    if not isinstance(valid, bool):
        raise ValueError(f"Invalid type for 'valid': {type(valid)}")
    if not isinstance(country_code, str):
        raise ValueError(f"Invalid type for 'countryCode': {type(country_code)}")
    if not isinstance(vat_number, str):
        raise ValueError(f"Invalid type for 'vatNumber': {type(vat_number)}")
    if not isinstance(request_date_str, str):
        raise ValueError(f"Invalid type for 'requestDate': {type(request_date_str)}")

    from datetime import datetime

    name_value = data.get("name")
    address_value = data.get("address")

    return ViesResponse(
        valid=valid,
        country_code=country_code,
        vat_number=vat_number,
        request_date=datetime.fromisoformat(request_date_str),
        name=name_value if isinstance(name_value, str) else None,
        address=address_value if isinstance(address_value, str) else None,
    )


def build_vat_number(country_code: str, vat_number: str) -> str:
    """Build a full VAT number from country code and number.

    Args:
        country_code: Two-letter ISO country code
        vat_number: The VAT number

    Returns:
        Full VAT number (e.g., "DE123456789")
    """
    # Normalize to uppercase
    country_code = country_code.upper()
    # Normalize Greece: EL not GR
    normalized_country = "EL" if country_code == "GR" else country_code
    return f"{normalized_country}{vat_number}"


def _is_valid_vat_format(country_code: str, vat_number: str) -> bool:
    """Basic format validation for VAT numbers.

    This is a lightweight check to catch obviously malformed numbers
    before calling VIES. It does not validate the actual VAT format
    for each country, which would be complex and VIES is the authority.

    Args:
        country_code: Two-letter ISO country code
        vat_number: The VAT number to validate

    Returns:
        True if format is plausible, False if obviously malformed
    """
    # Normalize to uppercase for validation
    country_code = country_code.upper()

    if not country_code or len(country_code) != 2:
        return False

    if not vat_number or len(vat_number) < 2:
        return False

    # VAT numbers should be alphanumeric (no spaces, special chars)
    # This is a basic sanity check, not comprehensive validation
    return vat_number.replace(" ", "").replace("-", "").isalnum()
