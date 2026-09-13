"""Typed dataclasses for postcode lookup. No I/O, no secrets."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class PostcodeLookupError(StrEnum):
    """Postcode lookup error types."""

    MALFORMED = "malformed"
    """The postcode format is invalid."""

    NOT_FOUND = "not_found"
    """The postcode does not resolve to any addresses."""

    UNAVAILABLE = "unavailable"
    """The postcode lookup service is unavailable."""


@dataclass(frozen=True, slots=True)
class Address:
    """A single address from postcode lookup."""

    line_1: str | None
    """First line of address (building name/number)."""

    line_2: str | None
    """Second line of address (street)."""

    line_3: str | None
    """Third line of address (locality)."""

    line_4: str | None
    """Fourth line of address (town/city)."""

    town_or_city: str | None
    """Town or city."""

    county: str | None
    """County."""

    postcode: str
    """Postcode."""

    formatted_address: str
    """Full formatted address for display."""


@dataclass(frozen=True, slots=True)
class PostcodeLookupResult:
    """Result of postcode lookup."""

    postcode: str
    """The postcode that was looked up."""

    addresses: list[Address]
    """List of addresses found for this postcode."""

    count: int
    """Number of addresses found."""
