# Dependency audit waivers

> **Last updated:** 5 September 2026
> **Review cadence:** monthly, first working day.

`make gate` and CI run `pnpm audit --audit-level moderate`. That gate will
eventually fail on a moderate advisory in a transitive dependency with no fix
available. A gate with no escape hatch gets bypassed within weeks, usually by
someone deleting it under deadline, so the escape hatch is defined here before it
is needed rather than improvised when it is.

## The rule

An advisory may be waived only when **all four** hold:

1. There is no fixed version available, or upgrading breaks the build in a way
   that cannot be resolved this week.
2. The vulnerable code path is not reachable from Vega, and the entry says why in
   one sentence a reviewer can check.
3. The waiver names an owner and an expiry no more than **90 days** out.
4. The entry is reviewed at the next monthly review, not silently renewed.

An advisory in a **direct** dependency is not waived. It is fixed, or the
dependency is replaced.

## The register

`security/audit-waivers.json`. One object per advisory:

```json
{
  "ghsa": "GHSA-xxxx-xxxx-xxxx",
  "package": "some-transitive-package",
  "severity": "moderate",
  "reason": "Prototype pollution in a CLI path the app never invokes; no fix released.",
  "granted": "2026-09-05",
  "expires": "2026-12-04",
  "owner": "Pawansingh3889"
}
```

`scripts/check_audit_waivers.py` runs in CI and fails when any entry is expired,
missing a field, or dated more than 90 days ahead. An expired waiver is a build
failure, which is the point: it forces the monthly review to actually happen.

Waived advisories are also listed under `auditConfig.ignoreGhsas` in
`pnpm-workspace.yaml`, which is what makes `pnpm audit` pass. The checker asserts
the two lists match, so a waiver cannot be applied to the tool without being
recorded here with a reason and an expiry.

## Monthly review

First working day of the month, for each entry:

- Is a fixed version out now? Then upgrade and delete the entry.
- Is the reachability argument still true after the code has moved?
- Is it about to expire? Renewal is a fresh decision, not a date bump.

Deleting an entry is the normal outcome. An entry renewed twice is a signal to
replace the dependency.
