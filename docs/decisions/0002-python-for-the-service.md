# 0002. Python and FastAPI for the service layer

**Date:** 4 September 2026
**Status:** Accepted

## Context

The service in ADR 0001 needs a language. The frontend is TypeScript, which argues
for one language across the repository. Seamly, the sibling product, is Python.

## Decision

FastAPI with SQLAlchemy 2, managed by uv, linted with ruff, tested with pytest.

## Rationale

**Reuse.** Seamly's four-file module contract, its in-process engine and its
database-enforced append-only audit trigger arrive as working code rather than as
inspiration.

**Money.** Float rounding, recorded once already and worth not rediscovering:
`Math.round(1.005 * 100)` returns 100, not 101, so a reconciliation silently
disagrees by a penny. Numbers filed with HMRC belong in `Decimal`.

**Optionality.** Two Python services sharing a module contract can merge later
almost mechanically if Vega and Seamly converge. A TypeScript service closes that
door on day one.

**House default.** Python is the default toolchain across these repositories.

## Alternatives rejected

**NestJS with Drizzle.** One language, compile-checked types frontend to backend.
Nothing reuses from Seamly, and float rounding has to be defended against by hand in
code that files tax returns.

**Hono with Drizzle.** The same benefits with far less framework, and the same two
costs.

**Litestar.** Better dependency injection than FastAPI and arguably a neater fit for
the module contract, but it diverges from Seamly, which weakens the reuse argument
that made Python attractive in the first place.

## Consequences accepted

No compile-time contract between the React app and the service. Mitigated by
generating an OpenAPI client from FastAPI into the frontend and failing CI on drift.
Two toolchains in one repository: pnpm for web, uv for api.
