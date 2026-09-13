# 0005. One repository, two applications

**Date:** 4 September 2026
**Status:** Accepted

## Context

Vega has a React frontend and a Python service that describe the same tables. The
house convention is one flat directory per repository under `~/projects`.

## Decision

One repository, `~/projects/vega`, holding `apps/web`, `apps/api` and `supabase/`
with the single migration history at the root.

## Rationale

A schema change touches both applications and should arrive as one pull request. Two
repositories turn that into two pull requests and an ordering problem, which is
exactly the coordination cost this product cannot afford during a filing period.

## Alternatives rejected

**Two repositories, `vega` and `vega-api`.** Matches the flat convention exactly and
gives each a clean toolchain. Rejected for the split-pull-request problem above.

**Keep the fork's layout, add `api/` alongside.** Least churn in Phase 0, but the
repository root stays a Vite project pretending to be the whole system.

## Consequences

- Two toolchains in one repository: pnpm for web, uv for api. Both lockfiles
  committed.
- CI must run both suites and know which paths trigger which.
- One schema, two writers. Alembic runs in diff mode to detect drift; it never
  authors a migration.
