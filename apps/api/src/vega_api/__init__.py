"""Vega's regulated-logic service.

Everything that must be auditable, scheduled or long running lives here rather
than in an Edge Function: VAT return derivation and submission, e-invoice
generation, carbon calculation, and the jobs behind them.

The module contract is Seamly's, four files per business capability:

    modules/<name>/
        __init__.py    handle(event, state) -> Result; PERMISSIONS dict
        contract.py    typed dataclasses; no secrets
        service.py     pure rules; no I/O, enforced by import-linter
        repository.py  all I/O; owns its tables on the shared metadata

Phase 0 establishes the toolchain only. The engine, the modules and the
Procrastinate worker arrive in Phase 2. See ROADMAP.md.
"""

__version__ = "0.0.0"
