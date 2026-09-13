"""Phase 0 keeps one test so the suite and its gates are wired from commit one.

Real coverage arrives with the modules in Phase 2.
"""

from vega_api import __version__


def test_package_imports() -> None:
    assert __version__ == "0.0.0"
