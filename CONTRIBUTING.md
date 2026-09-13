# Contributing to Vega

**Thank you for being here.** Vega is a UK-first ERP for small British
businesses, aimed first at small food manufacturers: they are legally required
to trace every batch, and most of them do it in spreadsheets. That target is a
hypothesis with no customer discovery behind it yet, which explains a good deal
about why the code looks the way it does, so please treat the domain model as
considered rather than settled.

A request, gently: there is a lot of documentation in this repository, and it
can read as a high bar. It is not meant to be. It exists so that nobody has to
guess at a rule that was already decided, and every rule in it names the thing
that went wrong to cause it. If any of it reads as unwelcoming, that is a bug in
the writing, and an issue saying so is a genuinely useful contribution.

Contributions that are not code are wanted just as much: documentation, a review
comment on somebody else's PR, a bug report with a clean reproduction, a
correction to a VAT rule, or a paragraph about how a real UK business actually
handles something. All of them are recognised the same way, see
[Recognition](#recognition) below.

Everyone taking part is asked to follow the
[Code of Conduct](CODE_OF_CONDUCT.md). [GOVERNANCE.md](GOVERNANCE.md) says who
decides what, and how a contributor becomes a maintainer.

> **On the `lane:` labels.** You will see them on some issues. They are an
> internal scheduling scheme for work happening in the maintainer's own clone,
> and they are **not a claim against you**. Pick up any issue that is not
> already assigned. The `good first issue` batch deliberately carries no lane at
> all.

## Your first contribution, end to end

```bash
# 1. Fork on GitHub, then clone your fork
git clone https://github.com/<your-username>/vega.git
cd vega
git remote add upstream https://github.com/Pawansingh3889/vega.git

# 2. Set up and check that a clean checkout is green before you change anything
make setup
make gate

# 3. Branch
git switch -c fix/the-thing-you-are-fixing

# 4. Make the change, then prove it
make gate

# 5. Push to your fork and open a PR against main
git push -u origin fix/the-thing-you-are-fixing
```

Then open the PR and say **why** in the description. That is the part a diff
cannot show you, and it is the only part of the checklist people find hard.

If `make gate` fails on a clean checkout, before you have touched anything, that
is a bug in `main`. Please open an issue rather than assuming it is you.

## Setup

You need **Node 22+**, **pnpm 11+**, **uv**, and a **container runtime**
(Docker or Podman). The container runtime is not optional: the database tests
build a real Postgres, because row level security cannot be exercised against a
mock.

```bash
git clone https://github.com/Pawansingh3889/vega.git
cd vega
make setup          # pnpm install, uv sync
make gate           # everything CI runs, in CI's order
```

`make gate` should pass on a clean checkout. If it does not, that is a bug in
`main` and worth an issue on its own.

Most work needs no database credentials. The suites that do build their own
throwaway Postgres from `supabase/migrations`. Only tasks that touch the hosted
project need `.env`, and a maintainer will supply it.

## Running things

| Command | What it does |
|---|---|
| `make gate` | Everything CI runs. Run this before pushing. |
| `make test` | Python suite, including the tenant isolation tests |
| `make lint` / `make typecheck` | eslint and ruff / tsc and mypy |
| `make db-verify` | Builds a fresh database from migrations and asserts its shape |
| `make debt` | The eslint warning breakdown by rule |
| `make edge` | Checks edge functions do not name columns that no longer exist |
| `pnpm dev` | The web app on :8080 |

## Two traps in the tooling

Both are deliberate and both look like mistakes. Please do not "fix" them.

**Typecheck targets `tsconfig.app.json`, not the root config.** The root
`tsconfig.json` is solution-style with `"files": []`, so a bare `tsc --noEmit`
against it compiles **zero files** and passes vacuously. That is how seven real
type errors survived in the upstream fork.

**`pnpm lint` runs with `--max-warnings 79`.** That is inherited debt, capped so
it can only go down. Lower the number when you burn some off. **Never raise it.**

## Branch naming

| Prefix | When |
|---|---|
| `feat/` | New behaviour |
| `fix/` | Bug fixes |
| `docs/` | Documentation |
| `chore/` | Tooling, dependencies, CI |

GitHub Flow: branch off `main`, PR back into `main`, squash-merge. `main` is
always releasable.

## Picking up an issue

Soft assignment, so nobody duplicates work:

- **Comment on the issue** saying you would like it. A maintainer assigns it.
- **One or two at a time.** Finish or open a draft PR before taking more.
- **14 days of silence and it goes back in the pool.** A nudge comes first, and
  you can pick it up again by commenting.
- **Anything labelled `needs-design`: post your approach in the issue and wait
  for a reply before building.** Those are issues where the shape matters more
  than the implementation, and rework is likely otherwise.
- **`good first issue`: just open the PR.** No need to ask.

## The rules that are not negotiable

[SECURITY.md](SECURITY.md) has six of them, N1 through N6, and they are
enforced by tests and migrations rather than by review. The three that catch
people out:

- **N1: every table has row level security and a tenant isolation test.** The
  suite is generated from the table list, so a new table without coverage fails
  the build.
- **N2: the ledgers are append-only.** `security_audit_log`,
  `transaction_audit_log`, `batch_movements` and `fx_rates` refuse UPDATE and
  DELETE, for every role including `service_role`. Correct a record by
  appending, never by rewriting.
- **N3: the server produces every number that gets filed.** Nothing computed in
  the browser may reach a VAT return.

## Migrations

Forward-only. **Never edit an existing migration**, and never edit
`00000000000000_inherited_baseline.sql` at all: it is a frozen record of what
was inherited, and every fix on top of it is a reviewable step.

End a migration by asserting what it claims to have done. Nearly every defect
found in this repo so far was invisible to a schema check and only appeared when
something tried to write, so a migration that says it enforced something and did
not is worse than one that did nothing.

## Pull request checklist

- [ ] `make gate` passes
- [ ] New tables have a tenant isolation test (N1)
- [ ] New migrations assert their own outcome
- [ ] `CHANGELOG.md` updated under `[Unreleased]`, unless this is pure CI or a
      dependency bump
- [ ] The PR says *why*, not just what. A diff shows what changed; the
      description is where the reasoning lives.

## Commit style

Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `build:`,
`ci:`, `test:`, `perf:`.

Write the body for whoever reads it in six months. If you rejected an
alternative, say which and why: that is the part nobody can reconstruct later.

## Secrets

Never commit one. `.env` is gitignored and `.env.example` is the template.
Credentials for the hosted project live in a password manager, not in the repo,
and not in a chat message.

If you find one committed, say so in a
[security advisory](https://github.com/Pawansingh3889/vega/security/advisories/new)
rather than a public issue.

## Recognition

Contribution should be visible, so:

- **The contributors table in the [README](README.md#contributors)** is built
  with [all-contributors](https://allcontributors.org). It recognises code,
  documentation, review, design, bug reports, ideas, testing and translation,
  not only commits. A maintainer adds you when your first contribution lands.
  If you were missed, please say so in an issue: that is an oversight, never a
  judgement.
- **Release notes and `CHANGELOG.md` name who did the work** and link the PR.
- **[GOVERNANCE.md](GOVERNANCE.md)** describes the route from a first PR to
  triage rights to maintainer, so sustained work leads somewhere rather than
  nowhere in particular.

You keep the copyright in what you write. There is no CLA to sign. By opening a
PR you are contributing it under [AGPL-3.0](LICENSE), the same licence the rest
of the project carries.

## What review here is like

So that it is not a surprise:

- **A reviewer will ask why, not just what.** If a comment asks for the
  reasoning behind a choice, it is not a challenge to your competence. The
  reasoning is the thing that cannot be reconstructed from the diff in six
  months.
- **Most of the rules are enforced by the build, not by a person.** `make gate`
  will tell you about the tenant isolation test before a human has to, which is
  deliberate: it keeps review about the design rather than about compliance.
- **"This needs an ADR" is a normal outcome** for a PR that turns out to
  encode a decision nobody has written down yet. It means the work was
  worthwhile and the discussion moved up a level, not that it was wrong.
- **A closed PR is not a closed door.** If an approach is rejected, the issue
  stays open and you are welcome on the next one. Please do say if a review
  felt unfair; that is worth hearing.

## If you get stuck

Please just ask, at any stage, including halfway through and including if you
are not sure the question is a good one.
[Discussions](https://github.com/Pawansingh3889/vega/discussions) is the right
place, and [SUPPORT.md](SUPPORT.md) lists where each kind of question goes. An
unfinished draft PR with a question in the description is completely welcome
and often the fastest way to get an answer.
