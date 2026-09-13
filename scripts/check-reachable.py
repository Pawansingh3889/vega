#!/usr/bin/env python3
"""A module nothing imports is not a feature, it is a file.

A pull request once added a complete postcode-lookup module, four files and
seven tests, said "Closes #38", and wired it to nothing: no route, no caller, no
reference anywhere outside its own package. Merging it would have closed an
issue whose user-visible behaviour did not exist, and the gate would have been
green throughout, because unreachable code compiles, type-checks and passes its
own unit tests perfectly.

The composition root is `app.py`, with `tasks.py` for scheduled work. A module
that neither reaches is not connected to anything a user or a job can trigger.

Run by `make lint` and CI. Locally: scripts/check-reachable.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "apps" / "api" / "src" / "vega_api"
MODULES = PACKAGE / "modules"


def modules_on_disk() -> set[str]:
    return {
        path.name
        for path in MODULES.iterdir()
        if path.is_dir() and not path.name.startswith("_") and (path / "__init__.py").exists()
    }


def modules_imported_from_outside() -> set[str]:
    """Module names referenced by any file that is not inside modules/."""
    found: set[str] = set()
    patterns = [
        re.compile(r"from\s+\.modules\s+import\s+([\w,\s]+)"),
        re.compile(r"from\s+\.modules\.(\w+)"),
        re.compile(r"from\s+vega_api\.modules\s+import\s+([\w,\s]+)"),
        re.compile(r"from\s+vega_api\.modules\.(\w+)"),
        re.compile(r"\bmodules\.(\w+)\b"),
    ]
    for path in PACKAGE.rglob("*.py"):
        if MODULES in path.parents:
            continue
        text = path.read_text(encoding="utf-8")
        for pattern in patterns:
            for match in pattern.findall(text):
                for name in re.split(r"[,\s]+", match):
                    if name:
                        found.add(name)
    return found


def main() -> int:
    on_disk = modules_on_disk()
    reachable = modules_imported_from_outside()
    orphans = sorted(on_disk - reachable)

    if orphans:
        print(f"FAIL: {len(orphans)} module(s) that nothing outside modules/ imports.\n")
        for name in orphans:
            print(f"  vega_api.modules.{name}")
        print()
        print("Unreachable code compiles, type-checks and passes its own tests. It just")
        print("does nothing. Wire it into app.py (a route) or tasks.py (a job), or say")
        print("plainly in the PR that this is the adapter half and does not close the")
        print("issue on its own.")
        return 1

    print(f"ok: all {len(on_disk)} module(s) are reachable ({', '.join(sorted(on_disk))})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
