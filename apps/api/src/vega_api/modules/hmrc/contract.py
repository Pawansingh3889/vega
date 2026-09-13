"""Typed shapes for the HMRC connection. No I/O, no secrets in transit."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from enum import StrEnum


class HmrcError(StrEnum):
    """Why a connection could not be made or used."""

    NOT_CONNECTED = "not_connected"
    """This company has never authorised Vega with HMRC."""

    STATE_MISMATCH = "state_mismatch"
    """The callback's `state` is not the one we issued. Treated as hostile."""

    EXCHANGE_REFUSED = "exchange_refused"
    """HMRC refused the authorisation code."""

    REFRESH_REFUSED = "refresh_refused"
    """The refresh token no longer works. The company must reconnect."""

    UNAVAILABLE = "unavailable"
    """HMRC did not answer."""


@dataclass(frozen=True, slots=True)
class Tokens:
    """What HMRC hands back. Held in memory, never logged, never serialised."""

    access_token: str
    refresh_token: str
    expires_at: datetime
    scope: str


@dataclass(frozen=True, slots=True)
class Connection:
    """What a caller may know about a connection. Deliberately no tokens.

    This is what a route may return. If a token is ever needed it is fetched,
    decrypted and used inside one function, and does not travel in a dataclass
    that somebody might log.
    """

    company_id: str
    expires_at: datetime
    scope: str
    environment: str
    connected_at: datetime
    refreshed_at: datetime | None


@dataclass(frozen=True, slots=True)
class DeviceContext:
    """The seven header values only the browser can know.

    HMRC's WEB_APP_VIA_SERVER connection method requires these to be collected
    on the originating device and relayed. Inventing them server-side is the
    specific thing the specification forbids, and HMRC runs automated
    conformance checks: persistently bad data can mean fines and API blocking.

    Every field is required and none has a default, deliberately. A default
    here would be a fabricated value that looks like a collected one, which is
    the failure this whole class exists to make impossible.
    """

    device_id: str
    """Gov-Client-Device-ID. Stable per device, generated in the browser."""

    browser_js_user_agent: str
    """Gov-Client-Browser-JS-User-Agent. As JavaScript reports it, which is not
    necessarily what the User-Agent request header says."""

    screens: str
    """Gov-Client-Screens. Width, height, scaling and colour depth."""

    window_size: str
    """Gov-Client-Window-Size. The window, not the screen."""

    timezone: str
    """Gov-Client-Timezone, as UTC+hh:mm."""

    user_ids: str
    """Gov-Client-User-IDs. Key-value identifiers for accounts the user holds."""

    multi_factor: str
    """Gov-Client-Multi-Factor. MFA statuses for this authentication. Empty
    string is a legitimate value here and is not the same as absent."""


@dataclass(frozen=True, slots=True)
class VendorContext:
    """What the service knows about itself, and about the connection it saw."""

    product_name: str
    version: str
    license_ids: str
    public_ip: str
    forwarded: str

    client_public_ip: str
    """The browser's public IP as THIS server observed it. Not something the
    browser reports about itself: it cannot reliably know, and a value it
    supplied would be a value an attacker could choose."""

    client_public_port: str
    client_public_ip_timestamp: str


@dataclass(frozen=True, slots=True)
class Obligation:
    """One VAT period HMRC expects a return for.

    `period_key` is HMRC's identifier and the only thing that ties a submission
    to the obligation it satisfies, which is why it is carried through to
    `hmrc_submissions` rather than derived from the dates.
    """

    period_key: str
    start: date
    end: date
    due: date
    status: str
    """`O` open or `F` fulfilled, in HMRC's vocabulary rather than ours,
    because a translation here is a place for the two to disagree."""

    received: date | None
