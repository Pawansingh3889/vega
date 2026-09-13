# Getting help

Vega is pre-release and maintained by one person, so please bear with the
response times. Every one of these is a fine way to ask.

| You want to | Go here |
|---|---|
| Ask how something works | [Discussions, Q&A](https://github.com/Pawansingh3889/vega/discussions/categories/q-a) |
| Report something broken | [Bug report](https://github.com/Pawansingh3889/vega/issues/new?template=bug_report.yml) |
| Propose a feature | [Feature request](https://github.com/Pawansingh3889/vega/issues/new?template=feature_request.yml) |
| Report a vulnerability | [Security advisory](https://github.com/Pawansingh3889/vega/security/advisories/new), privately, never a public issue |
| Understand a domain rule | [SPEC.md](SPEC.md) first, then ask in Discussions |
| Know why a choice was made | [docs/decisions/](docs/decisions/) |

## Before you ask about a failing build

`make gate` is meant to pass on a clean checkout. If it does not, that is a bug
in `main` and worth an issue on its own, so please do open one rather than
assuming you broke it.

Two things trip almost everybody up, and both are documented in
[CONTRIBUTING.md](CONTRIBUTING.md):

- **You need a container runtime.** Docker or Podman. The database tests build a
  real Postgres, because row level security cannot be exercised against a mock.
- **Node 22+, pnpm 11+, and uv.** An older Node fails in ways that do not name
  the version as the cause.

Please include the output of `node -v`, `uv --version`, and whether you are on
Docker or Podman. It saves a round trip.

## What we cannot help with

**Tax advice.** Vega implements VAT rules as [SPEC.md](SPEC.md) reads them, and
that document cites HMRC where it can, but nobody here is your accountant. If a
figure Vega produces disagrees with your accountant, the accountant is right and
we would very much like to see the issue.

## Commercial support

There is none yet. If you are a small UK business considering running Vega for
real, please open a Discussion and say so. The target user is currently a
hypothesis with no customer discovery behind it, and hearing from an actual one
would be more valuable than any feature on the roadmap.
