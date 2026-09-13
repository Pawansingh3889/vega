"""Errors carry a code and something a person can act on.

SECURITY.md N5 in spirit: no silent failure. An error that says only "something
went wrong" is the same as no error at all, because nobody can tell what broke.
"""

from __future__ import annotations

from dataclasses import dataclass


class VegaError(Exception):
    """Base class. Every subclass names a code and an HTTP status."""

    code = "vega_error"
    status = 500

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class UnauthenticatedError(VegaError):
    code = "unauthenticated"
    status = 401


class NoCompanySelectedError(VegaError):
    """The caller belongs to several companies and chose none.

    Deliberately its own error rather than an empty result: the old behaviour
    picked one arbitrarily, and silence is what let that go unnoticed.
    """

    code = "no_company_selected"
    status = 409


class InvalidRequestError(VegaError):
    code = "invalid_request"
    status = 422


@dataclass(frozen=True, slots=True)
class Result:
    """What a module hands back. Never a bare exception across a seam."""

    ok: bool
    value: object | None = None
    code: str | None = None
    message: str | None = None

    @staticmethod
    def good(value: object) -> Result:
        return Result(ok=True, value=value)

    @staticmethod
    def err(code: str, message: str) -> Result:
        if not message:
            raise ValueError("an error result must carry a message somebody can act on")
        return Result(ok=False, code=code, message=message)
