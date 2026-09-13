#!/usr/bin/env python3
"""Refuse a pull request that duplicates work another one already claims.

Work here happens in parallel, and the parts do not coordinate with each other.
On one day that produced four duplicates, the worst being three separate
implementations of the same import-linter enforcement, one of which would have
shipped a contract permitting the bug it was written to catch.

Reading the board first is a habit, and habits do not survive parallel work. This
is the check that does not depend on one.

Run by CI on every pull request. Locally: scripts/check-claim.py <pr-number>
"""

from __future__ import annotations

import json
import re
import subprocess
import sys

REPO = "Pawansingh3889/vega"
CLOSES = re.compile(r"\b(?:closes|fixes|resolves)\s+#(\d+)\b", re.IGNORECASE)


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        # check=True raises without showing stderr, which is how this script
        # first failed in CI: a permissions problem that reported only
        # "returned non-zero exit status 1". A check that cannot say why it
        # failed wastes the run it failed on.
        print(f"FAIL: gh {' '.join(args)} exited {result.returncode}", file=sys.stderr)
        print(result.stderr.strip(), file=sys.stderr)
        raise SystemExit(1)
    return result.stdout


def claimed_issues(body: str) -> set[int]:
    return {int(n) for n in CLOSES.findall(body or "")}


def find_clashes(
    issue_number: int, this_pr: int, open_prs: list[dict[str, object]]
) -> list[dict[str, object]]:
    """Open pull requests other than this one that claim the same issue.

    Split out from main so it can be tested without a network round trip. This
    is the branch that matters and it is the hardest to reach by hand: it needs
    two open PRs claiming one open issue, which is exactly the state nobody
    wants to create on purpose to check a script.
    """
    return [
        other
        for other in open_prs
        if other["number"] != this_pr
        and issue_number in claimed_issues(str(other.get("body") or ""))
    ]


def main(pr_number: str) -> int:
    pr = json.loads(gh("pr", "view", pr_number, "--repo", REPO, "--json", "body,title,number"))
    mine = claimed_issues(pr["body"])

    if not mine:
        print(f"FAIL: #{pr['number']} names no issue.")
        print()
        print("Every PR closes exactly one issue, so the board says what is being worked on")
        print("and anyone else can see it. Add 'Closes #<n>' to the description, or open")
        print("an issue first if none covers this.")
        return 1

    if len(mine) > 1:
        print(f"FAIL: #{pr['number']} claims {len(mine)} issues: {sorted(mine)}.")
        print()
        print("One PR, one issue. Two issues in one PR cannot be reviewed separately,")
        print("cannot be reverted separately, and hide which half a reviewer approved.")
        return 1

    issue_number = mine.pop()
    issue = json.loads(
        gh("issue", "view", str(issue_number), "--repo", REPO, "--json", "state,labels,title")
    )
    labels = {label["name"] for label in issue["labels"]}

    if issue["state"] != "OPEN":
        print(f"FAIL: #{pr['number']} closes issue #{issue_number}, which is already {issue['state']}.")
        print()
        print(f"  {issue['title']}")
        print()
        print("Work that is already done does not need doing again. Check the issue state")
        print("before starting: this has cost this repository a whole PR before.")
        return 1

    if not any(label.startswith("lane:") for label in labels):
        print(f"FAIL: issue #{issue_number} has no lane, so nobody owns it.")
        print("  gh issue edit %d --add-label lane:<web|api|db|repo>" % issue_number)
        return 1

    # The duplicate check. Everything above is hygiene; this is the one that
    # would have caught #61, #62 and #63 all implementing the same thing.
    others = json.loads(
        gh("pr", "list", "--repo", REPO, "--state", "open", "--json", "number,body,title")
    )
    clashes = find_clashes(issue_number, pr["number"], others)

    if clashes:
        print(f"FAIL: issue #{issue_number} is already claimed by an open pull request.")
        print()
        for other in clashes:
            print(f"  #{other['number']}  {other['title']}")
        print()
        print("Two PRs for one issue means the same thing got built twice, and one of")
        print("them wasted the work. Talk on the issue and decide which one continues.")
        print("If this PR is genuinely different, it needs its own issue.")
        return 1

    agent = sorted(label for label in labels if label.startswith("agent:"))
    who = agent[0].split(":", 1)[1] if agent else "nobody"
    print(f"ok: #{pr['number']} claims issue #{issue_number}, held by {who}, no clash.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: check-claim.py <pr-number>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
