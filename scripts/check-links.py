#!/usr/bin/env python3
"""Check that relative links in Markdown files resolve to existing files.

Anchors are not checked on purpose: GitHub heading-slug rules make that
fiddly, and this repository has already been bitten by gates that went slow
or flaky because they reached the network. External URLs, mailto links, and
fragment-only links are therefore skipped rather than resolved, so the gate
stays local and dependable. Links into files that do not exist are the only
thing this catches."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]

LINK_PATTERN = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
SKIP_DIRS = {".git", "node_modules", ".venv"}


def files() -> list[Path]:
    listed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.md"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()

    return [
        ROOT / name
        for name in listed
        if not SKIP_DIRS.intersection(Path(name).parts)
    ]


def relative_target(raw_target: str) -> str | None:
    target = raw_target.strip()

    if target.startswith(("#", "http://", "https://", "mailto:")):
        return None

    target = target.split("#", 1)[0]
    target = unquote(target)

    return target or None


def main() -> int:
    broken: list[str] = []

    for path in files():
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            for match in LINK_PATTERN.finditer(line):
                target = relative_target(match.group(1))
                if target is None:
                    continue

                resolved = path.parent / target
                if not resolved.exists():
                    rel = path.relative_to(ROOT)
                    broken.append(f"{rel}:{line_number}: {target}")

    if broken:
        print(f"FAIL: {len(broken)} relative Markdown link(s) do not resolve.\n")
        for entry in broken:
            print(f"  {entry}")
        return 1

    print("ok: every relative Markdown link resolves")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
