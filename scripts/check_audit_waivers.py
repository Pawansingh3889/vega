#!/usr/bin/env python3
"""Fail the build when a dependency audit waiver has expired or is malformed.

A waiver with no expiry is a permanent exemption wearing a temporary label, so
this refuses those, refuses anything dated more than 90 days out, and refuses a
waiver applied to pnpm that is not recorded with a reason.

Stdlib only: this runs on a bare CI runner with no install step.

Usage:  python3 scripts/check_audit_waivers.py
"""

from __future__ import annotations

import json
import re
import sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTER = ROOT / "security" / "audit-waivers.json"
WORKSPACE = ROOT / "pnpm-workspace.yaml"

MAX_WINDOW = timedelta(days=90)
REQUIRED = ("ghsa", "package", "severity", "reason", "granted", "expires", "owner")


def parse_day(value: str, label: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError:
        raise SystemExit(f"{label}: '{value}' is not an ISO date (YYYY-MM-DD)") from None


def ignored_ghsas() -> set[str]:
    """Read auditConfig.ignoreGhsas out of pnpm-workspace.yaml.

    Deliberately a narrow regex rather than a YAML parser: this must run with no
    dependencies, and the shape it reads is a flat list this repo controls.
    """
    if not WORKSPACE.exists():
        return set()
    text = WORKSPACE.read_text(encoding="utf-8")
    block = re.search(r"^\s*ignoreGhsas:\s*$((?:\n\s*-\s*.+)+)", text, re.M)
    if not block:
        return set()
    return set(re.findall(r"-\s*['\"]?(GHSA-[\w-]+)['\"]?", block.group(1)))


def main() -> int:
    if not REGISTER.exists():
        print(f"missing register: {REGISTER.relative_to(ROOT)}", file=sys.stderr)
        return 1

    waivers = json.loads(REGISTER.read_text(encoding="utf-8")).get("waivers", [])
    today = date.today()
    problems: list[str] = []

    for i, w in enumerate(waivers):
        tag = w.get("ghsa", f"entry {i}")
        for field in REQUIRED:
            if not w.get(field):
                problems.append(f"{tag}: missing required field '{field}'")
        if not all(w.get(f) for f in ("granted", "expires")):
            continue

        granted = parse_day(w["granted"], f"{tag}.granted")
        expires = parse_day(w["expires"], f"{tag}.expires")

        if expires < today:
            problems.append(
                f"{tag}: EXPIRED on {expires} ({(today - expires).days} days ago). "
                "Upgrade the dependency, or take the renewal decision again."
            )
        elif expires - granted > MAX_WINDOW:
            problems.append(f"{tag}: window is {(expires - granted).days} days, limit is 90")
        if len(w.get("reason", "")) < 20:
            problems.append(f"{tag}: reason is too thin for a reviewer to check")

    recorded = {w["ghsa"] for w in waivers if w.get("ghsa")}
    applied = ignored_ghsas()
    for ghsa in sorted(applied - recorded):
        problems.append(f"{ghsa}: ignored by pnpm but not recorded in the register")
    for ghsa in sorted(recorded - applied):
        problems.append(f"{ghsa}: recorded in the register but not ignored by pnpm")

    if problems:
        print("Dependency audit waiver check FAILED\n", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        print("\nSee security/README.md", file=sys.stderr)
        return 1

    if not waivers:
        print("No audit waivers in force.")
    else:
        soonest = min(parse_day(w["expires"], w["ghsa"]) for w in waivers)
        print(f"{len(waivers)} waiver(s) in force, next expiry {soonest}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
