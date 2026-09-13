"""HMRC: the MTD VAT connection, its tokens and its obligations.

This file was missing, and its absence was not cosmetic. `test_layering.py`
identifies a module by the presence of an `__init__.py`, so a directory without
one is not a module as far as the layering check is concerned: it was never
required to appear in the independence contract, and import-linter therefore
never looked at it. `import httpx` sat in `service.py` and the run reported
"service.py is pure: no network, no database, no repository KEPT".

The other four-file modules export their public surface here. This one does the
same, so `service` and `repository` stay the private halves and callers have one
name to import.
"""

from __future__ import annotations

from .contract import (
    Connection,
    DeviceContext,
    HmrcError,
    Obligation,
    Tokens,
    VendorContext,
)
from .service import (
    GRANT_LIFETIME_MONTHS,
    PRODUCTION_BASE,
    REAUTHORISATION_WARNING,
    REFRESH_MARGIN,
    SANDBOX_BASE,
    SCOPES,
    authorization_url,
    base_url,
    check_state,
    fraud_headers,
    grant_expires_at,
    grant_has_expired,
    needs_refresh,
    new_state,
    parse_obligations,
    parse_tokens,
    reauthorisation_due,
)

# Filing a VAT return is not a thing a person does by accident, and it is not a
# thing a background job should be able to do at all. Naming the permission here
# keeps it next to the module it governs rather than in a list somewhere else.
PERMISSIONS = {
    "hmrc.connect": "owner",
    "hmrc.file": "owner",
    "hmrc.read": "member",
}

__all__ = [
    "GRANT_LIFETIME_MONTHS",
    "PERMISSIONS",
    "PRODUCTION_BASE",
    "REAUTHORISATION_WARNING",
    "REFRESH_MARGIN",
    "SANDBOX_BASE",
    "SCOPES",
    "Connection",
    "DeviceContext",
    "HmrcError",
    "Obligation",
    "Tokens",
    "VendorContext",
    "authorization_url",
    "base_url",
    "check_state",
    "fraud_headers",
    "grant_expires_at",
    "grant_has_expired",
    "needs_refresh",
    "new_state",
    "parse_obligations",
    "parse_tokens",
    "reauthorisation_due",
]
