# Governance

Vega has one maintainer today. This file says how that changes, because a
project that cannot explain how someone gains rights is a project where
sustained work leads nowhere, and people are right not to invest in it.

## Who decides what

| Decision | Who |
|---|---|
| Merging a PR | Any maintainer, except their own |
| A new ADR in `docs/decisions/` | Maintainer, after the issue discussion |
| Changing `SPEC.md` or `SECURITY.md` | Lead maintainer only |
| A new phase in `ROADMAP.md` | Lead maintainer, after the cross-questioning round |
| Adding a maintainer | Lead maintainer, on a public nomination |

**Lead maintainer:** [@Pawansingh3889](https://github.com/Pawansingh3889).

The schema and the six non-negotiables are the two places where a mistake is
expensive and slow to reverse, which is why they are the two the lead holds.
Everything else is delegated as fast as there is somebody to delegate it to.

## The three levels

### Contributor

Anyone who opens an issue or a PR. Nothing to apply for. Your first merged PR
gets you added to the contributors table in the README, and named in the
release notes.

### Triager

**What you get:** the `triage` role on the repository. You can label, assign,
close and reopen issues, and request changes on a PR.

**How you get there:** three merged PRs, or sustained issue triage of similar
weight, and one nomination in a public issue. Reviewing other people's PRs
counts. So does documentation.

**What it is for:** the bottleneck on this project is not writing code, it is
reading it. A triager who says "this needs a tenant isolation test" before a
maintainer looks is worth more than one more feature.

### Maintainer

**What you get:** the `maintain` role. Merge rights, and a say in the ADRs.

**How you get there:** sustained review as a triager over a couple of months,
and a nomination the existing maintainers agree with. There is no fixed commit
count, because the thing being judged is judgement, not volume. Concretely,
what we look for:

- You have reviewed PRs in an area you did not write, and caught something.
- You have said no to something, including to the lead maintainer, and been
  right. This is the one that matters most.
- You know which of the six non-negotiables applies without looking it up.

**What you take on:** merge rights are a duty, not a trophy. A maintainer is
expected to say when they are out of time, and stepping back is normal and
carries no stigma. Emeritus maintainers keep their line in the contributors
table.

## Areas

An issue carries one `area:` label (`area:db`, `area:api`, `area:web`,
`area:ci`). A maintainer is usually a maintainer *of an area*, not of the whole
repository. `area:db` is the slowest to hand over, because migrations are
forward-only and a bad one is permanent.

The `lane:` labels are a different thing: an internal scheduling scheme for
parallel work in the maintainer's own clone. They are not a claim against an
outside contributor, and the `good first issue` batch carries no lane at all.

## Disagreement

1. **Say it in the issue, before the code.** `SPEC.md` and the ADRs are binding
   while they stand, and the way to change one is to argue against it in
   writing, not to implement the other reading and let the merge settle it.
2. **If the issue stalls, the lead maintainer decides,** and writes an ADR in
   `docs/decisions/` saying what was rejected and why. A decision without a
   written rejection is a decision that gets re-litigated in six months.
3. **A rejected approach is not a rejected person.** If your PR is closed, the
   issue that prompted it stays open and you are welcome on the next one.

## Being unresponsive

Maintainers go quiet. It happens, usually for good reasons. If the lead
maintainer is unreachable for 90 days, the remaining maintainers may act
together in their place, including on `SPEC.md`. If there are no maintainers
left, the licence is the point: AGPL-3.0 means anybody can fork and continue,
and that is the real continuity guarantee here, not this paragraph.

## Changing this file

By PR, like anything else. It is a description of how the project actually
works, so if it stops matching reality, the file is what is wrong.
