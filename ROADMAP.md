# Vega Roadmap

> **Last updated:** 6 September 2026
> **Update rule:** updated with every structural change, together with
> ARCHITECTURE.md.

Nine phases. Each depends on the one before it, and each ends on a condition that is
checkable rather than felt.

**No deadline.** Vega is built alongside a sibling product, and neither is
racing the other.

## The gate

Every phase opens with **two-way cross-questioning** before any code is written:
recommendations with defaults stated, challenged, then built. A phase that has not
been through that round has not started. This is the same rule used on Copernus, and
it exists because the expensive mistakes in this system are schema-shaped and
therefore made early.

Every exit condition below is also read against the five non-negotiables in
[SECURITY.md](SECURITY.md).

## Phase 0, Foundation

- [x] Selective copy from the upstream fork into `apps/web`: the shadcn
      primitives, the auth surface, and nothing the import closure does not reach
- [x] Strip Lovable boilerplate (`lovable-tagger` removed from the vite config)
- [x] `.env` untracked and `supabase/.temp/` ignored, with `.env.example` committed
- [x] Enumerate which edge functions genuinely need service-role, and which can
      be demoted. The audit itself is held privately: it maps the weakest of 13
      row-level-security bypasses, which is not a thing to publish.
- [x] pnpm workspace for `apps/web`, uv for `apps/api`, both lockfiles committed
- [x] Dependency auditing: `pnpm audit` and `uv lock --check` in CI, Dependabot
      configured for npm, uv and github-actions

**Exit: met.** `make gate` is green from a fresh clone: eslint (0 errors),
`tsc -p tsconfig.app.json --noEmit` over 102 files (0 errors), vite build, ruff,
ruff format, mypy strict, pytest, `pnpm audit`, `uv lock --check`.

Two things the gate surfaced that are worth carrying forward:

- The inherited `tsconfig.json` is a solution-style config with `"files": []`, so
  a bare `tsc --noEmit` compiles **nothing**. The fork's typecheck was vacuous,
  which is how seven real type errors survived in it, including a `Profile`
  interface still declaring a `role` column the table no longer has. The scripts
  target `tsconfig.app.json` deliberately.
- 79 eslint warnings are inherited debt, all explicit `any` in the auth stack plus
  react-refresh export shape. `pnpm lint` runs with `--max-warnings 79`, so the
  number can only go down. (Started at 145; the 65 unused-vars warnings were
  burned down mechanically in September 2026.)

## Phase 1, UK-native schema

- [x] Inherited baseline adopted and proven to rebuild from nothing
- [x] Rebuild with UK shapes: VAT treatment codes, GBP functional with EUR
      presentment and stored rates, commodity codes, EORI, UK addresses
- [x] Batch traceability structure, no behaviour
- [x] Deny-by-default: RLS on every table, no table without a policy, no
      SECURITY DEFINER with a mutable search_path
- [x] Session company context, so a multi-company user's boundary follows the
      session rather than an unordered `LIMIT 1`
- [x] N1 tenant isolation suite, including the same-user-two-companies case
- [x] Hosted Supabase project in London, Postgres 17. All twelve migrations
      applied and every local assertion re-run against it and passing.
- [x] Data restore drill against that project (`make drill`): the London
      database is dumped, restored into a fresh Postgres, and checked on three
      axes, row counts, known values, and whether the tenant boundary still
      holds. Passing. The restore target is local rather than a second hosted
      project, and the reason is printed in the drill's own output rather than
      left implied.

**Exit: met.** Everything provable locally is proven, and the hosted project exists with the schema applied and a restore drill passing against it. `make db-verify`
builds a fresh Postgres 17 from migrations alone and asserts 22 properties;
`make test` runs 15 tenant isolation tests against a real database. 

Seven defects surfaced that no schema-shaped check could have found, because all
four only appear when something writes:

- `companies` was not insertable at all. Its BEFORE INSERT trigger reaches
  `generate_gated_business_ref_no`, which reads a table no migration creates.
  Sign-up runs that path, so a fresh database could not register anybody.
- Once insertable, only **once**: the reference generator returned the same
  value forever against an empty source, and a unique index rejected the second
  company.
- The baseline was dumped with `--no-privileges`, so it carries no grants.
  Without the shim reproducing Supabase's defaults, every query as `anon` or
  `authenticated` failed for lack of privilege, and an RLS suite against that
  would have passed while proving nothing.
- All four company-scoping helpers ended in `LIMIT 1` with no `ORDER BY`.
- `generate_supplier_ref` declares a local variable named `supplier_ref` and
  then queries `WHERE supplier_ref = final_ref`, which PostgreSQL cannot resolve.
  No supplier could be inserted at all.
- Both `postal_code` and `postcode` spellings coexisted after 0006, and
  `sales_orders` ended up with `delivery_postal_code` **and**
  `delivery_postcode`: two columns for one fact.
- A real Supabase `auth.users` does not fit the shim's table, so a naive
  `pg_dump` of it restores zero rows in silence. The drill now carries identity
  references explicitly and fails loudly when none arrive.

## Phase 2, The API service

- [x] FastAPI against the same Postgres through `vega_api`, a role that owns
      nothing (migration 0014, provisioned by `scripts/provision-api-role.sh`)
- [x] Supabase JWT verification against the project's JWKS. The project issues
      **ES256** asymmetric tokens, so the service holds a public key and never a
      shared secret. Algorithm allowlist, issuer and audience all asserted.
- [x] Worker on the session pooler (5432), request paths on the transaction
      pooler (6543), pool bounded. Procrastinate's schema is generated into
      migration 0016 and lives in its own `procrastinate` schema, so the
      migration role owns the queue and `vega_api` does not (N2).
- [x] Seamly's four-file module contract, and the append-only enforcement from
      N2. `security_audit_log`, `transaction_audit_log`, `batch_movements` and
      `fx_rates` refuse UPDATE and DELETE via a trigger that binds **every**
      role including `service_role`, which bypasses RLS but not triggers, plus
      withheld grants as a second layer. Issued-invoice immutability waits for
      Phase 3: `sales_invoices.status` is currently constrained to `'finalized'`
      alone, so there is no draft state to become immutable from. Seamly's
      in-process engine is not carried across and is not needed yet: one module
      does not need a router.
- [x] Schema drift detection, `make drift`. **Not the Alembic check as
      written.** That assumed SQLAlchemy models describing the same tables, and
      there are none: the service uses raw queries, so autogenerate would pass
      vacuously, which is a failure mode this project has hit four times. The
      real risk is a dashboard edit leaving the migrations no longer describing
      production, and nothing could see it because every other check rebuilds
      from the migrations and agrees with itself. `make drift` compares a fresh
      local build against London: currently 1551 objects each side, no drift.
      Reinstate the Alembic check the day models appear.
- [ ] **Deferred out of Phase 2, deliberately.** The Phase 2 round chose
      "demote the three edge functions, defer the rest", so FastAPI does not own
      auth here, and the reason the `any` burn-down was scheduled alongside it
      (the generated OpenAPI client typing the error envelope for free) does not
      apply yet. Both move to whichever phase actually restructures auth.
      Hand-typing 40 handlers against supabase-js shapes before then is
      throwaway work. `--max-warnings` stays at 79 until it lands.
- [x] Demote `gemini-business-assistant` off service-role. 12 of 13 functions
      hold the key, down from 13.
- [ ] Demote `approve-registration` and `reject-registration`. Both act across
      tenants by design and need an admin RLS policy on
      `business_registration_requests` first; demoting without it would break
      them.
- [x] CSP and security headers. Three faults in the inherited policy, and the
      third was not a typo: `connect-src` named the **old Rigel project** so the
      app could not reach Vega's Supabase at all; `script-src` allowed two CDNs
      and `'unsafe-eval'` that nothing uses; and `frame-ancestors` plus
      `X-Frame-Options` were in `<meta>`, **where browsers ignore them**, so the
      page looked protected against clickjacking and was not. Real headers now
      live in `apps/web/public/_headers`.

**Exit:** one endpoint authenticated end to end from the browser; one job that wakes
on NOTIFY and retries; Alembic autogenerate produces an empty diff.

## Phase 3, Invoicing

- [x] Immutable issued invoices and credit notes (#26). Migrations
      `20260906065504_invoice_lifecycle.sql` and `..._invoice_append_only.sql`.
      Every refusal test seeds a row first and asserts the seed worked, because
      a `BEFORE ROW` trigger never fires on an empty table and the suite would
      otherwise pass against a table nothing can be written to.
- [x] Per-company serialised numbering, void by credit note only (#25).
      Migration `20260906065810_invoice_numbering.sql`. Serialises on
      `SELECT ... FOR UPDATE` of the counter row, and the migration proves the
      sequence before it finishes rather than asserting it did.
- [x] EUR on the face of the document with sterling underneath (#89).
      Landed inside #94 and #95, which own the two documents that must show it.
      The rate is the one stored on the document at issue, and the tests pin
      each acceptance item: `test_ubl_output.py:248` (two TaxTotals, EUR face
      and GBP at the stored rate), `test_invoice_pdf.py:92` (EUR on the face,
      sterling beneath with the rate and its date), and the GBP cases
      (`test_ubl_output.py:239`, `test_invoice_pdf.py:109`) that refuse a rate
      of 1.0 on a sterling invoice.
- [ ] PEPPOL BIS 3.0 UBL output, hardened parsing (#27)
- [ ] Server-side PDF rendering (#37)

**Exit:** a generated invoice passes the PEPPOL schematron; a parallel-issue test
produces no gap and no duplicate.

## Phase 4, UK and EU VAT

- [ ] HMRC OAuth and obligation retrieval
- [ ] Boxes 1 to 9 derived from treatment codes
- [ ] Submission with fraud prevention headers
- [ ] Northern Ireland and the EC Sales List
- [ ] EU reverse charge and the VIES adapter, owned by this phase because reverse
      charge needs it at invoice time
- [ ] VIES evidence retained as VAT number, timestamp and result, nothing else

**Exit:** a return accepted in the HMRC sandbox; the submission recorded append-only.

## Phase 5, Reference data

- [ ] Companies House lookup, company and VAT number validation with autofill
- [ ] Postcode lookup
- [ ] Commodity code and EORI checks
- [ ] Reuses the Phase 4 VIES adapter rather than building a second one

**Exit:** a bad registration number or EORI is caught at entry, not at invoice time.

## Phase 6, Carbon

- [ ] Versioned DEFRA and DESNZ factor tables
- [ ] Calculation engine in the service
- [ ] Per-SKU and per-shipment footprints
- [ ] SECR report output

**Exit:** a footprint recomputed against last year's factors returns last year's
number.

## Phase 7, Product compliance

- [ ] The shared provenance spine
- [ ] Authenticated supplier ingestion: per-supplier credentials, PACT v2 validation
      at the boundary, appends through the restricted role
- [ ] Digital Product Passport under ESPR
- [ ] Packaging EPR tonnage
- [ ] EUDR due diligence with geolocation
- [ ] CBAM embedded emissions per consignment
- [ ] Scheduled chain verification

**Exit:** one product traces to source and emits a passport and a due diligence
statement; a tampered or replayed event is caught by chain verification.

## Phase 8, GDPR

- [ ] Retention policies
- [ ] Subject access and erasure, covering EUDR plot coordinates as well as customer
      rows
- [ ] Audit log scoped for UK GDPR rather than inherited wholesale

**Exit:** an erasure leaves the ledger intact and the person unidentifiable.

## Pre-phase research

Every phase opens with a round of confirming assumptions against primary
sources: the regulation as HMRC or the EU currently states it, and the platform
behaviour as the vendor currently documents it. Regulation moves faster than
this document, so a phase that has not been through that round has not started.

Those notes are held privately. They mix regulatory reading, which is useful,
with our own infrastructure and billing posture, which is not something to
publish. Where a finding changed the design, it is in
[docs/decisions/](docs/decisions/) instead, which is the durable record.

