"""Importing the composition root must not read the environment.

`cors.py` states the property this file checks:

    Its own module because the composition root must stay importable without
    environment: the settings here are injected, never read.

Nothing checked it, and `app.py` broke it on the same commit that wrote it, with
`configure_cors(app, get_settings())` at module scope. It went unnoticed because
no test had ever imported the app, so nothing had ever asked. See #82.

The consequence was not subtle once something did ask: CI could not collect
`test_route_injection.py` at all, while the same tests passed on a developer
machine, for the ordinary reason that a laptop has an environment and a runner
does not.
"""

from __future__ import annotations

import subprocess
import sys

# Every variable `Settings` requires. Emptying the environment of these is the
# whole test: with them present, a module-level read passes and proves nothing.
REQUIRED = ("VITE_SUPABASE_URL", "VEGA_DATABASE_URL")


def _import_in_a_bare_environment(module: str) -> subprocess.CompletedProcess[str]:
    """Import `module` in a child process with the required variables removed.

    A subprocess rather than monkeypatching `os.environ`, because the parent
    has already imported half of this package and `get_settings` is
    `lru_cache`d: an in-process attempt would test a cached answer from before
    the variables were removed, which is exactly the kind of check that passes
    while doing nothing.
    """
    return subprocess.run(
        [sys.executable, "-c", f"import {module}"],
        capture_output=True,
        text=True,
        env={"PATH": "/usr/bin:/bin", "HOME": "/nonexistent"},
    )


def test_the_app_module_imports_with_no_environment() -> None:
    result = _import_in_a_bare_environment("vega_api.app")

    assert result.returncode == 0, (
        "Importing vega_api.app read the environment. Something at module scope "
        "is calling get_settings(); move it inside create_app().\n\n"
        f"{result.stderr[-2000:]}"
    )


def test_the_guard_is_looking_at_the_right_variables() -> None:
    """The test above is worthless if `Settings` stopped requiring these.

    Then a bare environment would be a valid one, the import would succeed for
    the wrong reason, and the guard would report success while checking nothing.
    """
    from vega_api.config import Settings

    required = {
        field.alias or name for name, field in Settings.model_fields.items() if field.is_required()
    }
    assert required == set(REQUIRED), (
        f"Settings' required variables changed to {sorted(required)}. Update "
        f"REQUIRED so the import test still runs against a genuinely bare "
        f"environment."
    )
