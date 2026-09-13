"""The composition root: the only place the adapters and the modules meet.

Routes translate HTTP into a call and a Result back into HTTP. They hold no
rules. Deleting this file must not require touching a module.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import asdict
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, Header, Request, Response
from fastapi.responses import JSONResponse

from .auth import Caller, TokenVerifier
from .common.db import Database
from .common.errors import Result, UnauthenticatedError, VegaError
from .config import Settings, get_settings
from .cors import configure_cors
from .modules import einvoice, hmrc, vat, vies
from .modules.hmrc import repository as hmrc_repository
from .modules.postcode import lookup_postcode


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    app.state.settings = settings
    app.state.verifier = TokenVerifier(settings)
    app.state.db = Database(settings)
    await app.state.db.connect()
    try:
        yield
    finally:
        await app.state.db.close()


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the application.

    A factory rather than a module-level object, because `cors.py` says the
    composition root must stay importable without environment and the previous
    `configure_cors(app, get_settings())` at import scope read it. That is not a
    style point: importing this module is how anything tests a route, and until
    #82 nothing could without `VITE_SUPABASE_URL` and `VEGA_DATABASE_URL` set.

    Fail-fast is unchanged. Called with no settings, which is how the server
    calls it, this still reads the environment and still refuses to start when a
    variable is missing. What moved is *when*: at startup, where a missing
    variable is a deploy failure, rather than at import, where it is every
    importer's problem.
    """
    settings = settings if settings is not None else get_settings()
    application = FastAPI(
        title="Vega API",
        description="Regulated logic: VAT, e-invoicing, carbon, and scheduled work.",
        lifespan=lifespan,
    )
    configure_cors(application, settings)
    _register(application)
    return application


async def handle_vega_error(_: Request, exc: VegaError) -> JSONResponse:
    """Errors say what went wrong and what to do, never just that something did."""
    return JSONResponse(
        status_code=exc.status,
        content={"error": {"code": exc.code, "message": exc.message}},
    )


def get_verifier(request: Request) -> TokenVerifier:
    """Hand a route the token verifier.

    `lifespan` puts it on `app.state`, and knowing that is this function's whole
    job. A route that reaches into `app.state` itself cannot be exercised
    without an app object populated the way production populates one, which is
    why nothing in this suite had ever called one.
    """
    verifier = request.app.state.verifier
    # `app.state` is untyped, so this both satisfies mypy and refuses loudly if
    # `lifespan` ever puts something else there.
    assert isinstance(verifier, TokenVerifier)
    return verifier


def get_database(request: Request) -> Database:
    """Hand a route the database.

    Deliberately the `Database`, not a live connection. A dependency that yields
    a connection for the lifetime of the request is the fuller version and the
    wrong trade on a bounded pool: it would stay checked out through response
    serialisation. `acting_as` stays in the route, holding one for exactly as
    long as it did before.
    """
    database = request.app.state.db
    assert isinstance(database, Database)
    return database


def get_address_key(request: Request) -> str | None:
    """Hand a route the getAddress.io key, which may be unset.

    Same reasoning as `get_verifier`: `app.state` is untyped, the assert
    satisfies mypy and refuses loudly if `lifespan` ever puts something else
    there, and a route that reaches into `app.state` itself cannot be called
    in a test without an app built the way production builds one.

    Optional since #92. Postcode lookup is a convenience and a deployment
    choosing not to use it is normal, so a missing key is refused at the point
    of use, not at startup.
    """
    settings = request.app.state.settings
    assert isinstance(settings, Settings)
    return settings.getaddress_api_key


async def current_caller(
    verifier: Annotated[TokenVerifier, Depends(get_verifier)],
    authorization: Annotated[str | None, Header()] = None,
    x_vega_company: Annotated[str | None, Header()] = None,
) -> Caller:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise UnauthenticatedError(
            "This endpoint needs a signed-in session. Send the Supabase access "
            "token as 'Authorization: Bearer <token>'."
        )
    return verifier.verify(authorization.split(" ", 1)[1].strip(), x_vega_company)


async def health() -> dict[str, str]:
    """Liveness only. It deliberately does not touch the database: a health
    check that fails on a slow query takes the service down for the wrong
    reason."""
    return {"status": "ok"}


async def vat_preview(
    period_start: date,
    period_end: date,
    caller: Annotated[Caller, Depends(current_caller)],
    db: Annotated[Database, Depends(get_database)],
) -> JSONResponse:
    """Boxes 1 to 9 for a period.

    Derivation only. Submission to HMRC needs recognition of the software, so
    this returns figures an accountant files. See ROADMAP Phase 4.
    """
    async with db.acting_as(caller) as conn:
        result = await vat.preview_return(conn, period_start, period_end)

    if not result.ok:
        return JSONResponse(
            status_code=422,
            content={"error": {"code": result.code, "message": result.message}},
        )
    assert result.value is not None
    return JSONResponse(content={"data": _jsonable(asdict(result.value))})  # type: ignore[call-overload]


async def hmrc_status(
    caller: Annotated[Caller, Depends(current_caller)],
    db: Annotated[Database, Depends(get_database)],
) -> JSONResponse:
    """Whether this company can file, and how long that stays true.

    Read only, and deliberately the first route this module gets. The grant
    behind an MTD connection dies after eighteen months whether or not anybody
    is watching, and it dies quietly: the tokens keep refreshing right up until
    they do not. A company that finds out at the filing deadline has missed it.

    No tokens are returned, encrypted or otherwise. `Connection` exists to be
    the shape a route may hand back, and the tokens are not in it.
    """
    if caller.requested_company is None:
        return JSONResponse(
            status_code=422,
            content={
                "error": {
                    "code": "company_required",
                    "message": (
                        "Send X-Vega-Company. An HMRC connection belongs to one "
                        "company and there is no sensible default."
                    ),
                }
            },
        )

    async with db.acting_as(caller) as conn:
        connection = await hmrc_repository.load_connection(conn, caller.requested_company)

    if connection is None:
        return JSONResponse(content={"data": {"connected": False}})

    # One clock read, used for every comparison below. Reading `now` twice can
    # answer two questions about two different instants, which is how a status
    # ends up self-contradictory at a boundary.
    now = datetime.now(UTC)
    return JSONResponse(
        content={
            "data": {
                "connected": True,
                "environment": connection.environment,
                "scope": connection.scope,
                "connected_at": connection.connected_at.isoformat(),
                "access_token_expires_at": connection.expires_at.isoformat(),
                "access_token_needs_refresh": hmrc.needs_refresh(connection.expires_at, now=now),
                # The eighteen month wall. `grant_expires_at` is measured from
                # `connected_at` because that is the moment we can observe. See
                # #109 q1: HMRC has been asked what it actually runs from, and
                # until they answer this is an assumption, stated rather than
                # hidden.
                "grant_expires_at": hmrc.grant_expires_at(connection.connected_at).isoformat(),
                "reauthorisation_due": hmrc.reauthorisation_due(connection.connected_at, now=now),
                "grant_has_expired": hmrc.grant_has_expired(connection.connected_at, now=now),
            }
        }
    )


async def postcode_lookup_route(
    postcode: str,
    caller: Annotated[Caller, Depends(current_caller)],
    address_key: Annotated[str | None, Depends(get_address_key)],
) -> JSONResponse:
    """Addresses for a UK postcode, from getAddress.io.

    The key stays server side: a lookup key in the browser is one view-source
    away from somebody else's free tier. Issue #38.

    503 rather than 422 when the key is unset: the problem is deployment
    configuration, not the request, and the two must not read alike. The
    message names the variable, because that is what the operator can act on.
    """
    if address_key is None:
        return JSONResponse(
            status_code=503,
            content={
                "error": {
                    "code": "not_configured",
                    "message": (
                        "Postcode lookup is not configured on this deployment: "
                        "set GETADDRESS_API_KEY. Manual address entry keeps "
                        "working."
                    ),
                }
            },
        )

    result = await lookup_postcode(postcode, address_key)

    if not result.ok:
        return JSONResponse(
            status_code=422,
            content={"error": {"code": result.code, "message": result.message}},
        )
    assert result.value is not None
    # asdict + _jsonable, the same as vat_preview two routes up. Without it,
    # JSONResponse hands a raw PostcodeLookupResult dataclass straight to
    # json.dumps, which does not know how to serialise one: every SUCCESSFUL
    # lookup 500s with "Object of type PostcodeLookupResult is not JSON
    # serializable". Every existing test mocked lookup_postcode to return a
    # plain dict, so this route has never actually been proven to work.
    return JSONResponse(content={"data": _jsonable(asdict(result.value))})  # type: ignore[call-overload]


async def check_customer_vat(
    customer_id: UUID,
    caller: Annotated[Caller, Depends(current_caller)],
    db: Annotated[Database, Depends(get_database)],
) -> JSONResponse:
    """Check a customer's VAT number against VIES and record the evidence.

    POST rather than GET: this calls a third party and writes the outcome, so
    it is neither safe nor idempotent in the sense a cache would assume.

    The tenant boundary is the database's, as everywhere else. `acting_as`
    means a customer outside the caller's company is simply not found, rather
    than this route deciding who may look.
    """
    async with db.acting_as(caller) as conn:
        return _vies_response(await vies.validate_customer_vat(conn, customer_id))


async def check_supplier_vat(
    supplier_id: UUID,
    caller: Annotated[Caller, Depends(current_caller)],
    db: Annotated[Database, Depends(get_database)],
) -> JSONResponse:
    """Check a supplier's VAT number against VIES and record the evidence."""
    async with db.acting_as(caller) as conn:
        return _vies_response(await vies.validate_supplier_vat(conn, supplier_id))


def _vies_response(result: Result) -> JSONResponse:
    """One place that turns a VIES Result into HTTP, for both routes.

    422 for every refusal, matching /vat/preview. The distinction that matters
    to a caller is in the code: `unavailable` means VIES did not answer and
    nothing was recorded, which is not the same as `invalid`, and a caller must
    not treat the first as evidence of the second.
    """
    if not result.ok:
        return JSONResponse(
            status_code=422,
            content={"error": {"code": result.code, "message": result.message}},
        )
    assert result.value is not None
    return JSONResponse(content={"data": result.value})


async def invoice_ubl(
    invoice_id: UUID,
    caller: Annotated[Caller, Depends(current_caller)],
    db: Annotated[Database, Depends(get_database)],
) -> Response:
    """One issued invoice as a PEPPOL BIS 3.0 UBL document.

    Returns XML, not JSON. The caller is sending this to a customer's accounts
    system, so the bytes are the product; wrapping them in a JSON envelope
    would mean every consumer unwraps and re-encodes, and re-encoding XML is
    how a document stops matching the one that was validated.

    A refusal is JSON, because a refusal is not a document.
    """
    async with db.acting_as(caller) as conn:
        result = await einvoice.emit_invoice(conn, invoice_id)

    if not result.ok:
        return JSONResponse(
            status_code=404 if result.code == "not_found" else 422,
            content={"error": {"code": result.code, "message": result.message}},
        )

    assert isinstance(result.value, str)
    return Response(
        content=result.value,
        media_type="application/xml",
        headers={"Content-Disposition": f'attachment; filename="invoice-{invoice_id}.xml"'},
    )


async def invoice_pdf(
    invoice_id: UUID,
    caller: Annotated[Caller, Depends(current_caller)],
    db: Annotated[Database, Depends(get_database)],
) -> Response:
    """One issued invoice as a PDF, rendered server side.

    SPEC.md 3.4 and N3: the server produces what gets filed, and a document
    assembled in the browser is one the browser could have got wrong.

    `inline` rather than `attachment`, unlike the UBL. This one is meant to be
    looked at before it is sent; the XML is only ever a file.
    """
    async with db.acting_as(caller) as conn:
        result = await einvoice.render_invoice_pdf(conn, invoice_id)

    if not result.ok:
        return JSONResponse(
            status_code=404 if result.code == "not_found" else 422,
            content={"error": {"code": result.code, "message": result.message}},
        )

    assert isinstance(result.value, bytes)
    return Response(
        content=result.value,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="invoice-{invoice_id}.pdf"'},
    )


def _jsonable(value: object) -> object:
    """Decimals and dates travel as strings.

    A VAT figure serialised as a float is a rounding bug waiting for a quarter
    end, so money leaves this process in the same form it was computed.
    """
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jsonable(v) for v in value]
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, Decimal):
        return str(value)
    return value


def _register(application: FastAPI) -> None:
    """Attach the handlers and routes.

    Separate from `create_app` so the route functions stay plain functions,
    declared once and readable without a decorator's worth of indirection.
    """
    # Starlette types the handler argument as taking a bare Exception, so a
    # handler narrowed to VegaError does not match. External-library gap.
    application.add_exception_handler(VegaError, handle_vega_error)  # type: ignore[arg-type]
    application.get("/health")(health)
    application.get("/api/v1/vat/preview")(vat_preview)
    application.get("/api/v1/hmrc/status")(hmrc_status)
    application.get("/api/v1/postcode/lookup")(postcode_lookup_route)
    application.post("/api/v1/customers/{customer_id}/vat-check")(check_customer_vat)
    application.post("/api/v1/suppliers/{supplier_id}/vat-check")(check_supplier_vat)
    application.get("/api/v1/invoices/{invoice_id}/ubl")(invoice_ubl)
    application.get("/api/v1/invoices/{invoice_id}/pdf")(invoice_pdf)
