"""The duplicate check, tested where it counts.

`scripts/check-claim.py` refuses a pull request that claims an issue another
open pull request already claims. Reaching that branch for real means creating
the exact mess the check exists to prevent, so the logic is a pure function and
this is where it gets proven.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

_spec = importlib.util.spec_from_file_location(
    "check_claim", Path(__file__).resolve().parents[3] / "scripts" / "check-claim.py"
)
assert _spec and _spec.loader
check_claim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_claim)


def pr(number: int, body: str) -> dict[str, Any]:
    return {"number": number, "body": body, "title": f"pr {number}"}


def test_closes_is_found_in_any_of_its_spellings() -> None:
    assert check_claim.claimed_issues("Closes #54") == {54}
    assert check_claim.claimed_issues("fixes #7 and resolves #8") == {7, 8}
    assert check_claim.claimed_issues("no issue here") == set()


def test_a_reference_without_a_keyword_is_not_a_claim() -> None:
    # "see #54" or "as in #54" must not count, or every PR mentioning another
    # would claim it and the duplicate check would fire on nothing.
    assert check_claim.claimed_issues("see #54 for background") == set()


def test_two_open_prs_claiming_one_issue_is_a_clash() -> None:
    # The real case: #61, #62 and #63 all implemented import-linter for #54.
    open_prs = [pr(61, "Closes #54"), pr(62, "Closes #54"), pr(64, "Closes #17")]
    clashes = check_claim.find_clashes(54, this_pr=61, open_prs=open_prs)
    assert [c["number"] for c in clashes] == [62]


def test_a_pr_does_not_clash_with_itself() -> None:
    assert check_claim.find_clashes(54, this_pr=61, open_prs=[pr(61, "Closes #54")]) == []


def test_no_clash_when_issues_differ() -> None:
    open_prs = [pr(61, "Closes #54"), pr(64, "Closes #17")]
    assert check_claim.find_clashes(54, this_pr=61, open_prs=open_prs) == []


def test_a_missing_body_is_not_a_crash() -> None:
    assert check_claim.find_clashes(54, this_pr=61, open_prs=[{"number": 62, "body": None}]) == []


def test_a_quoted_closing_keyword_still_counts() -> None:
    """Because GitHub counts it too, and will close the issue on merge.

    A pull request describing another one wrote: said "Closes #38", and
    connected to nothing. GitHub parses closing keywords anywhere in a body,
    quotes included, so merging it would have closed an unrelated issue. The
    check flagging that is correct behaviour, not a false positive: the fix is
    to reword the prose, not to loosen the pattern.
    """
    body = 'This PR closes #68. #60 said "Closes #38", and connected to nothing.'
    assert check_claim.claimed_issues(body) == {68, 38}


def test_a_bot_author_is_recognised_by_its_flag() -> None:
    assert check_claim.is_bot({"login": "dependabot", "is_bot": True})


def test_a_bot_author_is_recognised_by_its_login_suffix() -> None:
    # gh does not always report is_bot, so the suffix is the stable signal.
    assert check_claim.is_bot({"login": "dependabot[bot]"})


def test_a_person_is_not_a_bot() -> None:
    assert not check_claim.is_bot({"login": "Pawansingh3889", "is_bot": False})


def test_a_missing_author_is_not_a_bot() -> None:
    # A bot slipping through would skip the duplicate check, so this defaults
    # to treating an unknown author as a person.
    assert not check_claim.is_bot({})
