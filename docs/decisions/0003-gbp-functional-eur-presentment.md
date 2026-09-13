# 0003. GBP functional, EUR presentment

**Date:** 4 September 2026
**Status:** Accepted

## Context

UK businesses trading with the EU raise invoices in euro. HMRC still requires the
VAT return in sterling. A figure restated a year later must reproduce exactly.

## Decision

GBP is the functional currency: books, VAT return and all reporting are sterling.
EUR is a presentment currency: an invoice may be raised and sent in euro, and the
document stores the amount, the currency, the FX rate used, and the date that rate
was sourced.

The rate lives **on the document**, never resolved at read time.

## Alternatives rejected

**GBP only.** Simplest, and it fails the first client with EU customers.

**Full multi-currency.** Any currency, per-company functional currency, period-end
revaluation and FX gain and loss postings. The heaviest thing that could be added to
Phase 1, and no client needs it yet.

**GBP and EUR both functional.** Two base currencies, either can be the company's
own. Suits a business with a genuine EU entity rather than EU customers, and roughly
doubles the reporting surface.

## Consequences

- Every money column carries a currency and a rate reference from Phase 1. This is
  the point: retrofitting it across a working ERP is the expensive kind of rework.
- Rate sourcing needs a recorded provenance, not just a number.
- Adding a third currency later is a feature, not a migration.
