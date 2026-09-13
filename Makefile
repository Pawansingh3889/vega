.PHONY: setup lint fmt typecheck test gate build debt waivers db-verify seed drill drift edge migrations worker fx-status clean

setup:
	pnpm install
	cd apps/api && uv sync --extra dev

lint:
	pnpm --filter @vega/web run lint
	cd apps/api && uv run ruff check .
	cd apps/api && uv run lint-imports
	scripts/check-citations.py
	scripts/check-reachable.py

fmt:
	cd apps/api && uv run ruff format .

typecheck:
	pnpm --filter @vega/web run typecheck
	cd apps/api && uv run mypy

test:
	cd apps/api && VEGA_REQUIRE_DB=1 uv run pytest -q
# The web half of the fraud prevention headers is only checkable here. The
# server refuses a wrongly shaped value, so a browser that formats one
# badly fails at filing time, which is the worst moment to find out.
	pnpm --filter @vega/web run test

build:
	pnpm --filter @vega/web run build

# Everything CI runs, in the order CI runs it.
# Report the eslint debt by rule. Never fails; the ceiling is the gate.
debt:
	node scripts/lint-debt.mjs

# Fail if a dependency audit waiver has expired. See security/README.md.
waivers:
	python3 scripts/check_audit_waivers.py

# Prove a fresh database builds from migrations alone and lands where we think.
# Needs a container runtime; not part of `gate` because CI runs it as its own job.
db-verify:
	./scripts/verify-baseline.sh

# Load the known dataset. --hosted needs .env and pass.
seed:
	./scripts/seed-demo.sh --hosted

# Back up the London project and prove the backup restores. Phase 1's last exit
# criterion. Restores into a local Postgres, not a fresh Supabase project.
drill:
	./scripts/restore-drill.sh --hosted

# Does the hosted database still match the migrations? Catches a dashboard edit,
# which nothing else can see: every other check rebuilds from the migrations and
# therefore agrees with itself.
drift:
	./scripts/check-schema-drift.sh

# Break each gate check on purpose and confirm it refuses. Needs a clean tree.
prove:
	./scripts/prove-gate-checks.sh

# What the hosted project is missing. Reads only; changes nothing.
db-status:
	./scripts/apply-migrations.sh

# Apply pending migrations to the hosted project, then prove the drift is gone.
db-push:
	./scripts/apply-migrations.sh --apply

# Edge functions run on Supabase, outside tsc and outside the test suite, so a
# migration can break sign-in and every other gate stays green. This is the only
# thing that looks.
edge:
	python3 scripts/check-edge-function-columns.py

# Run the job worker locally, in the image Fly would run. Free, and the FX
# history it accrues cannot be backfilled once a day has passed.
worker:
	./scripts/run-worker-local.sh start

# What rates do we actually hold, and how recent is the newest? The worker only
# runs while this machine is awake, so this is the check that matters.
fx-status:
	@./scripts/fx-status.sh

# Migration filenames must order unambiguously and never collide. With several
# contributors at once, two branches both writing 0018_ is a matter of time, and each
# passes its own gate.
migrations:
	python3 scripts/check-migrations.py

gate: lint typecheck test build waivers edge migrations
	pnpm audit --audit-level moderate
	cd apps/api && uv run ruff format --check . && uv lock --check
	@node scripts/lint-debt.mjs

clean:
	rm -rf node_modules apps/web/node_modules apps/web/dist apps/api/.venv
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
