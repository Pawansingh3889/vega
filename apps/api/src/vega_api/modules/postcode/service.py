"""Postcode lookup service. Pure business logic, no I/O."""

from __future__ import annotations

from .contract import (
    Address,
)


def normalize_postcode(postcode: str) -> str:
    """Normalize a postcode for the API: spaces removed, uppercase.

    Args:
        postcode: The postcode as typed by a user

    Returns:
        The normalized postcode
    """
    return postcode.replace(" ", "").upper()


def is_valid_postcode_format(postcode: str) -> bool:
    """Basic format validation for UK postcodes.

    This is a lightweight check to catch obviously malformed postcodes
    before calling the API. It does not validate the full UK postcode format.

    Args:
        postcode: The postcode to validate

    Returns:
        True if format is plausible, False if obviously malformed
    """
    if not postcode:
        return False

    # Remove spaces and check length
    normalized = postcode.replace(" ", "")

    # UK postcodes are typically 5-7 characters without spaces
    if len(normalized) < 5 or len(normalized) > 7:
        return False

    # Should be alphanumeric
    return normalized.replace(" ", "").isalnum()


def parse_addresses(raw_addresses: list[dict[str, str]], postcode: str) -> list[Address]:
    """Parse raw getAddress.io response into Address objects.

    Args:
        raw_addresses: Raw addresses from API response
        postcode: The postcode being looked up

    Returns:
        List of Address objects
    """
    addresses = []

    for raw in raw_addresses:
        formatted_address = raw.get("formatted_address", "")

        address = Address(
            line_1=raw.get("line_1"),
            line_2=raw.get("line_2"),
            line_3=raw.get("line_3"),
            line_4=raw.get("line_4"),
            town_or_city=raw.get("town_or_city"),
            county=raw.get("county"),
            postcode=raw.get("postcode", postcode),
            formatted_address=formatted_address,
        )
        addresses.append(address)

    return addresses
