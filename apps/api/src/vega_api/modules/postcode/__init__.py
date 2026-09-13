"""Postcode lookup adapter using getAddress.io.

Phase 5 adds postcode lookup to improve address entry accuracy and reduce
data-entry errors in the UK-first ERP.
"""

from __future__ import annotations

from ...common.errors import Result
from . import repository
from .contract import Address, PostcodeLookupError, PostcodeLookupResult

__all__ = [
    "PERMISSIONS",
    "Address",
    "PostcodeLookupError",
    "PostcodeLookupResult",
    "lookup_postcode",
]

PERMISSIONS = {"postcode.lookup": "authenticated"}


async def lookup_postcode(postcode: str, api_key: str) -> Result:
    """Lookup addresses for a UK postcode.

    Args:
        postcode: The UK postcode to lookup
        api_key: The getAddress.io API key

    Returns:
        Result with addresses or error
    """
    if not postcode:
        return Result.err("no_postcode", "No postcode provided")

    result = await repository.lookup_postcode(postcode, api_key)

    if isinstance(result, PostcodeLookupError):
        if result == PostcodeLookupError.MALFORMED:
            return Result.err("malformed", "Postcode format is invalid")
        elif result == PostcodeLookupError.NOT_FOUND:
            return Result.err("not_found", "Postcode does not resolve to any addresses")
        elif result == PostcodeLookupError.UNAVAILABLE:
            return Result.err("unavailable", "Postcode lookup service is unavailable")
        else:
            return Result.err("unknown", "Unknown error occurred")

    # Convert addresses to serializable format
    addresses_data = [
        {
            "line_1": addr.line_1,
            "line_2": addr.line_2,
            "line_3": addr.line_3,
            "line_4": addr.line_4,
            "town_or_city": addr.town_or_city,
            "county": addr.county,
            "postcode": addr.postcode,
            "formatted_address": addr.formatted_address,
        }
        for addr in result.addresses
    ]

    return Result.good(
        {
            "postcode": result.postcode,
            "addresses": addresses_data,
            "count": result.count,
        }
    )
