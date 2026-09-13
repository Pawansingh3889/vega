#!/usr/bin/env python3
"""Every citation must resolve to something that exists.

A security pull request once justified two changes "per SECURITY.md
recommendation" and "per SECURITY.md N1". SECURITY.md says nothing about
passwords, and N1 is about row level security returning empty. Both changes were
defensible on their own merits; neither citation existed.

A citation nobody checks is how a rule gets invented, and an invented rule is
harder to remove than a missing one because everyone believes it was decided.
This is the check nobody was doing.

Run over the tree by `make lint` and CI. Locally: scripts/check-citations.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Only the forms actually used in this repository. A looser pattern would match
# prose like "note 3.1 of the return" and produce failures nobody trusts, which
# is how a check gets switched off.
PATTERNS = {
    "security": re.compile(r"SECURITY\.md\s+(N\d+)"),
    "spec": re.compile(r"SPEC\.md\s+(\d+(?:\.\d+)?)"),
    "adr": re.compile(r"\bADR[\s-](\d{4})\b"),
}

SKIP_DIRS = {".git", "node_modules", ".venv", "dist", "build", "__pycache__", ".next"}
READ_SUFFIXES = {".py", ".ts", ".tsx", ".js", ".mjs", ".sql", ".md", ".sh", ".toml", ".yml", ".yaml"}


def anchors() -> tuple[set[str], set[str], set[str]]:
    security = set(re.findall(r"^## (N\d+)\.", (ROOT / "SECURITY.md").read_text(), re.MULTILINE))
    spec = set(
        re.findall(r"^#{2,4} (\d+(?:\.\d+)?)[ .]", (ROOT / "SPEC.md").read_text(), re.MULTILINE)
    )
    adr = {path.name[:4] for path in (ROOT / "docs" / "decisions").glob("[0-9]*.md")}
    return security, spec, adr


def files() -> list[Path]:
    listed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"], capture_output=True, text=True, check=True
    ).stdout.split()
    return [
        ROOT / name
        for name in listed
        if Path(name).suffix in READ_SUFFIXES
        and not SKIP_DIRS.intersection(Path(name).parts)
    ]


def main() -> int:
    security, spec, adr = anchors()
    known = {"security": security, "spec": spec, "adr": adr}
    where = {
        "security": "SECURITY.md has no such non-negotiable",
        "spec": "SPEC.md has no such section",
        "adr": "docs/decisions has no such ADR",
    }

    broken: list[str] = []
    for path in files():
        if path.name == "check-citations.py":
            continue  # its own docstring quotes the bad citations it exists to catch
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        for line_number, line in enumerate(text.splitlines(), start=1):
            for kind, pattern in PATTERNS.items():
                for reference in pattern.findall(line):
                    if reference not in known[kind]:
                        rel = path.relative_to(ROOT)
                        broken.append(f"{rel}:{line_number}: {kind} {reference}: {where[kind]}")

    if broken:
        print(f"FAIL: {len(broken)} citation(s) do not resolve.\n")
        for entry in broken:
            print(f"  {entry}")
        print()
        print("Either the reference is wrong, or the thing it names should exist and does not.")
        print("Do not fix this by deleting the citation: work out which of the two it is.")
        return 1

    counts = f"{len(security)} non-negotiables, {len(spec)} spec sections, {len(adr)} ADRs"
    print(f"ok: every citation resolves ({counts})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
