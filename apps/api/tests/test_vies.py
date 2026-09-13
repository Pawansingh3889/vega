"""Tests for VIES VAT validation adapter."""

from __future__ import annotations

from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

from vega_api.modules.vies.contract import (
    ValidationResult,
    ViesRequest,
    ViesValidationError,
)
from vega_api.modules.vies.repository import call_vies_api, update_vat_validation
from vega_api.modules.vies.service import (
    _is_valid_vat_format,
    build_vat_number,
    normalize_country_code,
    parse_vies_response,
    validate_vat_format,
)


def test_is_valid_vat_format_valid() -> None:
    """Test valid VAT format."""
    assert _is_valid_vat_format("DE", "123456789") is True
    assert _is_valid_vat_format("FR", "12345678901") is True
    assert _is_valid_vat_format("GB", "123456789") is True


def test_is_valid_vat_format_invalid() -> None:
    """Test invalid VAT format."""
    assert _is_valid_vat_format("", "123456789") is False
    assert _is_valid_vat_format("D", "123456789") is False
    assert _is_valid_vat_format("DE", "") is False
    assert _is_valid_vat_format("de", "123456789") is True  # Lowercase is accepted
    assert _is_valid_vat_format("DE", "1") is False
    assert _is_valid_vat_format("DE", "123@456") is False


def test_build_vat_number() -> None:
    """Test building full VAT number."""
    assert build_vat_number("DE", "123456789") == "DE123456789"
    assert build_vat_number("FR", "12345678901") == "FR12345678901"


def test_build_vat_number_greece() -> None:
    """Test Greece normalization (GR -> EL)."""
    assert build_vat_number("GR", "123456789") == "EL123456789"
    assert build_vat_number("gr", "123456789") == "EL123456789"  # Lowercase normalized


def test_validation_result_creation() -> None:
    """Test ValidationResult dataclass creation."""
    result = ValidationResult(
        vat_number="DE123456789",
        checked_at=datetime(2026, 9, 6, 10, 0, 0),
        is_valid=True,
    )
    assert result.vat_number == "DE123456789"
    assert result.is_valid is True
    assert isinstance(result.checked_at, datetime)


def test_validation_result_invalid() -> None:
    """Test ValidationResult for invalid VAT."""
    result = ValidationResult(
        vat_number="DE123456789",
        checked_at=datetime(2026, 9, 6, 10, 0, 0),
        is_valid=False,
    )
    assert result.vat_number == "DE123456789"
    assert result.is_valid is False


def test_validation_result_unavailable() -> None:
    """Test ValidationResult for unavailable service."""
    result = ValidationResult(
        vat_number="DE123456789",
        checked_at=datetime(2026, 9, 6, 10, 0, 0),
        is_valid=None,
    )
    assert result.vat_number == "DE123456789"
    assert result.is_valid is None


def test_vies_request_creation() -> None:
    """Test ViesRequest dataclass creation."""
    request = ViesRequest(country_code="DE", vat_number="123456789")
    assert request.country_code == "DE"
    assert request.vat_number == "123456789"


def test_vies_error_types() -> None:
    """Test ViesValidationError enum values."""
    assert str(ViesValidationError.MALFORMED) == "malformed"
    assert str(ViesValidationError.INVALID) == "invalid"
    assert str(ViesValidationError.UNAVAILABLE) == "unavailable"


def test_normalize_country_code() -> None:
    """Test country code normalization."""
    assert normalize_country_code("DE") == "DE"
    assert normalize_country_code("FR") == "FR"
    assert normalize_country_code("GR") == "EL"  # Greece normalization
    assert normalize_country_code("gr") == "EL"  # Lowercase normalized


def test_validate_vat_format() -> None:
    """Test VAT format validation."""
    request = ViesRequest(country_code="DE", vat_number="123456789")
    assert validate_vat_format(request) is None

    request = ViesRequest(country_code="", vat_number="123456789")
    assert validate_vat_format(request) == ViesValidationError.MALFORMED

    request = ViesRequest(country_code="DE", vat_number="")
    assert validate_vat_format(request) == ViesValidationError.MALFORMED


def test_parse_vies_response_success() -> None:
    """Test parsing a valid VIES response."""
    data: dict[str, object] = {
        "valid": True,
        "countryCode": "DE",
        "vatNumber": "123456789",
        "requestDate": "2026-09-06T10:00:00",
        "name": "Test Company",
        "address": "Test Address",
    }
    request = ViesRequest(country_code="DE", vat_number="123456789")
    response = parse_vies_response(data, request)

    assert response.valid is True
    assert response.country_code == "DE"
    assert response.vat_number == "123456789"
    assert response.name == "Test Company"
    assert response.address == "Test Address"


def test_parse_vies_response_invalid_type() -> None:
    """Test parsing response with invalid type for required field."""
    data: dict[str, object] = {
        "valid": "true",  # Should be bool, not string
        "countryCode": "DE",
        "vatNumber": "123456789",
        "requestDate": "2026-09-06T10:00:00",
    }
    request = ViesRequest(country_code="DE", vat_number="123456789")

    try:
        parse_vies_response(data, request)
        raise AssertionError("Should have raised ValueError")
    except ValueError as e:
        assert "Invalid type" in str(e)


def test_parse_vies_response_missing_field() -> None:
    """Test parsing response with missing required field."""
    data: dict[str, object] = {
        "valid": True,
        "countryCode": "DE",
        # Missing vatNumber and requestDate
    }
    request = ViesRequest(country_code="DE", vat_number="123456789")

    try:
        parse_vies_response(data, request)
        raise AssertionError("Should have raised ValueError")
    except ValueError as e:
        assert "Missing required field" in str(e)


def test_parse_vies_response_optional_fields() -> None:
    """Test parsing response with missing optional fields."""
    data: dict[str, object] = {
        "valid": False,
        "countryCode": "DE",
        "vatNumber": "123456789",
        "requestDate": "2026-09-06T10:00:00",
        # Missing name and address (optional)
    }
    request = ViesRequest(country_code="DE", vat_number="123456789")
    response = parse_vies_response(data, request)

    assert response.valid is False
    assert response.name is None
    assert response.address is None


async def test_call_vies_api_timeout() -> None:
    """Test VIES API call handles timeout."""
    import httpx

    request = ViesRequest(country_code="DE", vat_number="123456789")

    async def mock_post(*args: object, **kwargs: object) -> None:
        raise httpx.TimeoutException("Timeout")

    with patch("httpx.AsyncClient") as mock_client_class:
        mock_client = MagicMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=None)
        mock_client.post = mock_post
        mock_client_class.return_value = mock_client

        result = await call_vies_api(request)
        assert result == ViesValidationError.UNAVAILABLE


async def test_call_vies_api_500_error() -> None:
    """Test VIES API call handles 500 error."""
    import httpx

    request = ViesRequest(country_code="DE", vat_number="123456789")

    mock_response = MagicMock()
    mock_response.status_code = 500

    async def mock_post(*args: object, **kwargs: object) -> None:
        raise httpx.HTTPStatusError("Server error", request=MagicMock(), response=mock_response)

    with patch("httpx.AsyncClient") as mock_client_class:
        mock_client = MagicMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=None)
        mock_client.post = mock_post
        mock_client_class.return_value = mock_client

        result = await call_vies_api(request)
        assert result == ViesValidationError.UNAVAILABLE


async def test_call_vies_api_network_error() -> None:
    """Test VIES API call handles network error."""
    import httpx

    request = ViesRequest(country_code="DE", vat_number="123456789")

    async def mock_post(*args: object, **kwargs: object) -> None:
        raise httpx.RequestError("Network error")

    with patch("httpx.AsyncClient") as mock_client_class:
        mock_client = MagicMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=None)
        mock_client.post = mock_post
        mock_client_class.return_value = mock_client

        result = await call_vies_api(request)
        assert result == ViesValidationError.UNAVAILABLE


async def test_call_vies_api_success() -> None:
    """Test VIES API call success path."""
    request = ViesRequest(country_code="DE", vat_number="123456789")

    mock_response = MagicMock()
    mock_response.raise_for_status = MagicMock()
    mock_response.json = MagicMock(
        return_value={
            "valid": True,
            "countryCode": "DE",
            "vatNumber": "123456789",
            "requestDate": "2026-09-06T10:00:00",
        }
    )

    async def mock_post(*args: object, **kwargs: object) -> MagicMock:
        return mock_response

    with patch("httpx.AsyncClient") as mock_client_class:
        mock_client = MagicMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=None)
        mock_client.post = mock_post
        mock_client_class.return_value = mock_client

        result = await call_vies_api(request)
        assert isinstance(result, ValidationResult)
        assert result.is_valid is True
        assert result.vat_number == "123456789"


async def test_update_vat_validation_unavailable() -> None:
    """Test that unavailable validation does not update database."""
    from uuid import uuid4

    mock_conn = AsyncMock()
    result = ValidationResult(
        vat_number="DE123456789",
        checked_at=datetime(2026, 9, 6, 10, 0, 0),
        is_valid=None,  # Unavailable
    )

    await update_vat_validation(mock_conn, "customers", uuid4(), result)

    # Should not have called execute because is_valid is None
    mock_conn.execute.assert_not_called()


async def test_update_vat_validation_valid() -> None:
    """Test that valid validation updates database."""
    from uuid import uuid4

    mock_conn = AsyncMock()
    entity_id = uuid4()
    result = ValidationResult(
        vat_number="DE123456789",
        checked_at=datetime(2026, 9, 6, 10, 0, 0),
        is_valid=True,  # Valid
    )

    await update_vat_validation(mock_conn, "customers", entity_id, result)

    # Should have called execute with the right parameters
    mock_conn.execute.assert_called_once()
    call_args = mock_conn.execute.call_args
    assert call_args[0][0].strip().startswith("UPDATE public.customers")
    assert call_args[0][1] == result.checked_at
    assert call_args[0][2] == result.is_valid
    assert call_args[0][3] == entity_id
