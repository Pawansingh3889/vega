# Changelog

All notable changes to this project are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- The claim check no longer blocks work it was never meant to. It refused every
  Dependabot pull request, because a bot does not write `Closes #<n>` and never
  will, and it refused every pull request against an issue carrying no `lane:`
  label. Lanes were an internal scheduling scheme that does not exist in this
  repository, so a contributor could take a `good first issue`, finish it, open
  a PR, and be told their issue "has no lane, so nobody owns it" followed by a
  command to add a label that cannot be added. A dead end at the last step,
  after the work was done. One PR per issue and the duplicate detection, which
  are the parts that earn their keep, are unchanged.

### Added
- Added `scripts/check-links.py` to the gate to catch relative Markdown links that point to missing files.
- **`LICENSE`: GNU AGPL-3.0.** The repository had no licence file, which meant
  nobody could legally use or contribute to it. AGPL rather than a permissive
  licence because Vega is a system of record for somebody's business, and the
  copyleft is what guarantees a company running it can always get at, and keep,
  the code its books depend on. Section 11 of the same licence grants any patent
  reading on Vega to every recipient, which is a deliberate trade and is written
  up in `docs/going-public.md`.
- `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `GOVERNANCE.md` and
  `SUPPORT.md`. `GOVERNANCE.md` carries the contributor to triager to maintainer
  route, so that sustained work visibly leads somewhere, and says which
  decisions the lead maintainer keeps (`SPEC.md`, `SECURITY.md`, the phases) and
  why.
- A feature request issue template, and Discussions, the Code of Conduct and
  `CONTRIBUTING.md` in the issue chooser.
- Contributor recognition: `.all-contributorsrc` and a contributors table in the
  README, covering documentation, review, design and bug reports rather than
  commits alone.
- `docs/going-public.md`: the ordered checklist for opening the repository,
  including the patent timing constraint (UK novelty is absolute, so a filing
  has to precede publication) and the audit of all 147 commits for secrets.

### Changed
- `SECURITY.md` reporting is a real policy: private advisory route, response
  times, scope, safe harbour, and credit for reporters. It previously said only
  that the repository was private.
- `SECURITY.md` is headed "Six non-negotiables", which is how many it defines.
  It said five, and so did the README, while N1 to N6 have been there for some
  time.
- `START-HERE.md` is written for a contributor working from a fork. It used to
  open with two rules that only made sense inside the maintainer's own clone,
  so the first thing a newcomer met was a rule they could not follow.
- `CONTRIBUTING.md` opens with a fork-to-PR walkthrough, and adds what review
  here is like and how contribution is recognised.
- The README quick start described Phase 0 and said there was nothing to run.
  It now builds and runs the app, which has been true since Phase 1.

### Fixed
- The XI VAT number no longer appears on domestic Northern Ireland invoices.
  HMRC ties the XI prefix to supplies to an EU customer, explicitly *in
  addition to* what a normal invoice to a Northern Ireland customer carries, so
  the test is northern-ireland **and** ec-sales-list, which is `XI_ICS` alone.
  An NI company with no XI number can now invoice its neighbours again.
- The postcode lookup no longer reports our own bugs as "the provider is
  down". A bare `except Exception` turned any defect inside the request, a
  typo, a `KeyError`, a wrong column, into `unavailable`. The four specific
  handlers stay; everything else now surfaces.
- `GET /api/v1/invoices/{id}/ubl` and `/pdf` no longer fail on their first
  real call. `einvoice/repository.py` joined `sales_invoice_items` on
  `invoice_id`; the column is `sales_invoice_id`. Every repository query is now
  executed against a database built from the migrations, which is what neither
  this defect nor the identical one in `vat/repository.py` had.
- `VEGA_CORS_ORIGINS` is read, and the comma separated form the docstring
  promises is accepted. `Settings` has no `env_prefix`, so the documented
  variable was silently ignored while origins stayed at localhost, and the
  documented format raised. A deploy following the docs would have had every
  browser call refused at the preflight, where nothing reaches the service to
  be logged. Added to `.env.example`, which had never mentioned it.
- Routes are handed the token verifier and the database through `Depends`
  instead of reaching into `app.state` for them. `app.state` now appears only in
  `lifespan` and in the two providers, which is where knowing about it belongs.
  Route behaviour is unchanged, including how long a pooled connection is held.
- The composition root is importable without an environment again, which
  `cors.py` says it must be and which `configure_cors(app, get_settings())` at
  module scope had broken. `create_app(settings)` is now a factory, and both
  `Dockerfile` and `fly.toml` launch it with `--factory`. A missing variable
  still refuses at startup; it just no longer refuses at import.
- The `database` gate no longer flakes. `verify-baseline.sh` and
  `replay-inherited.sh` waited on `pg_isready`, which reports ready against the
  temporary server the Postgres image runs its init scripts on, moments before
  that server is shut down and restarted. Both now wait for two real queries a
  second apart, the rule `apps/api/tests/conftest.py` already used, and refuse
  loudly instead of continuing when the database never arrives.

### Added
- The eighteen month HMRC authorisation wall is now calculable:
  `grant_expires_at`, `reauthorisation_due` and `grant_has_expired`. Calendar
  months rather than a day count, and the warning fires a VAT quarter ahead so
  it cannot first be seen on filing day.
- `make prove` breaks each gate check on purpose and confirms it refuses.
  REVIEWING.md asks that a new check be proven able to fail; this turns that
  from a claim about the day it was written into something runnable, and it
  refuses to start on a dirty tree because it restores with `git checkout`.
- `hmrc_submissions`, the append-only record Phase 4 files into: what was
  sent, when, by whom, and the response. It deliberately holds no fraud
  prevention headers, because those are a device fingerprint of a named person
  and an append-only table is the wrong place for data Phase 8 must erase.
- HMRC fraud prevention headers (v3.3, `WEB_APP_VIA_SERVER`) and VAT
  obligation retrieval. The seven browser-collected values are required inputs
  with no defaults, and a blank one refuses rather than being sent, because a
  header present but empty reports as collected data that was never collected.
- HMRC OAuth: `hmrc_credentials` storage and the authorisation flow, written
  and proven without an HMRC account. Tokens are encrypted by the service
  before they reach Postgres, so the database holds ciphertext and never the
  key, and `authenticated` is granted no access to the token columns at all.
- A way to apply migrations to the hosted project, which did not exist:
  `make db-status` says what is pending and changes nothing, `make db-push`
  applies it and then proves the drift is gone rather than trusting the push's
  exit code. `scripts/deploy-api.sh` now refuses to ship code ahead of the
  schema it assumes, overridable with `ALLOW_SCHEMA_DRIFT=1`.
- Server-side PDF rendering for invoices, at `GET /api/v1/invoices/{id}/pdf`.
  WeasyPrint, HTML to PDF, generated on demand and stored nowhere. It shares
  the UBL's invoice load and its VAT grouping, so the printed document and its
  machine-readable twin cannot disagree about a figure. A EUR invoice shows the
  euro total on the face with the sterling equivalent, the stored FX rate and
  its date beneath.
- PEPPOL BIS Billing 3.0 UBL output for an issued invoice, at
  `GET /api/v1/invoices/{id}/ubl`. The EN 16931 tax category is read from
  `vat_treatments.en16931_category` rather than derived, so the three category
  collisions (RED/STD/XI_STD on S, DRC/ERC on AE, ZER/XI_ZER on Z) stay told
  apart by rate, exemption reason and party identifier.
- FX worker watchdog: `scripts/fx-worker-watchdog.sh` plus a 15 minute systemd
  user timer, installed by `scripts/install-fx-watchdog.sh`. It watches the
  Procrastinate heartbeat, which is the only signal that tells working apart
  from present, and restarts the worker when it goes stale.
- VIES VAT number checking, reachable over HTTP:
  `POST /api/v1/customers/{id}/vat-check` and the supplier equivalent. An
  unreachable VIES answers `unavailable` and records nothing, which is
  deliberately not the same as `invalid`.
- Documentation foundation: architecture, domain specification, nine-phase roadmap,
  security non-negotiables, and five architecture decision records.
- An audit of the defects inherited from the upstream fork, so Phase 1 does not
  copy them forward. Held privately: it describes an upstream system that is not
  ours. The fixes it produced are all in `supabase/migrations`.
