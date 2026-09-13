/**
 * Every wrong value asserted against here is one the obvious browser API
 * actually returns. The point of the file is that "non-empty" was never the
 * same thing as "correct", and HMRC only accepts correct.
 */
import { describe, expect, it } from "vitest";

import {
  collectDeviceHeaders,
  deviceId,
  multiFactor,
  screens,
  timezone,
  userIds,
  windowSize,
} from "./deviceHeaders";

// The same shapes the API refuses on, kept in sync by
// deviceHeaders.contract.test.ts, which reads them out of the Python.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIMEZONE = /^UTC[+-]\d{2}:\d{2}$/;
const SCREEN = /^width=\d+&height=\d+&scaling-factor=\d+(\.\d+)?&colour-depth=\d+$/;
const WINDOW = /^width=\d+&height=\d+$/;

class MemoryStorage implements Storage {
  private store = new Map<string, string>();
  get length(): number {
    return this.store.size;
  }
  clear(): void {
    this.store.clear();
  }
  getItem(key: string): string | null {
    return this.store.get(key) ?? null;
  }
  key(index: number): string | null {
    return [...this.store.keys()][index] ?? null;
  }
  removeItem(key: string): void {
    this.store.delete(key);
  }
  setItem(key: string, value: string): void {
    this.store.set(key, value);
  }
}

describe("deviceId", () => {
  it("is a UUID", () => {
    expect(deviceId(new MemoryStorage())).toMatch(UUID);
  });

  it("is the same on the next visit", () => {
    // A device that reports a new id every reload looks like thousands of
    // devices, which is what the header is meant to expose, not produce.
    const store = new MemoryStorage();
    expect(deviceId(store)).toBe(deviceId(store));
  });

  it("replaces a stored value that is not a UUID", () => {
    const store = new MemoryStorage();
    store.setItem("vega.hmrc.deviceId", "vega-device-1");
    expect(deviceId(store)).toMatch(UUID);
  });
});

describe("timezone", () => {
  it("is UTC+hh:mm, not an IANA zone name", () => {
    // Intl.DateTimeFormat().resolvedOptions().timeZone gives "Europe/London".
    expect(timezone()).toMatch(TIMEZONE);
    expect(timezone()).not.toContain("/");
  });

  it("puts British Summer Time ahead of UTC, not behind it", () => {
    // getTimezoneOffset() returns -60 in BST, because it counts minutes TO
    // UTC. Copying that sign straight through reports UTC-01:00.
    const bst = new Date();
    bst.getTimezoneOffset = () => -60;
    expect(timezone(bst)).toBe("UTC+01:00");
  });

  it("puts a zone behind UTC behind it", () => {
    const newYork = new Date();
    newYork.getTimezoneOffset = () => 300;
    expect(timezone(newYork)).toBe("UTC-05:00");
  });

  it("handles UTC itself without a stray minus", () => {
    const utc = new Date();
    utc.getTimezoneOffset = () => 0;
    expect(timezone(utc)).toBe("UTC+00:00");
  });

  it("keeps a part-hour offset", () => {
    // India is +05:30. Truncating to whole hours would be wrong for the person
    // who wrote this, sitting in it.
    const india = new Date();
    india.getTimezoneOffset = () => -330;
    expect(timezone(india)).toBe("UTC+05:30");
  });
});

describe("screens", () => {
  it("is the four key-value fields HMRC names", () => {
    const screen = { width: 1920, height: 1080, colorDepth: 24 } as Screen;
    expect(screens(screen, 1)).toBe(
      "width=1920&height=1080&scaling-factor=1&colour-depth=24",
    );
  });

  it("keeps a fractional scaling factor", () => {
    // HMRC's own example carries 1.25, so rounding it would be our bug.
    const screen = { width: 3000, height: 2000, colorDepth: 16 } as Screen;
    expect(screens(screen, 1.25)).toContain("scaling-factor=1.25");
    expect(screens(screen, 1.25)).toMatch(SCREEN);
  });

  it("rounds fractional pixel dimensions to whole numbers", () => {
    const screen = { width: 1919.5, height: 1079.5, colorDepth: 24 } as Screen;
    expect(screens(screen, 1)).toMatch(SCREEN);
  });
});

describe("windowSize", () => {
  it("is width and height only", () => {
    expect(windowSize({ innerWidth: 1256, innerHeight: 803 })).toBe(
      "width=1256&height=803",
    );
  });

  it("rounds a fractional window", () => {
    // A zoomed browser reports fractions, and "width=1256.25" is refused.
    expect(windowSize({ innerWidth: 1256.25, innerHeight: 803.5 })).toMatch(WINDOW);
  });
});

describe("userIds", () => {
  it("is key=value", () => {
    expect(userIds({ vega: "alice123" })).toBe("vega=alice123");
  });

  it("encodes a value that would otherwise split the field", () => {
    // An email is a normal identifier, and an unencoded comma or equals sign
    // turns one identifier into two.
    expect(userIds({ vega: "a,b=c" })).toBe("vega=a%2Cb%3Dc");
  });

  it("drops an empty value rather than sending a bare key", () => {
    expect(userIds({ vega: "alice123", hmrc: "" })).toBe("vega=alice123");
  });
});

describe("multiFactor", () => {
  it("is empty when no second factor was used", () => {
    // Truthful, and accepted. Inventing an entry would be the fraud the header
    // is there to catch.
    expect(multiFactor([])).toBe("");
  });

  it("is minute precision with the colon encoded", () => {
    const value = multiFactor([
      {
        type: "AUTH_CODE",
        at: new Date("2026-09-07T13:23:45.678Z"),
        uniqueReference: "fc4b5fd6",
      },
    ]);
    expect(value).toBe(
      "type=AUTH_CODE&timestamp=2026-09-07T13%3A23Z&unique-reference=fc4b5fd6",
    );
    // toISOString() would have left seconds and milliseconds in.
    expect(value).not.toContain("45");
  });

  it("comma separates more than one", () => {
    const uses = [
      { type: "AUTH_CODE", at: new Date("2026-09-07T13:23:00Z"), uniqueReference: "a" },
      { type: "TOTP", at: new Date("2026-09-07T13:20:00Z"), uniqueReference: "b" },
    ];
    expect(multiFactor(uses).split(",")).toHaveLength(2);
  });
});

describe("collectDeviceHeaders", () => {
  it("produces every value in the shape the server accepts", () => {
    const all = collectDeviceHeaders({ vega: "alice123" });
    expect(all.deviceId).toMatch(UUID);
    expect(all.timezone).toMatch(TIMEZONE);
    expect(all.screens).toMatch(SCREEN);
    expect(all.windowSize).toMatch(WINDOW);
    expect(all.userIds).toBe("vega=alice123");
    expect(all.multiFactor).toBe("");
    expect(all.browserJsUserAgent.length).toBeGreaterThan(0);
  });
});
