# Vega Domain Specification

> **Last updated:** 6 September 2026 (rev 3)
> **Update rule:** this file changes whenever a domain rule is added, narrowed or
> reversed. It is the contract the schema is measured against.

This describes what the system must be true about, not how it is built. For the how,
see [ARCHITECTURE.md](ARCHITECTURE.md).

## 1. Currency

**GBP is the functional currency.** The books, the VAT return and every report are
sterling.

**EUR is a presentment currency.** An invoice may be raised and sent in euro. The
document stores four things together:

| Field | Rule |
|---|---|
| `amount` | In the presentment currency, as `NUMERIC`, never a float |
| `currency` | ISO 4217. GBP or EUR today; the column does not assume two |
| `fx_rate` | The rate used, stored on the document |
| `fx_rate_date` | The date that rate was sourced |

The rate lives on the document rather than being looked up at read time. HMRC wants
sterling on the return whatever the invoice was raised in, and a figure restated a
year later must reproduce exactly. A rate resolved at read time cannot do that.

### 1.1 Rate ingestion integrity

Storing the rate correctly is worthless if the rate arrives wrong. The ECB ingestion
job:

- validates the payload against the published schema before anything is written;
- refuses to write on a stale feed or a failed parse;
- **never overwrites today's rate with an empty result.**

A failed update leaves yesterday's rate standing and raises an alert. It does not
fail silently and it does not write a zero, because a zero rate produces an invoice
that looks settled and a VAT box that balances to nothing. See SECURITY.md N6.

This is a Phase 1 decision. Retrofitting a currency and a rate onto every money
column across a working ERP is the expensive kind of rework.

See [ADR 0003](docs/decisions/0003-gbp-functional-eur-presentment.md).

## 2. VAT

### 2.1 Treatment codes, not rates

Every invoice line carries a **treatment code**, never a loose percentage. A rate is
a consequence of a treatment; storing the rate alone loses why it applied.

| Code | Meaning |
|---|---|
| `STD` | Standard rated, 20 percent |
| `RED` | Reduced rated, 5 percent |
| `ZER` | Zero rated |
| `EXM` | Exempt |
| `OUT` | Outside the scope of UK VAT |
| `DRC` | Domestic reverse charge |
| `ERC` | EU business to business reverse charge |
| `XI_*` | Northern Ireland cases under the Windsor Framework |

Rates are versioned reference data keyed by treatment and effective date. A change
of rate never rewrites an issued document.

`OUT` is deliberately not `OSS`. In this product OSS already means the EU One Stop
Shop, which is deferred but has reserved room in this same table. Two meanings of
one code sitting side by side in tax filings is a defect waiting for a deadline, and
renaming costs nothing while nothing is stored.

### 2.2 The return is derived

Boxes 1 to 9 are derived from treatment codes over a period. No box is ever typed by
a human, and no box is stored as an editable figure. The derivation is pure
arithmetic over typed rows and lives in `service.py`, testable without a database.

### 2.3 Submission

Making Tax Digital. HMRC OAuth, obligation retrieval, submission with the required
fraud prevention headers. The submission record is append-only: what was sent, when,
by whom, and the response received.

### 2.4 EN 16931 category mapping

PEPPOL BIS Billing 3.0 carries the EN 16931 tax category code, not Vega's treatment
code. The mapping is reference data, and Phase 3's UBL emission is a **lookup against
this table, never an improvisation at the call site**.

| Treatment | EN 16931 category | Meaning |
|---|---|---|
| `STD` | `S` | Standard rate |
| `RED` | `S` | Standard rate, reduced percentage. The category does not distinguish; the percentage does. |
| `ZER` | `Z` | Zero rated |
| `EXM` | `E` | Exempt from VAT |
| `DRC` | `AE` | VAT reverse charge |
| `ERC` | `AE` | VAT reverse charge |
| `OUT` | `O` | Services outside the scope of tax |
| Export of goods, non-EU | `G` | Free export item, VAT not charged |
| Intra-community supply of goods | `K` | VAT exempt for intra-community supply |

Northern Ireland cases map to the same category codes as their equivalents. What
distinguishes them is the **XI endpoint indicator** on the party identifier, not a
different category. A document raised under a `XI_*` treatment carries the XI VAT
number as the party scheme identifier and takes the category its underlying treatment
implies.

Two consequences worth stating, because both are easy to get wrong:

- `RED` and `STD` share category `S`. The rate carries the difference. Emitting a
  distinct category for reduced rate produces a document that fails validation.
- `DRC` and `ERC` share category `AE`. They differ in the exemption reason text and
  in which return boxes they feed, not in the category.

## 3. Invoices

| Rule | Detail |
|---|---|
| Immutable once issued | An issued invoice is frozen. No edit, no delete, no renumber. Enforced by a trigger binding every role, as in migration 0017. |
| Corrections are credit notes | Because that is what an audit expects and what the return reconciles against. |
| Gapless numbering | Per company, per year, allocated **at issue** so an abandoned draft leaves no gap. |
| Serialised per company | A counter row under `SELECT ... FOR UPDATE`. See 3.2 and ADR 0006. |
| Void means credit note | There is no void that removes a row. |

### 3.1 The lifecycle

An invoice has two states and one transition:

| State | Meaning |
|---|---|
| `draft` | Being prepared. Editable, has no number yet. |
| `issued` | Sent. Immutable, numbered, and countable in a VAT return. |

**The transition is one-way.** There is no un-issuing. A mistake found after
issuing is corrected by a credit note, which is the whole reason credit notes
exist.

A number is allocated **at issue**, not at creation. Numbering a draft that is
later abandoned puts a gap in the sequence, and gaplessness is the property that
makes the sequence worth anything.

The inherited schema disagrees with itself here, and both sides need fixing:
`sales_invoices.status` is constrained to `'finalized'` alone, so no draft state
exists, while `credit_notes.status` already defaults to `'Draft'`.

### 3.2 How a number is allocated

**A counter row per company, taken under a row lock.**

```sql
SELECT next_number FROM invoice_counters
 WHERE company_id = $1 FOR UPDATE;
```

The row *is* the sequence, so an allocation path cannot forget to lock: reading
the next number requires taking the lock that serialises it. The cost is one
contended row per company, which at this scale is nothing.

Two alternatives were rejected. A **per-company advisory lock** needs no extra
table and releases automatically, but the lock and the allocation are separate
steps, so a new path that allocates without locking works fine until two
invoices are issued in the same second. A Postgres **`SEQUENCE`** is not a
candidate at all: sequences deliberately do not roll back, so a failed
transaction burns a number, and the requirement is gapless.

See [ADR 0006](docs/decisions/0006-gapless-invoice-numbering.md).

### 3.3 Credit notes

A credit note corrects an issued invoice. It **references the invoice it
corrects**, and optionally the return order that prompted it.

The inherited model has `credit_notes.rso_id NOT NULL`, so a credit note can
only exist against a Return Sales Order. That makes the correction path above
impossible: a pricing error has no return behind it, and inventing a
zero-quantity return to satisfy the constraint fabricates an event that never
happened, which is exactly the sort of thing an auditor asks about.

`rso_id` becomes nullable and `invoice_id` is added. The existing returns flow
keeps working unchanged.

### 3.4 The human-readable document

PDF is rendered **server side** from HTML, using WeasyPrint. Same reason as
every other figure: N3 says the server produces what gets filed, and a document
assembled in the browser is a document the browser could have got wrong.

A headless browser was rejected as a renderer. It is pixel-perfect and it puts a
browser process next to the ledger, which is a large attack surface for
something whose job is to lay out a table.

**Format:** PEPPOL BIS Billing 3.0, UBL. Already the NHS supplier standard, the most
likely shape of any wider UK mandate, and the same rails the EU is moving to. All
inbound XML is treated as hostile: see SECURITY.md N4.

## 4. EU trade

### 4.1 In scope

**Northern Ireland, Windsor Framework.** XI VAT numbers, goods moving from NI into
the EU still inside the EU goods regime, EC Sales List obligations. Modelled as
first-class treatment codes, not as a special case bolted onto the UK path. That is
where this normally goes wrong.

**EU business to business.** Reverse charge treatments on sales into the EU, customer
VAT number validation through VIES, and room to hold registrations in member states.

VIES evidence retention is narrow by design: store the VAT number checked, the
timestamp, and the result. Nothing else. The response body is not evidence and is not
kept.

**Customs and origin.** EORI on the company, commodity and HS codes on products,
preferential origin under the UK and EU trade agreement. These sit in Phase 1 rather
than in the customs work, because CBAM and the product passport both join on the
commodity code.

### 4.2 Out of scope, deliberately

**OSS and IOSS** distance selling. No client sells direct to EU consumers yet. The
treatment code table leaves room.

**CSRD.** Materially larger than everything else in this specification combined. It
waits for a client who needs it.

## 5. Carbon

### 5.1 Factors are versioned data

The DEFRA and DESNZ greenhouse gas conversion factors are published annually and free
to use, which makes them a versioned reference table rather than a vendor dependency.

One row per factor per publication year, in `kgCO2e` per unit. New factors land as a
new year. **A factor row is never updated in place.**

### 5.2 Results remember their inputs

Every calculated footprint stores the factor identifier and version it used. A 2026
figure must still reproduce after the 2027 factors publish. Without this, numbers
change quietly under a client's feet, which is the failure that destroys trust in a
disclosure product.

### 5.3 It hangs off records that already exist

| Source record | Carries |
|---|---|
| Purchase line | Upstream emissions |
| Shipment | Transport emissions |
| Meter reading | Scope 1 and Scope 2 |

No parallel data entry. That is the reason most carbon modules go unused.

### 5.4 Supplier data is ingested, not trusted

Suppliers submit primary data through an authenticated API: per-supplier credentials,
PACT v2 schema validation at the boundary, appends through the restricted role only.
A forged or replayed event poisons the chain, and the chain is the whole proposition.
Chain verification runs on a schedule, not on demand.

## 6. Product compliance

Four regimes, one spine. All four want provenance and disclosure attached to a
product line, traced back through the supply chain.

| Regime | What it adds |
|---|---|
| Digital Product Passport, ESPR | The carbon figure plus materials and repairability |
| Packaging EPR | Packaging weight and material per line, reported by tonnage |
| EUDR | Geolocated traceability for cocoa, coffee, wood, cattle, rubber, soy, palm, and a due diligence statement |
| CBAM | Embedded emissions per consignment, joined on the commodity code |

EUDR plot coordinates are **personal data**. They identify a smallholder. Erasure
design in Phase 8 covers plot coordinates, not only customer rows.

## 7. Multi-tenancy

Every table is scoped to a company. Row level security is enabled on every table with
no exception, and the guarantee is proven by a generated test rather than asserted.
See SECURITY.md N1.
