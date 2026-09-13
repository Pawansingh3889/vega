"""Verifying a Supabase JWT.

This project issues ES256 tokens signed with a rotating key published at the
JWKS endpoint, so the service holds a public key and never a shared secret. That
removes a whole class of accident: there is no JWT secret to leak from this
process.

Three assertions matter and all three are made explicitly, because each has been
a real vulnerability in somebody's authentication code:

  * the algorithm comes from OUR allowlist, never from the token's header, which
    is how `alg: none` and HS256-with-the-public-key forgeries work;
  * the issuer must be this project, so a token minted by any other Supabase
    project is refused;
  * the audience must be `authenticated`, so an anon key's token cannot pass as
    a signed-in user.
"""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

import jwt
from jwt import PyJWKClient

from .common.errors import UnauthenticatedError
from .config import Settings


@dataclass(frozen=True, slots=True)
class Caller:
    """Who is asking, and which company they asked to act in.

    The company is a REQUEST, not a fact. The database decides whether it is
    honoured, by checking membership in current_company_id(). Nothing in this
    process may treat it as authorisation.
    """

    user_id: UUID
    email: str | None
    requested_company: UUID | None


class TokenVerifier:
    """Verifies bearer tokens against the project's published keys.

    The JWKS client caches keys and refetches on an unknown `kid`, so key
    rotation is handled without a restart.
    """

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._jwks = PyJWKClient(settings.jwks_url, cache_keys=True)

    def verify(self, token: str, requested_company: str | None = None) -> Caller:
        try:
            signing_key = self._jwks.get_signing_key_from_jwt(token).key
        # Any JWKS failure is a refusal, whatever its shape.
        except Exception as exc:
            raise UnauthenticatedError(
                "Could not fetch the key this token was signed with. "
                "If the project's signing keys were just rotated, retry."
            ) from exc

        try:
            claims = jwt.decode(
                token,
                signing_key,
                algorithms=list(self._settings.jwt_algorithms),
                audience=self._settings.jwt_audience,
                issuer=self._settings.jwt_issuer,
                options={"require": ["exp", "sub", "aud", "iss"]},
            )
        except jwt.ExpiredSignatureError as exc:
            raise UnauthenticatedError("This session has expired. Sign in again.") from exc
        except jwt.InvalidAudienceError as exc:
            raise UnauthenticatedError("This token was not issued for this application.") from exc
        except jwt.InvalidIssuerError as exc:
            raise UnauthenticatedError("This token was issued by a different project.") from exc
        except jwt.InvalidTokenError as exc:
            raise UnauthenticatedError(f"This token could not be verified: {exc}") from exc

        try:
            user_id = UUID(str(claims["sub"]))
        except (KeyError, ValueError) as exc:
            raise UnauthenticatedError("This token carries no usable subject.") from exc

        company: UUID | None = None
        if requested_company:
            try:
                company = UUID(requested_company)
            except ValueError as exc:
                raise UnauthenticatedError(
                    f"'{requested_company}' is not a company id. "
                    "Send the company's UUID in the X-Vega-Company header."
                ) from exc

        return Caller(
            user_id=user_id,
            email=claims.get("email"),
            requested_company=company,
        )
