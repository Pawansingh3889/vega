"""The HMRC OAuth flow, exercised without an HMRC account.

That is the point of the split. Getting real credentials is a registration with
lead time, and a flow that can only be checked once you have them is a flow
nobody checks until the day it matters.

The transport is faked; the logic is not.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

from vega_api.common.crypto import SecretBox, SecretBoxError
from vega_api.modules.hmrc import repository, service
from vega_api.modules.hmrc.contract import HmrcError

NOW = datetime(2026, 9, 7, 12, 0, tzinfo=UTC)
# Real Fernet keys, generated for this file. They protect nothing.
KEY = "mdf3g8EigF8Wk85-UZoecUP2jeiUt-sIZnq1aKxN_hQ="
OTHER_KEY = "1CaU4sjEOHw2aCXXqhXaSLEjvTINx9MoIW9Uzm4KYu4="


def _client(handler: object) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))  # type: ignore[arg-type]


# --- the parts that decide where a return goes -------------------------------


def test_sandbox_and_production_are_different_hosts() -> None:
    """Not a flag on one host. The wrong one files a real return at a test
    service, or a test return at the real one."""
    assert service.base_url("sandbox") == "https://test-api.service.hmrc.gov.uk"
    assert service.base_url("production") == "https://api.service.hmrc.gov.uk"


def test_an_unknown_environment_raises_rather_than_guessing() -> None:
    with pytest.raises(ValueError):
        service.base_url("staging")


def test_the_authorisation_url_asks_for_exactly_the_two_scopes_we_use() -> None:
    """A customer sees this list on HMRC's consent screen. Asking for more than
    the product uses is asking them to grant more than it needs."""
    url = service.authorization_url(
        environment="sandbox",
        client_id="cid",
        redirect_uri="https://vega.example/callback",
        state="st",
    )
    query = parse_qs(urlparse(url).query)

    assert query["scope"] == ["read:vat write:vat"]
    assert query["response_type"] == ["code"]
    assert query["state"] == ["st"]
    assert urlparse(url).netloc == "test-api.service.hmrc.gov.uk"


# --- the CSRF guard ----------------------------------------------------------


def test_a_mismatched_state_is_refused() -> None:
    """Without this, an attacker completes the flow into their own HMRC
    account and the customer's Vega ends up connected to it."""
    assert service.check_state(issued="a", returned="b") is HmrcError.STATE_MISMATCH


def test_an_empty_state_is_refused_rather_than_treated_as_equal() -> None:
    assert service.check_state(issued="", returned="") is HmrcError.STATE_MISMATCH


def test_a_matching_state_passes() -> None:
    assert service.check_state(issued="same", returned="same") is None


def test_two_states_are_never_the_same() -> None:
    assert service.new_state() != service.new_state()


# --- reading HMRC's answer ---------------------------------------------------


def test_a_token_response_without_a_refresh_token_is_refused() -> None:
    """It would look connected and would not be, and the person would find out
    at the moment they tried to file."""
    result = service.parse_tokens({"access_token": "a", "expires_in": 14400}, now=NOW)

    assert result is HmrcError.EXCHANGE_REFUSED


def test_a_token_response_without_an_access_token_is_refused() -> None:
    assert service.parse_tokens({"refresh_token": "r"}, now=NOW) is HmrcError.EXCHANGE_REFUSED


def test_expiry_comes_from_hmrc_rather_than_being_assumed() -> None:
    tokens = service.parse_tokens(
        {"access_token": "a", "refresh_token": "r", "expires_in": 60}, now=NOW
    )

    assert not isinstance(tokens, HmrcError)
    assert tokens.expires_at == NOW + timedelta(seconds=60)


def test_a_token_is_refreshed_before_it_actually_dies() -> None:
    """A submission started at 3:59:59 must not fail mid-flight."""
    assert service.needs_refresh(NOW + timedelta(minutes=1), now=NOW) is True
    assert service.needs_refresh(NOW + timedelta(hours=1), now=NOW) is False


# --- the transport -----------------------------------------------------------


@pytest.mark.asyncio
async def test_a_code_is_exchanged_for_tokens() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "test-api.service.hmrc.gov.uk"
        return httpx.Response(
            200,
            json={
                "access_token": "at",
                "refresh_token": "rt",
                "expires_in": 14400,
                "scope": "read:vat write:vat",
            },
        )

    async with _client(handler) as client:
        tokens = await repository.exchange_code(
            client,
            environment="sandbox",
            client_id="cid",
            client_secret="secret",
            redirect_uri="https://vega.example/callback",
            code="the-code",
            now=NOW,
        )

    assert not isinstance(tokens, HmrcError)
    assert tokens.refresh_token == "rt"


@pytest.mark.asyncio
async def test_a_refused_grant_and_an_outage_are_told_apart() -> None:
    """One asks the person to reconnect, the other asks them to wait. Reporting
    both as the same thing sends somebody to redo an authorisation that was
    fine."""

    async with _client(lambda r: httpx.Response(400, json={})) as client:
        refused = await repository.refresh_tokens(
            client,
            environment="sandbox",
            client_id="c",
            client_secret="s",
            refresh_token="rt",
            now=NOW,
        )
    async with _client(lambda r: httpx.Response(503, text="down")) as client:
        outage = await repository.refresh_tokens(
            client,
            environment="sandbox",
            client_id="c",
            client_secret="s",
            refresh_token="rt",
            now=NOW,
        )

    assert refused is HmrcError.REFRESH_REFUSED
    assert outage is HmrcError.UNAVAILABLE


@pytest.mark.asyncio
async def test_a_timeout_is_unavailable_not_a_refusal() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("slow", request=request)

    async with _client(handler) as client:
        result = await repository.exchange_code(
            client,
            environment="sandbox",
            client_id="c",
            client_secret="s",
            redirect_uri="https://vega.example/cb",
            code="x",
            now=NOW,
        )

    assert result is HmrcError.UNAVAILABLE


# --- the encryption ----------------------------------------------------------


def test_a_sealed_secret_does_not_contain_the_plaintext() -> None:
    box = SecretBox(KEY)

    sealed = box.seal("my-refresh-token")

    assert b"my-refresh-token" not in sealed
    assert box.open(sealed) == "my-refresh-token"


def test_sealing_twice_gives_different_ciphertext() -> None:
    """Otherwise two companies with the same token are visibly the same, and a
    changed token is visible as a changed row even to somebody who cannot read
    it."""
    box = SecretBox(KEY)

    assert box.seal("same") != box.seal("same")


def test_another_key_cannot_open_it() -> None:
    sealed = SecretBox(KEY).seal("secret")

    with pytest.raises(SecretBoxError):
        SecretBox(OTHER_KEY).open(sealed)


def test_tampered_ciphertext_is_refused_rather_than_decrypted() -> None:
    """Fernet is authenticated encryption, which is why this is possible. An
    unauthenticated cipher would let somebody who can write to the table swap
    one token's bytes for another's undetected."""
    box = SecretBox(KEY)
    sealed = bytearray(box.seal("secret"))
    sealed[-1] ^= 0x01

    with pytest.raises(SecretBoxError):
        box.open(bytes(sealed))


def test_a_missing_key_refuses_and_names_the_variable() -> None:
    with pytest.raises(SecretBoxError) as caught:
        SecretBox("")

    assert "VEGA_TOKEN_KEY" in str(caught.value)
