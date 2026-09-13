#!/usr/bin/env python3
"""Migration filenames must order unambiguously and never collide.

WHY THIS EXISTS. With one person writing migrations, `0001`, `0002`, `0003`
reads beautifully. With several people working at once it is a collision waiting
to happen: two branches both write `0018_...sql`, both pass their own gate, and
whichever merges second either overwrites the first or lands two migrations
claiming the same position. Neither is caught by anything else, because each
branch is internally consistent.

So new migrations carry a UTC timestamp prefix, `YYYYMMDDHHMMSS`, the same shape
the inherited ones use. Two contributors cannot collide even to the second in
practice, and ordering stays deterministic without anyone coordinating.

The existing `0001` to `0017` keep their numbers. They are applied to the London
project and renaming an applied migration is how you get a database that thinks
it has work still to do.

    python3 scripts/check-migrations.py
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"

# Numbers already applied to London. New work does not extend this sequence.
LEGACY_MAX = 17
TIMESTAMP = re.compile(r"^(\d{14})_")
SEQUENTIAL = re.compile(r"^(\d{1,4})_")


def main() -> int:
    problems: list[str] = []
    prefixes: dict[str, list[str]] = defaultdict(list)

    files = sorted(p.name for p in MIGRATIONS.glob("*.sql"))
    if not files:
        print("no migrations found", file=sys.stderr)
        return 1

    for name in files:
        ts = TIMESTAMP.match(name)
        seq = SEQUENTIAL.match(name)
        if ts:
            prefixes[ts.group(1)].append(name)
            continue
        if seq:
            number = int(seq.group(1))
            prefixes[seq.group(1)].append(name)
            if number > LEGACY_MAX:
                problems.append(
                    f"  {name}: sequential number {number} is above the applied range.\n"
                    f"      New migrations use a UTC timestamp prefix so two branches cannot\n"
                    f"      collide. Rename it to $(date -u +%Y%m%d%H%M%S)_<description>.sql"
                )
            continue
        problems.append(f"  {name}: no numeric prefix, so its position in the order is undefined")

    for prefix, names in sorted(prefixes.items()):
        if len(names) > 1:
            problems.append(
                f"  prefix {prefix} used by {len(names)} migrations: {', '.join(names)}.\n"
                f"      Two migrations claiming one position means whichever applies second\n"
                f"      may be skipped entirely."
            )

    if problems:
        print("Migration filenames are not safe to apply in order:\n", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        return 1

    timestamped = sum(1 for f in files if TIMESTAMP.match(f))
    print(
        f"Migrations: {len(files)} files, no prefix collisions "
        f"({timestamped} timestamped, {len(files) - timestamped} legacy sequential)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
