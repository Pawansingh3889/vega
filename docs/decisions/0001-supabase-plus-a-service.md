# 0001. Supabase plus a separate service, not Supabase alone

**Date:** 4 September 2026
**Status:** Accepted

## Context

Vega forks a codebase whose 262 components call `@supabase/supabase-js` directly.
The new scope adds MTD VAT submission, PEPPOL e-invoicing and carbon calculation,
which are auditable, scheduled and long running in a way ordinary CRUD is not.

## Decision

Keep Supabase for identity, storage and CRUD, in the `eu-west-2` London region. Add
a separate FastAPI service that owns the regulated work, reaching the same Postgres
through a role that owns nothing. Background work runs on Procrastinate in that same
database.

## Alternatives rejected

**Supabase alone, with Edge Functions.** Short-lived Deno workers with no queue, no
retry and no long-running compute. An HMRC submission needs a durable server-side
record, a VAT obligation arrives on a calendar, and a Scope 3 calculation cannot run
in a browser holding an anon key.

**Neon, Drizzle and a service.** Cleaner separation and a nicer migration story, but
it means rebuilding auth, storage and row level security that already work.

**Hasura or Directus.** Replaces the layer being kept and not the layer that is
missing. The VAT and carbon services still have to be written by hand.

**PocketBase or Appwrite.** A downgrade on Postgres, which is the one component this
product cannot compromise on.

**Self-hosted Supabase on a UK VPS.** Defensible if a client demands it, and the
option stays open because the database is plain Postgres either way.

## Consequences

- Two runtimes to deploy and observe.
- Connection modes must be pinned deliberately, because Procrastinate's worker needs
  `LISTEN/NOTIFY`, which the transaction pooler does not carry.
- Data residency becomes a region setting rather than an architecture.
