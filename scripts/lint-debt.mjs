#!/usr/bin/env node
/**
 * Print the eslint warning debt broken down by rule.
 *
 * The --max-warnings ceiling in apps/web/package.json bounds the TOTAL, which
 * means someone can fix ten warnings and introduce ten more and the gate stays
 * green while the debt quietly changes shape. This makes the shape visible.
 *
 * Never fails the build. The ceiling is the gate; this is the X-ray.
 *
 * Usage:  node scripts/lint-debt.mjs
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CEILING = 79; // keep in step with apps/web/package.json's --max-warnings

// eslint's own stdout can carry pnpm's chatter in front of it (e.g. a
// "[WARN] Tarball download..." line on a slow registry), and that chatter
// can itself start with "[", so hunting for the first "[" on stdout picks
// the wrong one and JSON.parse throws. Writing the report straight to a
// file sidesteps stdout, and pnpm's chatter, entirely.
const dir = mkdtempSync(join(tmpdir(), "vega-lint-debt-"));
const reportPath = join(dir, "report.json");

try {
  execFileSync(
    "pnpm",
    [
      "--filter",
      "@vega/web",
      "exec",
      "eslint",
      ".",
      "--format",
      "json",
      "--output-file",
      reportPath,
    ],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
} catch {
  // eslint exits non-zero when it reports problems; the report file is still written.
}

let raw;
try {
  raw = readFileSync(reportPath, "utf8");
} catch {
  console.error("lint-debt: no JSON report written, skipping");
  process.exit(0);
} finally {
  rmSync(dir, { recursive: true, force: true });
}

const results = JSON.parse(raw);
const byRule = new Map();
const byFile = new Map();
let warnings = 0;
let errors = 0;

for (const file of results) {
  for (const m of file.messages) {
    if (m.severity === 2) errors++;
    if (m.severity !== 1) continue;
    warnings++;
    const rule = m.ruleId ?? "(no rule)";
    byRule.set(rule, (byRule.get(rule) ?? 0) + 1);
    const short = file.filePath.split("/apps/web/").pop();
    byFile.set(short, (byFile.get(short) ?? 0) + 1);
  }
}

const sorted = (m) => [...m.entries()].sort((a, b) => b[1] - a[1]);

console.log(`\neslint debt: ${warnings} warnings, ${errors} errors (ceiling ${CEILING})\n`);
console.log("  by rule");
for (const [rule, n] of sorted(byRule)) {
  console.log(`    ${String(n).padStart(4)}  ${rule}`);
}
console.log("\n  top files");
for (const [file, n] of sorted(byFile).slice(0, 10)) {
  console.log(`    ${String(n).padStart(4)}  ${file}`);
}

if (warnings < CEILING) {
  console.log(
    `\n  ${CEILING - warnings} under the ceiling. Lower --max-warnings to ${warnings} to lock the gain in.`,
  );
}
console.log("");
