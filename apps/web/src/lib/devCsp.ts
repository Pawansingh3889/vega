/**
 * Widen index.html's Content-Security-Policy meta tag for local development,
 * without touching the shipped production policy.
 *
 * Two real bugs lived in the version of this before it was a testable module,
 * both silent because the one condition that would have exercised them
 * (VITE_SUPABASE_URL pointing at a local http:// stack) has never been true in
 * this project's normal dev setup, which uses the hosted Supabase project.
 *
 * 1. The browser enforces the INTERSECTION of every CSP present on a page. A
 *    response header AND a <meta> tag both apply, and widening only the
 *    header (#135) does nothing while the meta tag stays narrow: every local
 *    API call died as a bare "TypeError: Failed to fetch" with no CSP
 *    violation logged anywhere application code could see, because the
 *    browser refuses the connection before fetch() gets an event describing
 *    why. Both surfaces have to be widened together.
 *
 * 2. The regex used to find connect-src in the meta tag had no anchor:
 *    the unanchored pattern connect-src followed by [^;"]*, with no start
 *    anchor. index.html carries an HTML COMMENT directly above
 *    the tag, explaining the CSP's history in prose that itself contains the
 *    words "connect-src" twice. [^;"] matches newlines, so the unanchored
 *    regex matched the COMMENT's first occurrence and swallowed everything
 *    up to the next ; or " character, landing deep inside the real tag. The
 *    widening then modified the wrong span and changed nothing a browser
 *    reads. Anchoring on the actual <meta http-equiv="Content-Security-Policy"
 *    ...> tag's content attribute is what makes this correct rather than
 *    merely plausible.
 */

const CSP_META_CONNECT_SRC =
  /(<meta http-equiv="Content-Security-Policy" content="[^"]*?connect-src)([^;"]*)/;

/**
 * Append origins to the CSP meta tag's connect-src. A no-op if there is
 * nothing to add or no such tag is present.
 */
export function widenConnectSrc(html: string, extraOrigins: readonly string[]): string {
  if (extraOrigins.length === 0) return html;
  return html.replace(
    CSP_META_CONNECT_SRC,
    (_match, prefix: string, sources: string) => `${prefix}${sources} ${extraOrigins.join(' ')}`,
  );
}

/**
 * The extra origins to allow, given the local dev environment.
 *
 * Supabase is widened only when VITE_SUPABASE_URL is a local http:// stack
 * (`supabase start`); the normal case here is the hosted project, where
 * nothing needs widening. The API is widened whenever VITE_API_URL is
 * itself http://, which is the local FastAPI case; only its ORIGIN is taken,
 * because a full URL with a path is not a valid connect-src source and would
 * silently invalidate the directive it sits in.
 */
export function devOrigins(supabaseUrl: string, apiUrl: string | undefined): string[] {
  const origins: string[] = [];
  if (supabaseUrl.startsWith('http://')) {
    origins.push(supabaseUrl, supabaseUrl.replace(/^http/, 'ws'));
  }
  if (apiUrl !== undefined) {
    try {
      const origin = new URL(apiUrl).origin;
      if (origin.startsWith('http://')) origins.push(origin);
    } catch {
      // Malformed VITE_API_URL is the deployment's problem; required()
      // reports it far better than a mangled CSP tag would.
    }
  }
  return origins;
}
