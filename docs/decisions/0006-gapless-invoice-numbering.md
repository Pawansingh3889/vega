# 0006. Gapless invoice numbering by counter row

**Date:** 6 September 2026
**Status:** Accepted

## Context

SECURITY.md N5 requires invoice numbers to serialise per company, with no gaps
and no duplicates. The defect it guards against surfaces during a filing
reconciliation, which is the worst possible moment: a gap invites the question
"what happened to invoice 1042", and a duplicate means two documents claim to be
the same one.

Three mechanisms were available.

## Decision

**A counter row per company, allocated under `SELECT ... FOR UPDATE`.**

A number is taken at **issue**, not at creation, so an abandoned draft leaves no
gap.

## Why this one

The row *is* the sequence. Reading the next number requires taking the lock that
serialises it, so an allocation path cannot forget to lock. That property is
worth more than elegance here, because the failure mode of forgetting is silent
until it is expensive.

## Alternatives rejected

**Per-company advisory lock** (`pg_advisory_xact_lock`). No extra table, releases
automatically at transaction end, and genuinely lighter. Rejected because the
lock and the allocation are separate steps: a new code path that allocates
without locking compiles, passes review, and works fine until two invoices are
issued in the same second.

**A Postgres `SEQUENCE`.** Not a candidate. Sequences deliberately do not
roll back, so a failed transaction burns a number. That is the right behaviour
for a surrogate key and the wrong behaviour for a document number somebody has
to account for.

## Consequences

- One contended row per company. At this scale, nothing; at a scale where it
  matters, the contention is per tenant rather than global.
- The counter table is itself tenant data and needs row level security and a
  tenant isolation test, like every other table (N1).
- A concurrency test is not optional. The defect only appears under contention,
  so a test that issues invoices sequentially proves nothing. Phase 3's exit
  criterion names this test directly.
