# Vega Security

> **Last updated:** 4 September 2026 (rev 2)
> **Update rule:** a non-negotiable is added or changed here before it is relied on
> anywhere else.

The standing rules every phase is measured against. Each one is enforced by a
test or a migration rather than by review, so the build tells you before a
person has to.

Vega is a fork, and the audit of what was inherited from upstream is held
privately rather than here: it describes a system that is not ours and that we
cannot confirm is retired, and publishing a map to somebody else's exposure is
not ours to do. The fixes it produced are all in `supabase/migrations`, and the
non-negotiables below are what keep them from being undone.

---

# The six non-negotiables

These are not phase work. Every exit condition in [ROADMAP.md](ROADMAP.md) is read
against them, and each exists because the Rigel work already demonstrated the failure
it prevents.

## N1. Deny by default, proven in CI

Rigel did not prove that row level security works. It demonstrated how RLS fails
**silently**: a `SECURITY DEFINER` helper referencing a dropped column returned empty
result sets instead of an error, and a human found it by clicking a menu item.

Therefore:

- A **generated** test asserting tenant A can never read or write tenant B, for every
  table, so a new table without coverage fails the build rather than passing quietly.
- The same suite covers **one auth user who belongs to two companies**, asserting the
  boundary flips with the session's company context. Rigel's accounts are
  multi-business, so this is the realistic tenancy defect, and it is a different bug
  from two separate users. A policy keyed on `auth.uid()` alone passes the
  two-user test and fails this one.
- A table template where RLS enabled plus no permissive policy means **blocked**.
  Open is never the default state.
- Every `SECURITY DEFINER` function pins `SET search_path`, checked by CI rather than
  by review.
- **No table carries a `FOR SELECT TO public` policy** unless it is deliberately
  public, and that intent is asserted in CI rather than assumed from the absence
  of a complaint.
- No policy calls a helper that has no test of its own.

## N2. Append-only by grants, and the API role owns nothing

> **Enforced since migration 0017.** `security_audit_log`,
> `transaction_audit_log`, `batch_movements` and `fx_rates` refuse UPDATE and
> DELETE. Issued invoices and credit notes follow in Phase 3, when issuing
> becomes a real transition rather than a column constrained to one value.

Trigger plus withheld grants, the pattern proven in Seamly, applied to:

- issued invoices and credit notes
- the VAT submission record
- passport and DPP events
- the carbon result ledger
- the audit log

The corollary matters more than the rule. **A table owner bypasses RLS** unless
`FORCE ROW LEVEL SECURITY` is set. So the FastAPI role never owns a table, and the
migration role that creates tables never lingers in the application's connection
string. A migration role left in a running service is a quiet full bypass.

## N3. The server produces every number, offline included

The inherited IndexedDB layer replays client mutations. Left alone, that puts
client-computed figures onto invoices, and those are the figures filed with HMRC.

- The sync protocol recomputes server side on receipt.
- A client-supplied figure is a **claim**, not a result.
- Anything rendered from cache is marked non-authoritative in the UI.

Without this, the offline feature is an integrity bypass rather than a convenience.

The Content Security Policy is the other half of the same rule. A `connect-src`
allowlist keeps the app from reaching an origin nobody approved, which is what a
compromised dependency reaches for first. Phase 2 sets it, and a mismatched policy
fails loudly and confusingly rather than silently, which is the behaviour you want.

## N4. All inbound XML is hostile

UBL, XRechnung and Factur-X are XML.

- Entity expansion disabled, DTD loading off.
- Size and depth caps enforced at the boundary.
- The koSIT and Mustangproject validators are JVM processes, so they run as
  **sandboxed sidecars** with no network egress and no database credentials. A JVM
  with network access sitting next to the ledger is its own finding.

## N5. Money sequences serialise per company

Allocating a number in the database is necessary and not sufficient.

- Two concurrent invoices for one company take a per-company advisory lock, or a
  counter row held under a row lock.
- Issued rows are never deleted and never renumbered.
- A void is a credit note.

This is the classic duplicate-and-gap defect, and it surfaces during a filing
reconciliation, which is the worst possible moment to find it.

## N6. Security-relevant failures are never swallowed and are alertable

Migration 344 exists because a function discarded an error and a control "never
fired". The root cause was not the missing index. It was that the sign-in function
caught a `42P10`, PostgREST turned it into a 400, and the code carried on as though
the lockout had been recorded. Nobody could have noticed, because nothing said so.

- Auth failures, lockout writes, chain verification failures, Alembic drift and
  restore drills surface in server-side logs with alerting attached.
- No function catches an error and continues as if the control held.
- **If a control cannot report its own failure, it does not count as a control.**

The test for this rule is not whether the control works. It is whether you would find
out on the day it stops.

---

# One hole we opened on purpose

## The developer override

`developer_access` lists accounts that may act in **any** company by setting the
`x-vega-company` header, without being a member of it. It exists so the product
can be inspected across tenants while it is being built.

This is a real cross-tenant hole. It is written down here rather than left as a
surprise.

**What keeps it narrow:**

- It is expressed inside `current_company_id()`, the same helper the policies
  already use, so it cannot reach further than a policy does. It is not
  `BYPASSRLS`.
- Still one company at a time. A developer picks a company and everything
  behaves exactly as it does for a real user, so screens and reports work
  normally and nothing sees every tenant at once.
- **A company must be explicitly requested.** A developer with no header gets
  their own memberships like anybody else, so the override never fires by
  accident.
- `expires_at` is NOT NULL and enforced in the database, so a lapsed grant stops
  working whether or not anyone remembers to delete it.
- The table is unreachable through the API. Who holds a backdoor is not
  something a signed-in user may enumerate.

**What it does not have:** a per-query audit trail. `current_company_id()` is
evaluated inside policy checks, potentially per row, and writing an audit row
there would be a performance disaster. The grant is the record: who, why, and
until when.

**Managing it:** `./scripts/grant-developer.sh [grant|revoke|list]`.

**Removing it entirely:** delete the rows, then restore 0010's definition of
`current_company_id()` and drop the table. That is one migration, which is why
the override lives in its own table rather than being spread through 96
policies.

Six tests in the tenant isolation suite cover it: that it works when invoked,
that it does not fire without a header, that expiry is enforced, that granting
one account widens nobody else, that the table is unreadable, and that a grant
cannot be immortal.

---

## Reporting a vulnerability

**Please report privately, never in a public issue**, using
[GitHub Security Advisories](https://github.com/Pawansingh3889/vega/security/advisories/new).
That gives us a private thread and, if it turns out to be real, a CVE and a
credit line with your name on it.

If you cannot use advisories, email pawankapkoti3889@gmail.com with `VEGA
SECURITY` in the subject.

**What to expect.** Vega is maintained by one person and is pre-release, so
please be patient with the timings rather than assuming you have been ignored:

| | |
|---|---|
| Acknowledgement | Within 5 working days |
| First assessment | Within 14 days |
| Fix or a stated plan | Depends on severity, and you will be told which |

**Please do include** the version or commit, what an attacker gains, and a
reproduction if you have one. A report with a clean reproduction and no exploit
is just as welcome as one with an exploit.

**Please do not** test against the hosted Supabase project or any live company's
data. Build a local instance: `make setup` then `make db-verify` gives you a
throwaway Postgres from the migrations, which is the right place to demonstrate
anything about row level security.

**Scope.** Anything touching the six non-negotiables above, tenant isolation,
the audit ledgers, or a filed VAT figure is in scope and taken seriously.

Vega is a fork, and a private audit already catalogues what was inherited from
upstream, so some findings in the inherited surface are known. You have no way
to see that list, which is not your problem: please report anyway. You will be
told promptly if it is already on it, and a report that an inherited defect is
*worse* than the audit says is a real finding either way.

**Credit.** Anyone who reports a valid vulnerability is credited in the advisory
and in the contributors table in the README, unless they would rather not be.
Please say which you prefer.

**Safe harbour.** Report in good faith, stay within the scope above, and do not
access or destroy anyone else's data, and we will not pursue anything against
you and will treat you as helping rather than attacking.
