# 0004. Vega owns carbon and the product passport

**Date:** 4 September 2026
**Status:** Accepted

## Context

The sibling product's roadmap already planned Digital Product Passport generation on the
open-dpp and Tractus-X model, plus GS1 EPCIS 2.0 event emission. Vega's plan
independently included product carbon footprints. That is the same feature planned
twice in two products.

## Decision

Vega owns carbon calculation, the Digital Product Passport, packaging EPR, EUDR due
diligence and CBAM. Seamly consumes the resulting figures and reconciles them like
any other ERP field.

## Rationale

A footprint needs its source records: purchase lines for upstream emissions,
shipments for transport, meter readings for Scope 1 and 2. Those are ERP records.
Seamly would have had to import them to compute anything, which is the ERP's job.

## Alternatives rejected

**Seamly owns the passport, Vega supplies records.** Keeps the work where it was
first planned, and Seamly's citation-verified pattern suits regulated disclosure.
Rejected because it inverts the data gravity: the records live in Vega.

**Both, decided later.** Risks building the factor schema twice, and the factor
tables shape Phase 1.

## Consequences

- The sibling product's roadmap is now wrong and must be edited. It has a doc
  freshness check, so it will keep asserting the old plan until someone does.
- Vega's Phase 7 carries four regimes on one provenance spine.
- Vega gains an authenticated supplier ingestion API, with the integrity
  requirements that implies. See SECURITY.md.
