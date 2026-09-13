# Vega Architecture

> **Last updated:** 4 September 2026
> **Update rule:** this file changes with every structural change. If the shape of
> the system moves and this file does not, the change is not finished.

## 1. Helicopter view

Vega is **one Postgres with two consumers**. Supabase owns identity, storage and
ordinary CRUD, which the React client reaches directly. A FastAPI service owns
everything that has to be auditable, scheduled or long running, and reaches the same
database through a role that owns nothing.

```
  ┌──────────────────────┐        ┌───────────────────────────┐
  │  apps/web            │        │  apps/api                 │
  │  React 18, Vite 7    │        │  FastAPI, SQLAlchemy 2    │
  │  shadcn, TanStack    │        │  Procrastinate worker     │
  └──────────┬───────────┘        └─────────────┬─────────────┘
             │ supabase-js                      │ asyncpg
             │ anon key + user JWT              │ dedicated role, owns nothing
             ▼                                  ▼
  ┌──────────────────────────────────────────────────────────┐
  │        Supabase Postgres, eu-west-2 London               │
  │        RLS on every table  ·  append-only audit log      │
  └──────────────────────────────────────────────────────────┘
```

The client never computes a figure that reaches a return or a disclosure. That rule
is why the service exists at all.

## 2. Why Supabase is kept, and why it is not enough

**Kept:** the fork's 262 components call `@supabase/supabase-js` directly. Replacing
it means rewriting the entire data layer, which discards the reason for forking
rather than starting fresh. Supabase also has a London region, so UK data residency
is a region setting rather than an architecture.

**Not enough:** Edge Functions are short-lived Deno workers with no queue, no retry
and no long-running compute. Three obligations need all three:

| Need | Why a worker cannot serve it |
|---|---|
| Auditable | An HMRC submission is a legal filing. It needs a durable record of what was sent, when, and by whom, written server side. |
| Scheduled | VAT obligations arrive on a calendar. Conversion factors are republished annually. Neither waits for a browser. |
| Trusted | A figure that goes on a return or a disclosure is produced by the server, never by a client holding an anon key. |

## 3. Why Python for the service

Two reasons outweigh the loss of shared types with React.

1. **Seamly is already Python.** Its four-file module contract, its in-process
   engine and its database-enforced append-only audit trigger arrive as working
   code rather than as inspiration.
2. **Money.** `Math.round(1.005 * 100)` returns 100, not 101, because 1.005 is
   not exactly representable in binary floating point. Numbers filed with HMRC
   belong in `Decimal`, not in a float defended against by hand.

The cost is real: no compile-time contract between the React app and the service.
The mitigation is ordinary. Generate an OpenAPI client from FastAPI into the
frontend and fail CI when the two drift.

See [ADR 0002](docs/decisions/0002-python-for-the-service.md).

## 4. Module contract

`apps/api` follows Seamly's contract. One module is one business capability, four
files:

```
modules/<name>/
├── __init__.py    handle(event, state) -> Result; PERMISSIONS dict
├── contract.py    typed dataclasses; no secrets
├── service.py     pure rules; no I/O, enforced by import-linter
└── repository.py  all I/O; owns its tables on the shared metadata
```

The purity of `service.py` is enforced, not reviewed. A rule module that reaches for
SQLAlchemy, httpx or a repository fails the build, transitively as well as directly.
A VAT box is arithmetic over typed rows, so it belongs in `service.py` and must be
testable without a database.

## 5. Layering rules

| # | Rule | Enforced by |
|---|---|---|
| 5.1 | No module imports a sibling | import-linter independence contract |
| 5.2 | No I/O in `service.py` | import-linter forbidden contract |
| 5.3 | The FastAPI role owns no tables | migration review, and a grants assertion in CI |
| 5.4 | The client computes no filed figure | code review, plus the offline rule in SECURITY.md N3 |
| 5.5 | ARCHITECTURE.md changes with the structure | doc freshness check |

## 6. Connection modes, pinned deliberately

Procrastinate's worker wakes on `LISTEN/NOTIFY`, which does **not** survive
Supabase's transaction-mode pooler on port 6543. Left unstated, jobs silently
degrade to poll intervals or never fire.

| Path | Connection |
|---|---|
| Procrastinate worker | Direct connection, or session-mode pooler |
| API request handlers | Transaction pooler |
| Migrations | Direct connection, migration role, not the application role |

Two consequences to check before Phase 2. Supabase direct connections are IPv6-only
unless the IPv4 add-on is held. And Fly London plus AWS `eu-west-2` is the same city
across two clouds, which is fine at this scale and is still a reason to bound the
connection pool explicitly, because worker fan-out generates connection storms.

## 7. One schema, two writers

Migrations are owned by the Supabase CLI and live in `supabase/migrations`. The
SQLAlchemy models in `apps/api` describe the same tables, which makes two writers
for one schema. CI runs Alembic autogenerate in diff mode and fails on any drift.
Alembic never authors a migration here; it only detects disagreement.

## 8. Repository shape

One repository, because a schema change touches both apps and should arrive as one
pull request.

```
vega/
├── apps/
│   ├── web/          React, pnpm, pnpm-lock.yaml committed
│   └── api/          FastAPI, uv, uv.lock committed
├── supabase/
│   └── migrations/   the single schema history
└── docs/
    └── decisions/    architecture decision records
```

## 9. Provenance

Vega is a fork, taken for its React components rather than its schema. The
schema is rebuilt UK-native on top of a frozen baseline,
`supabase/migrations/00000000000000_inherited_baseline.sql`, which is a record of
what was inherited and is never edited. Every fix on top of it is a separate,
reviewable migration.

The audit of what the baseline carries that must not travel forward is held
privately, because it describes an upstream system that is not ours. The fixes
it produced are all in `supabase/migrations`, and the non-negotiables in
[SECURITY.md](SECURITY.md) are what keep them from being undone.
