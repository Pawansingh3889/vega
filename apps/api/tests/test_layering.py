"""The layering contracts are only as good as their coverage.

`lint-imports` enforces module independence from a hand-written list in
pyproject.toml. A new module that nobody adds to that list is not covered, and
nothing says so: the run still reports every contract kept. That is the shape of
check this repository keeps producing by accident, so this test closes it.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

API_ROOT = Path(__file__).resolve().parents[1]
MODULES_DIR = API_ROOT / "src" / "vega_api" / "modules"


def _independence_modules() -> set[str]:
    with (API_ROOT / "pyproject.toml").open("rb") as handle:
        config = tomllib.load(handle)
    for contract in config["tool"]["importlinter"]["contracts"]:
        if contract["type"] == "independence":
            return set(contract["modules"])
    raise AssertionError("no independence contract in pyproject.toml")


def _module_dirs() -> list[Path]:
    return sorted(
        path for path in MODULES_DIR.iterdir() if path.is_dir() and not path.name.startswith("_")
    )


def test_every_module_directory_has_a_seam() -> None:
    """A module directory without `__init__.py` is invisible to everything.

    This is not a style rule. The coverage test below identified a module by its
    `__init__.py`, so a directory without one was not a module as far as the
    check was concerned: it was never required to appear in the independence
    contract, and import-linter therefore never read it.

    That is not hypothetical. `modules/hmrc` shipped without one. `import httpx`
    was planted in its `service.py` and the run answered "service.py is pure: no
    network, no database, no repository KEPT", with the coverage test passing
    alongside it. The hole was in the filter of the test written to close it.
    """
    without = [path.name for path in _module_dirs() if not (path / "__init__.py").exists()]
    assert not without, (
        f"these module directories have no __init__.py: {sorted(without)}. "
        "Add one. Until it exists the module is not covered by the independence "
        "contract and its service.py purity is not checked, while the run still "
        "reports every contract kept."
    )


def test_every_module_is_covered_by_the_independence_contract() -> None:
    # Deliberately every directory, not only those with an __init__.py. Keying
    # off the seam file is what let modules/hmrc go uncovered: the missing file
    # excused the module from the check instead of failing it.
    on_disk = {f"vega_api.modules.{path.name}" for path in _module_dirs()}
    listed = _independence_modules()

    missing = on_disk - listed
    assert not missing, (
        f"these modules exist but are not in the independence contract: {sorted(missing)}. "
        "Add them to [[tool.importlinter.contracts]] in apps/api/pyproject.toml, "
        "or the contract passes while covering nothing."
    )

    stale = listed - on_disk
    assert not stale, f"the independence contract names modules that do not exist: {sorted(stale)}"


# The forbidden list is a ratchet, like --max-warnings. Entries may be added.
# None may be removed.
#
# A competing pull request once proposed this same contract with `httpx` left
# out, described as "httpx is allowed for external API calls". httpx in
# service.py is the violation that caused the contract to be written: two
# modules made the HTTP call from service.py, and fx already proves a module can
# fetch over the network with a pure service, because fx/repository.py does the
# call. Allowing it would not have relaxed a rule, it would have written the
# current bug into the rule and then reported the result as enforced.
REQUIRED_FORBIDDEN = {
    "vega_api.modules.*.repository",
    "vega_api.common.db",
    "httpx",
    "asyncpg",
    "sqlalchemy",
    "psycopg",
    "procrastinate",
}


def _forbidden_modules() -> set[str]:
    with (API_ROOT / "pyproject.toml").open("rb") as handle:
        config = tomllib.load(handle)
    for contract in config["tool"]["importlinter"]["contracts"]:
        if contract["type"] == "forbidden":
            return set(contract["forbidden_modules"])
    raise AssertionError("no forbidden contract in pyproject.toml")


def test_the_forbidden_list_only_ever_grows() -> None:
    dropped = REQUIRED_FORBIDDEN - _forbidden_modules()
    assert not dropped, (
        f"these were removed from the forbidden contract: {sorted(dropped)}. "
        "The list is a ratchet: adding an entry is a decision, removing one is a "
        "regression wearing the shape of a decision. If a module genuinely needs "
        "one of these, the import belongs in repository.py, not in the contract."
    )


def test_external_packages_are_actually_analysed() -> None:
    # Without include_external_packages, a forbidden contract cannot see httpx
    # or asyncpg at all: it reports every contract kept while checking only the
    # first-party half. The run looks identical either way, which is why this
    # is asserted rather than trusted.
    with (API_ROOT / "pyproject.toml").open("rb") as handle:
        config = tomllib.load(handle)
    assert config["tool"]["importlinter"].get("include_external_packages") is True, (
        "include_external_packages must stay true, or the network half of the "
        "purity contract silently checks nothing."
    )
