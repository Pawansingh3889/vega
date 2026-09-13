# Start here

Read this before you write anything. It is seven short rules and it takes two
minutes. [CONTRIBUTING.md](CONTRIBUTING.md) is the friendlier, longer version,
and it covers setup; this is the part a reviewer will actually look for.

Every rule guards against something that has already gone wrong in this
repository, which is why each one says so rather than just stating the rule.

---

**1. Work on a branch, in your own fork.** Never commit to `main`, and never
work on somebody else's branch. Branch names are `feat/`, `fix/`, `docs/` or
`chore/` followed by something readable.

**1b. One PR, one issue.** `scripts/check-claim.py` runs in CI and enforces it:
a PR says `Closes #<n>` and no other open PR claims that issue. This is not
bureaucracy. Work here has been duplicated before, up to three separate
implementations of one issue, because nobody read the board first.

**2. Read these, in this order:** [CONTRIBUTING.md](CONTRIBUTING.md), then the
issue, then whichever of [SPEC.md](SPEC.md), [SECURITY.md](SECURITY.md) or
[docs/decisions/](docs/decisions/) the issue cites.

**3. `SPEC.md` and the ADRs are binding, not advisory.** If you think a decision
is wrong, say so in the issue and wait for a reply. Please do not build the
other way and let the merge settle it. Two people implementing opposite readings
of one rule is the failure this repo is most exposed to, because both halves
work in isolation and only disagree once they meet.

**4. Stage what you wrote.** Never `git add -A`, never `git commit -a`. Read
`git status` before every commit. This matters more than it looks: a blanket
stage picks up whatever else is in your tree, and generated files and local
config have both reached commits that way.

**5. `make gate` must pass before you push.** Never make a check weaker to get
past it. `--max-warnings` only goes down. If a check blocks you and you think it
is wrong, please open an issue rather than editing it in the same PR as the work
it was blocking.

**6. If you add a check, prove it can fail.** Break the thing on purpose, watch
the check catch it, put it back, and say so in the PR. Six checks in this repo
once passed while doing nothing at all, which is the only reason this rule
exists.

**7. Stay inside the issue.** Something small and in your way: fix it and say so
under its own heading in the PR. Anything larger: open an issue, please do not
widen the PR.

---

Open a PR when the gate is green. Say **why** in the description, not just what,
and name anything you were unsure about. A judgement call you flag yourself is
faster for everyone than one a reviewer has to find.

Stuck at any point? Please ask in
[Discussions](https://github.com/Pawansingh3889/vega/discussions). A draft PR
with a question in the description is welcome too, and is often the quickest way
to an answer.
