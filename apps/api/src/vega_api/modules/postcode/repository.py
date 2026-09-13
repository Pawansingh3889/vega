"""Address I/O for postcode lookup. All HTTP calls live here."""

from __future__ import annotations

import httpx

from . import service
from .contract import (
    PostcodeLookupError,
    PostcodeLookupResult,
)

GETADDRESS_API_URL = "https://api.getAddress.io/v3/uk/{postcode}?api-key={api_key}"


async def lookup_postcode(
    postcode: str, api_key: str
) -> PostcodeLookupResult | PostcodeLookupError:
    """Lookup addresses for a UK postcode using getAddress.io.

    Args:
        postcode: The UK postcode to lookup
        api_key: The getAddress.io API key

    Returns:
        PostcodeLookupResult if successful, PostcodeLookupError if failed

    Raises:
        ValueError: If the postcode format is invalid
    """
    # Validate format before calling API
    if not service.is_valid_postcode_format(postcode):
        return PostcodeLookupError.MALFORMED

    # Normalize postcode (remove spaces, uppercase)
    normalized_postcode = service.normalize_postcode(postcode)

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            url = GETADDRESS_API_URL.format(postcode=normalized_postcode, api_key=api_key)
            response = await client.get(url)
            response.raise_for_status()
            data = response.json()

            if not data or data.get("address_count", 0) == 0:
                return PostcodeLookupError.NOT_FOUND

            addresses = service.parse_addresses(data.get("addresses", []), normalized_postcode)

            return PostcodeLookupResult(
                postcode=normalized_postcode,
                addresses=addresses,
                count=len(addresses),
            )

    except httpx.HTTPStatusError:
        # Rate limit (429) or other HTTP errors
        return PostcodeLookupError.UNAVAILABLE

    except httpx.TimeoutException:
        # Service timeout
        return PostcodeLookupError.UNAVAILABLE

    except httpx.RequestError:
        # Network error
        return PostcodeLookupError.UNAVAILABLE

    except ValueError:
        # A 200 whose body is not JSON. Narrow on purpose, and the last handler
        # here: this one really is the provider misbehaving, so it belongs with
        # the four above.
        #
        # There used to be a bare `except Exception` below this, added to "treat
        # an unexpected error as unavailable to be safe". It was the opposite of
        # safe. Any bug inside the try became `unavailable`: a KeyError, a typo,
        # a column that does not exist. The caller is told getAddress.io is
        # having a bad afternoon and nobody looks at the code.
        #
        # That is not hypothetical. Two repositories shipped queries naming
        # columns that do not exist (#99, #103). Both raised, both surfaced as a
        # 500 naming the column, and both were found in minutes. Behind a
        # catch-all they would have been a shrug. SECURITY.md N6: a failure that
        # cannot report itself is not handled.
        return PostcodeLookupError.UNAVAILABLE
