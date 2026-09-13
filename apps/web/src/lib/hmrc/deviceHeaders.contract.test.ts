/**
 * The collector and the server's validator have to agree, and nothing in either
 * language can see the other.
 *
 * So this reads the patterns out of the Python and runs the TypeScript output
 * against them. Duplicating them by hand would pass on the day it was written
 * and drift the first time somebody tightens one side, which is exactly the
 * failure it is here to prevent: a value the browser sends happily and the
 * server refuses at filing time.
 */
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { collectDeviceHeaders, screens, timezone, windowSize } from "./deviceHeaders";

const SERVICE = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../../api/src/vega_api/modules/hmrc/service.py",
);

const source = readFileSync(SERVICE, "utf8");

/** Pull one `_NAME = re.compile(r"...")` out of the Python and make it a RegExp. */
function serverPattern(name: string): RegExp {
  const declaration = new RegExp(`_${name}\\s*=\\s*re\\.compile\\(\\s*r"([^"]*)"([^)]*)\\)`, "s");
  const found = declaration.exec(source);
  if (found === null) {
    // Renaming or reformatting the Python constant has to break this loudly.
    // Silently skipping would turn the whole file into decoration.
    throw new Error(
      `could not find _${name} in ${SERVICE}. If it was renamed, rename it here too.`,
    );
  }
  const [, body, flags] = found;
  const verbose = flags.includes("re.X");
  const source_ = (verbose ? body.replace(/\s+/g, "") : body)
    // Python anchors, JavaScript anchors. Same meaning, different spelling.
    .replace(/\\A/g, "^")
    .replace(/\\Z/g, "$");
  return new RegExp(source_, flags.includes("re.I") ? "i" : "");
}

describe("the browser and the server agree on every format", () => {
  it("finds all four patterns, so a rename cannot pass silently", () => {
    for (const name of ["UUID", "TIMEZONE", "SCREEN", "WINDOW_SIZE"]) {
      expect(serverPattern(name).source.length).toBeGreaterThan(0);
    }
  });

  it("accepts the device id the browser generates", () => {
    expect(collectDeviceHeaders({ vega: "a" }).deviceId).toMatch(serverPattern("UUID"));
  });

  it("accepts the timezone the browser reports, in every offset shape", () => {
    const pattern = serverPattern("TIMEZONE");
    for (const minutes of [0, -60, 300, -330, 75, -765]) {
      const at = new Date();
      at.getTimezoneOffset = () => minutes;
      expect(timezone(at)).toMatch(pattern);
    }
  });

  it("accepts the screen string, including a fractional scaling factor", () => {
    const pattern = serverPattern("SCREEN");
    const screen = { width: 1920, height: 1080, colorDepth: 24 } as Screen;
    expect(screens(screen, 1)).toMatch(pattern);
    expect(screens(screen, 1.25)).toMatch(pattern);
    expect(screens(screen, 2)).toMatch(pattern);
  });

  it("accepts the window size, including a zoomed fractional window", () => {
    const pattern = serverPattern("WINDOW_SIZE");
    expect(windowSize({ innerWidth: 1256, innerHeight: 803 })).toMatch(pattern);
    expect(windowSize({ innerWidth: 1256.25, innerHeight: 803.5 })).toMatch(pattern);
  });

  it("refuses what the server refuses", () => {
    // Proves the imported patterns are doing work rather than matching
    // everything, which is how a contract test quietly becomes a no-op.
    expect("Europe/London").not.toMatch(serverPattern("TIMEZONE"));
    expect("1920x1080").not.toMatch(serverPattern("SCREEN"));
    expect("vega-device-1").not.toMatch(serverPattern("UUID"));
  });
});
