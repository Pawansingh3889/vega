# Vega

[![Licence: AGPL v3](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)
[![All Contributors](https://img.shields.io/badge/all_contributors-1-orange.svg)](#contributors)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> A UK-first ERP for small British businesses.

**New here and thinking of contributing? Welcome.** Start with
[CONTRIBUTING.md](CONTRIBUTING.md), and please do not be put off by how much
documentation there is: it exists so that nobody has to guess, not because the
bar is high. Issues labelled
[`good first issue`](https://github.com/Pawansingh3889/vega/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
are self-contained and safe to learn on, and you do not need to ask before
taking one.

**About to open your first PR?** [START-HERE.md](START-HERE.md) is seven short
rules and two minutes. Every one of them is there because something went wrong
without it.

Stock, sales, purchasing and finance, with Making Tax Digital VAT filing, EU trade
and product carbon footprints designed into the schema rather than bolted on
afterwards.

Vega is a fork, rebuilt around a UK-native domain model. It is the system of
record for the business that runs it: stock levels, what was sold, what is owed,
and what gets filed.

## Status

**Phase 3, invoicing.** The schema history is `supabase/migrations`, applied to Supabase London with
`make db-push` and checked with `make drift`, the
FastAPI service verifies ES256 tokens and impersonates the caller per request, and
a Procrastinate worker runs under systemd. Each phase's exit condition is in
[ROADMAP.md](ROADMAP.md); check the board rather than this line for what is left.

The first target is small UK food manufacturers, who are legally required to
trace every batch and mostly do it in spreadsheets. That is a **hypothesis with
no customer discovery behind it yet**, so please treat the domain model as
considered rather than settled. If you run a business like this, saying so in an
issue is worth more than any feature on the roadmap.

Read in this order:

| Document | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | The stack, why each piece is there, and the layering rules |
| [SPEC.md](SPEC.md) | The domain: VAT treatments, currency, invoices, carbon, EU regimes |
| [ROADMAP.md](ROADMAP.md) | Nine phases, each with a concrete exit condition |
| [SECURITY.md](SECURITY.md) | Six non-negotiables, and the defects inherited from the fork |
| [docs/decisions/](docs/decisions/) | Why each significant choice was made, and what was rejected |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setup, the gate, branch and PR conventions, how issues are picked up |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | How we treat each other here |
| [GOVERNANCE.md](GOVERNANCE.md) | Who decides what, and the route from first PR to maintainer |
| [SUPPORT.md](SUPPORT.md) | Where to ask a question |
| [START-HERE.md](START-HERE.md) | The seven rules, read before your first commit |

## Layout

```
vega/
├── apps/
│   ├── web/          the forked React app, pnpm
│   └── api/          FastAPI service, uv
├── supabase/         migrations, the single schema history
└── docs/             architecture, decisions, discovery
```

## Quick start

You need **Node 22+**, **pnpm 11+**, **uv**, and a **container runtime** (Docker
or Podman). The container runtime is not optional: the database tests build a
real Postgres, because row level security cannot be exercised against a mock.

```bash
git clone https://github.com/Pawansingh3889/vega.git
cd vega
make setup     # pnpm install, uv sync
make gate      # everything CI runs, in CI's order
pnpm dev       # the web app on :8080
```

`make gate` is meant to pass on a clean checkout with no credentials. If it does
not, that is a bug in `main` and worth an issue on its own. Only tasks that touch
the hosted Supabase project need a `.env`, and a maintainer will supply one.

## Contributing

Contributions are very welcome, and that includes ones that are not code:
documentation, a review comment, a bug report with a clean reproduction, or a
sentence about how a real UK business actually handles something.

Read [CONTRIBUTING.md](CONTRIBUTING.md). The short version: fork it, branch,
`make setup && make gate` should pass on a clean checkout, and open a PR saying
*why*. Issues are soft-assigned by commenting on them, except
`good first issue`, where you can just open the PR.

- [`good first issue`](https://github.com/Pawansingh3889/vega/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  is self-contained and safe to learn on.
- [`help wanted`](https://github.com/Pawansingh3889/vega/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
  is where an extra pair of hands would genuinely help.
- [`needs-design`](https://github.com/Pawansingh3889/vega/issues?q=is%3Aissue+is%3Aopen+label%3Aneeds-design)
  wants an approach agreed in the issue before any code.

The six rules in [SECURITY.md](SECURITY.md) are enforced by tests and migrations
rather than by review, so the build will tell you before a human has to.
[GOVERNANCE.md](GOVERNANCE.md) has the route from a first PR to triage rights to
maintainer, because sustained work should lead somewhere visible.

Two things worth saying plainly, since they are easy to get wrong and neither is
your fault: the `lane:` labels are a collision-avoidance scheme for automated
agents and **do not apply to you**, and a closed PR is never a closed door. The
issue stays open and you are welcome on the next one.

## Working rule

Every phase opens with two-way cross-questioning before any code is written:
recommendations with defaults stated, challenged, then built. A phase that has not
been through that round has not started.

## Contributors

Thank you to everyone who has put time into Vega. This list is built with
[all-contributors](https://allcontributors.org), and it recognises
documentation, review, design, bug reports and ideas, not only commits. If you
contributed and are not here, that is an oversight rather than a judgement:
please open an issue and it will be fixed.

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Pawansingh3889"><img src="https://avatars.githubusercontent.com/u/Pawansingh3889?v=4?s=80" width="80px;" alt="Pawansingh Kapkoti"/><br /><sub><b>Pawansingh Kapkoti</b></sub></a><br /><a href="#code-Pawansingh3889" title="Code">💻</a> <a href="#doc-Pawansingh3889" title="Documentation">📖</a> <a href="#design-Pawansingh3889" title="Design">🎨</a> <a href="#maintenance-Pawansingh3889" title="Maintenance">🚧</a> <a href="#security-Pawansingh3889" title="Security">🛡️</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

## Licence

[GNU AGPL-3.0](LICENSE). You may run Vega, read it, change it and share it. If
you run a modified version as a network service, AGPL section 13 requires you to
offer your users the source of your version.

This was chosen deliberately over a permissive licence. Vega is a system of
record for somebody's business, and the point of the copyleft is that a company
running it can always get at, and keep, the code their books depend on.

Copyright (C) 2026 Pawansingh Kapkoti and Vega contributors.
