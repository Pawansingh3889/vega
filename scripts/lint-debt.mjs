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

const CEILING = 79; // keep in step with apps/web/package.json's --max-warnings

let raw;
try {
  raw = execFileSync(
    "pnpm",
    ["--filter", "@vega/web", "exec", "eslint", ".", "--format", "json"],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
} catch (e) {
  // eslint exits non-zero when it reports problems; the JSON is still on stdout.
  raw = e.stdout ?? "";
}

const start = raw.indexOf("[");
if (start === -1) {
  console.error("lint-debt: no JSON report on stdout, skipping");
  process.exit(0);
}

const results = JSON.parse(raw.slice(start));
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
