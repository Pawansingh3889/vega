"""Tests for postcode lookup adapter."""

from __future__ import annotations

from vega_api.modules.postcode.contract import (
    Address,
    PostcodeLookupError,
    PostcodeLookupResult,
)
from vega_api.modules.postcode.service import (
    is_valid_postcode_format,
    parse_addresses,
)


def testis_valid_postcode_format_valid() -> None:
    """Test valid postcode formats."""
    assert is_valid_postcode_format("SW1A 1AA") is True
    assert is_valid_postcode_format("SW1A1AA") is True
    assert is_valid_postcode_format("M1 1AA") is True
    assert is_valid_postcode_format("B33 8TH") is True


def testis_valid_postcode_format_invalid() -> None:
    """Test invalid postcode formats."""
    assert is_valid_postcode_format("") is False
    assert is_valid_postcode_format("SW1") is False  # Too short
    assert is_valid_postcode_format("SW1A 1AAX") is False  # Too long
    assert is_valid_postcode_format("SW1@ 1AA") is False  # Invalid chars


def testparse_addresses() -> None:
    """Test parsing raw API response into Address objects."""
    raw_addresses: list[dict[str, str]] = [
        {
            "line_1": "10 Downing Street",
            "line_2": "",
            "line_3": "",
            "line_4": "",
            "town_or_city": "London",
            "county": "Greater London",
            "postcode": "SW1A 2AA",
            "formatted_address": "10 Downing Street, London, SW1A 2AA",
        }
    ]

    addresses = parse_addresses(raw_addresses, "SW1A2AA")

    assert len(addresses) == 1
    assert addresses[0].line_1 == "10 Downing Street"
    assert addresses[0].town_or_city == "London"
    assert addresses[0].postcode == "SW1A 2AA"
    assert addresses[0].formatted_address == "10 Downing Street, London, SW1A 2AA"


def testparse_addresses_multiple() -> None:
    """Test parsing multiple addresses."""
    raw_addresses: list[dict[str, str]] = [
        {
            "line_1": "10 Downing Street",
            "line_2": "",
            "line_3": "",
            "line_4": "",
            "town_or_city": "London",
            "county": "Greater London",
            "postcode": "SW1A 2AA",
            "formatted_address": "10 Downing Street, London, SW1A 2AA",
        },
        {
            "line_1": "11 Downing Street",
            "line_2": "",
            "line_3": "",
            "line_4": "",
            "town_or_city": "London",
            "county": "Greater London",
            "postcode": "SW1A 2AB",
            "formatted_address": "11 Downing Street, London, SW1A 2AB",
        },
    ]

    addresses = parse_addresses(raw_addresses, "SW1A2AA")

    assert len(addresses) == 2
    assert addresses[0].line_1 == "10 Downing Street"
    assert addresses[1].line_1 == "11 Downing Street"


def test_address_creation() -> None:
    """Test Address dataclass creation."""
    address = Address(
        line_1="10 Downing Street",
        line_2=None,
        line_3=None,
        line_4=None,
        town_or_city="London",
        county="Greater London",
        postcode="SW1A 2AA",
        formatted_address="10 Downing Street, London, SW1A 2AA",
    )

    assert address.line_1 == "10 Downing Street"
    assert address.town_or_city == "London"
    assert address.postcode == "SW1A 2AA"


def test_postcode_lookup_result_creation() -> None:
    """Test PostcodeLookupResult dataclass creation."""
    addresses = [
        Address(
            line_1="10 Downing Street",
            line_2=None,
            line_3=None,
            line_4=None,
            town_or_city="London",
            county="Greater London",
            postcode="SW1A 2AA",
            formatted_address="10 Downing Street, London, SW1A 2AA",
        )
    ]

    result = PostcodeLookupResult(
        postcode="SW1A2AA",
        addresses=addresses,
        count=1,
    )

    assert result.postcode == "SW1A2AA"
    assert result.count == 1
    assert len(result.addresses) == 1


def test_postcode_lookup_error_types() -> None:
    """Test PostcodeLookupError enum values."""
    assert str(PostcodeLookupError.MALFORMED) == "malformed"
    assert str(PostcodeLookupError.NOT_FOUND) == "not_found"
    assert str(PostcodeLookupError.UNAVAILABLE) == "unavailable"
