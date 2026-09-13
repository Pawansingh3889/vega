/**
 * The seven fraud prevention values only this browser can know.
 *
 * HMRC's WEB_APP_VIA_SERVER connection method requires these to be collected on
 * the originating device and relayed to the server, which adds the nine it can
 * observe itself. The server refuses a value that is absent OR the wrong shape,
 * so this module's whole job is producing the exact strings HMRC publishes.
 *
 * Formats are from HMRC's connection method guide. Where the obvious browser
 * API returns something close but wrong, the comment says so, because that is
 * the mistake this file exists to not make.
 */

const DEVICE_ID_KEY = "vega.hmrc.deviceId";

export interface DeviceHeaders {
  deviceId: string;
  browserJsUserAgent: string;
  screens: string;
  windowSize: string;
  timezone: string;
  userIds: string;
  multiFactor: string;
}

/**
 * A UUID that survives reloads, because HMRC wants it stable per device.
 *
 * Regenerating it every visit would report one device as thousands, which reads
 * to HMRC's conformance checks as exactly the evasion the header is there to
 * detect. localStorage is the store because the value has to outlive the tab
 * and must not travel to another device.
 */
export function deviceId(store: Storage = localStorage): string {
  const existing = store.getItem(DEVICE_ID_KEY);
  // A value written by an older build, or by hand, is not necessarily a UUID.
  // Keeping it would send the server something it will refuse, so it is
  // replaced rather than trusted.
  if (existing !== null && isUuid(existing)) {
    return existing;
  }
  const fresh = crypto.randomUUID();
  store.setItem(DEVICE_ID_KEY, fresh);
  return fresh;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

/**
 * `UTC±hh:mm`, which is NOT what the obvious API gives you.
 *
 * `Intl.DateTimeFormat().resolvedOptions().timeZone` returns "Europe/London".
 * That is non-empty and looks right in a log, so it used to pass every check we
 * had and would have been filed to HMRC as a malformed header.
 *
 * The sign is also inverted on the way in: getTimezoneOffset() returns the
 * minutes to ADD to local time to reach UTC, so British Summer Time is -60, not
 * +60. Copying the sign across is the second mistake here, and it silently
 * reports every UK user as being in the wrong hemisphere of the clock.
 */
export function timezone(now: Date = new Date()): string {
  const minutesToUtc = now.getTimezoneOffset();
  const aheadOfUtc = -minutesToUtc;
  const sign = aheadOfUtc < 0 ? "-" : "+";
  const total = Math.abs(aheadOfUtc);
  const hours = Math.floor(total / 60);
  const minutes = total % 60;
  return `UTC${sign}${pad(hours)}:${pad(minutes)}`;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

/**
 * `width=<n>&height=<n>&scaling-factor=<n>&colour-depth=<n>`, comma separated
 * when there is more than one screen.
 *
 * A plain browser can only see the screen it is on. Reporting one screen
 * honestly beats guessing at a second.
 */
export function screens(source: Screen = window.screen, ratio = window.devicePixelRatio): string {
  return [
    `width=${Math.round(source.width)}`,
    `height=${Math.round(source.height)}`,
    // HMRC's own example carries 1.25, so the decimal is kept rather than
    // rounded to a whole number.
    `scaling-factor=${ratio}`,
    `colour-depth=${source.colorDepth}`,
  ].join("&");
}

/** `width=<n>&height=<n>`. The window, not the screen. Whole numbers only. */
export function windowSize(view: { innerWidth: number; innerHeight: number } = window): string {
  return `width=${Math.round(view.innerWidth)}&height=${Math.round(view.innerHeight)}`;
}

/**
 * `key=value` pairs naming the accounts the user holds with us.
 *
 * The value is percent-encoded because an email address is a normal user
 * identifier and an unencoded comma or equals sign would split one identifier
 * into two.
 */
export function userIds(ids: Record<string, string>): string {
  return Object.entries(ids)
    .filter(([, value]) => value !== "")
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join(",");
}

/**
 * `type=<t>&timestamp=<yyyy-MM-ddThh:mmZ>&unique-reference=<r>`, comma separated.
 *
 * An empty string is returned when the session used no second factor, and that
 * is a truthful answer rather than a gap: the server accepts it and inventing
 * an entry would be the actual fraud this header guards against.
 */
export interface MultiFactorUse {
  type: string;
  at: Date;
  uniqueReference: string;
}

export function multiFactor(uses: readonly MultiFactorUse[]): string {
  return uses
    .map((use) => {
      // yyyy-MM-ddThh:mmZ, to the minute. toISOString() carries seconds and
      // milliseconds, which is a different format from the one published.
      const stamp = `${use.at.toISOString().slice(0, 16)}Z`;
      return [
        `type=${encodeURIComponent(use.type)}`,
        `timestamp=${encodeURIComponent(stamp)}`,
        `unique-reference=${encodeURIComponent(use.uniqueReference)}`,
      ].join("&");
    })
    .join(",");
}

/** Everything the browser owes the submission, in one object. */
export function collectDeviceHeaders(
  ids: Record<string, string>,
  mfa: readonly MultiFactorUse[] = [],
): DeviceHeaders {
  return {
    deviceId: deviceId(),
    // Deliberately navigator.userAgent and not the request header. HMRC asks
    // for the value "as reported by the browser" to JavaScript, and the two
    // differ often enough that substituting one for the other is a finding.
    browserJsUserAgent: navigator.userAgent,
    screens: screens(),
    windowSize: windowSize(),
    timezone: timezone(),
    userIds: userIds(ids),
    multiFactor: multiFactor(mfa),
  };
}
