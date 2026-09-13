#!/usr/bin/env python3
"""Do the edge functions still name columns that exist?

WHY THIS EXISTS. The UK migrations renamed and dropped a lot of columns, and
three edge functions kept referring to the old names: `signin` selected
`companies.gstn` and `postal_code`, `register-business` wrote `gstin`, and
`approve-registration` wrote both. Sign-in is on the critical path.

Nothing caught it. Edge functions are Deno TypeScript that runs on Supabase, so
they are outside `tsc`, outside the Python suite, and outside `make db-verify`.
A migration can therefore break authentication and every gate stays green.

WHAT THIS DOES. Reads the column names the schema actually has, then reads the
`.from("table").select(...)` and `.insert({...})` calls in the edge functions and
flags any column name that no schema table has. It is deliberately coarse: it
does not track which table a name belongs to, because the goal is catching a
rename that leaves a dangling reference, not type-checking Deno.

False positives are possible for a local variable that happens to share a
column's shape. The fix is to name it in ALLOWED below with a reason, not to
loosen the check.

    python3 scripts/check-edge-function-columns.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FUNCTIONS = ROOT / "supabase" / "functions"
MIGRATIONS = ROOT / "supabase" / "migrations"

# Names that look like columns in these files but are not.
ALLOWED = {
    "created_at", "updated_at",  # written by defaults, sometimes named anyway
    "email_confirm",             # a GoTrue admin API field, not a column
    "inner", "left",             # PostgREST embed hints
    "from_format", "to_format",  # arguments to a formatting helper, not columns
    "request_id",                # a local identifier in register-business
}

# Columns the UK migrations removed. Naming them explicitly turns a vague
# "unknown column" into a message that says what to use instead.
RENAMED = {
    "gstn": "vat_number", "gstin": "vat_number", "gst_number": "vat_number",
    "postal_code": "postcode", "pin_code": "postcode",
    "shipping_pin_code": "shipping_postcode",
    "billing_pin_code": "billing_postcode",
    "delivery_pin_code": "delivery_postcode",
    "dispatch_pin_code": "dispatch_postcode",
    "gst_percentage": "default_vat_treatment_code",
    "hsn_code": "commodity_code", "hsn_sac_code": "commodity_code",
    "pan_number": "(dropped: no UK counterpart)",
    "ifsc_code": "(dropped: use sort_code)",
    "place_of_supply": "(dropped: treatment codes carry this)",
    "gst_tax_location": "(dropped)",
}


def schema_columns() -> set[str]:
    """Every column name the migrations create, rename into, or add."""
    columns: set[str] = set()
    for path in sorted(MIGRATIONS.glob("*.sql")):
        sql = path.read_text(encoding="utf-8", errors="replace")
        for body in re.findall(r"CREATE TABLE[^(]*\((.*?)\n\);", sql, re.S):
            for line in body.splitlines():
                m = re.match(r"\s+([a-z_][a-z0-9_]*)\s+", line)
                if m and m.group(1).upper() not in {"CONSTRAINT", "PRIMARY", "UNIQUE", "FOREIGN", "CHECK"}:
                    columns.add(m.group(1))
        columns.update(re.findall(r"RENAME COLUMN\s+\w+\s+TO\s+(\w+)", sql, re.I))
        columns.update(re.findall(r"ADD COLUMN(?:\s+IF NOT EXISTS)?\s+(\w+)", sql, re.I))
    return columns


def referenced_columns() -> dict[str, set[str]]:
    """Column-ish names each edge function mentions in a query."""
    found: dict[str, set[str]] = {}
    for path in sorted(FUNCTIONS.rglob("index.ts")):
        text = path.read_text(encoding="utf-8", errors="replace")
        names: set[str] = set()
        # .insert({ col: value }) and .update({ col: value })
        for block in re.findall(r"\.(?:insert|update)\(\s*\{(.*?)\}\s*\)", text, re.S):
            names.update(re.findall(r"^\s*([a-z_][a-z0-9_]*)\s*:", block, re.M))
        # .select("a, b, companies!inner(x, y)")
        #
        # PostgREST embeds a related table as `table!inner(cols)`. Those table
        # names and the `inner` hint are not columns, so strip the embed syntax
        # before collecting names, or the check drowns in false positives and
        # gets ignored, which is worse than not having it.
        for block in re.findall(r'\.select\(\s*[`"\']([^`"\']*)[`"\']', text, re.S):
            block = re.sub(r"\b[a-z_]+\s*!\s*(?:inner|left)\b", " ", block)
            block = re.sub(r"\b([a-z_][a-z0-9_]*)\s*\(", " ", block)  # embedded table(
            block = block.replace("!inner", " ").replace("!left", " ")
            names.update(re.findall(r"\b([a-z_][a-z0-9_]*)\b", block))
        names -= ALLOWED
        if names:
            found[path.parent.name] = names
    return found


def main() -> int:
    known = schema_columns()
    problems: list[str] = []

    for function, names in referenced_columns().items():
        for name in sorted(names - known):
            hint = RENAMED.get(name)
            if hint:
                problems.append(f"  {function}: '{name}' no longer exists. Use '{hint}'.")
            else:
                problems.append(f"  {function}: '{name}' is not a column in any table.")

    if problems:
        print("Edge functions reference columns the schema does not have:\n", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        print(
            "\nEdge functions run on Supabase, outside tsc and outside the test suite,"
            "\nso a migration can break one and every other gate stays green.",
            file=sys.stderr,
        )
        return 1

    print(f"Edge functions: every column referenced exists ({len(known)} known columns).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
