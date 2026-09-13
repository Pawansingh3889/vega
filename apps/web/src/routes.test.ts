/**
 * Every route the app navigates to must be a route the app registers.
 *
 * Two bugs on 2026-09-08 were this exact shape, and both looked like something
 * else to the person hitting them:
 *
 *   Signin.tsx did navigate('/dashboard'). No such route existed, so a CORRECT
 *   sign-in fell through App.tsx's `path="*"` and rendered "Oops! Page not
 *   found". The credentials were right and the app reported a missing page.
 *
 *   The same file did navigate('/forgot-password') while the registered route
 *   is '/gated/forgot-password'.
 *
 * Neither is catchable by tsc, eslint or a build: a route is a string, and a
 * string that matches nothing is a valid string. So it is checked here.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

const SRC = resolve(dirname(fileURLToPath(import.meta.url)));

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) return sourceFiles(full);
    return /\.tsx?$/.test(entry) && !/\.test\.tsx?$/.test(entry) ? [full] : [];
  });
}

/** The paths App.tsx registers, minus the catch-all. */
function registeredRoutes(): Set<string> {
  const app = readFileSync(join(SRC, 'App.tsx'), 'utf8');
  const paths = [...app.matchAll(/path="([^"]+)"/g)].map((m) => m[1]);
  expect(paths.length, 'no routes found in App.tsx; has it been restructured?').toBeGreaterThan(3);
  return new Set(paths.filter((p) => p !== '*'));
}

/** Literal internal destinations: navigate('/x'), <Link to="/x">, <Navigate to="/x">. */
function navigationTargets(): { file: string; target: string }[] {
  const found: { file: string; target: string }[] = [];
  for (const file of sourceFiles(SRC)) {
    const source = readFileSync(file, 'utf8');
    for (const m of source.matchAll(/navigate\(\s*['"](\/[^'"]*)['"]/g)) {
      found.push({ file, target: m[1] });
    }
    for (const m of source.matchAll(/\bto=["'](\/[^"']*)["']/g)) {
      found.push({ file, target: m[1] });
    }
  }
  return found;
}

/** A registered route matches if it is identical or is a `:param` template. */
function isRegistered(rawTarget: string, routes: Set<string>): boolean {
  // A query string and a hash are not part of the route. Comparing them
  // whole reported '/vat?period=x' as broken when '/vat' is registered.
  const target = rawTarget.split(/[?#]/)[0];
  if (routes.has(target)) return true;
  const parts = target.split('/');
  return [...routes].some((route) => {
    const candidate = route.split('/');
    if (candidate.length !== parts.length) return false;
    return candidate.every((seg, i) => seg.startsWith(':') || seg === parts[i]);
  });
}

// Known-broken destinations, as a ratchet. Entries may be REMOVED as they are
// fixed and must never be added: a new one is a new dead link, which is the
// thing this file exists to stop. Same shape as the eslint --max-warnings
// ceiling and the forbidden-import list, both of which this repository already
// treats as one-way.
const KNOWN_BROKEN = new Set([
  // GatedBusinessRegistration sends people here after they register. Vega has
  // no billing: no checkout page, no payment integration, nothing. Pointing it
  // at an existing route would send them somewhere wrong instead of nowhere,
  // so the gap is recorded until somebody decides whether Vega charges at all.
  // The sign-in card already claims "Only registered, paid businesses can sign
  // in", which is the same fiction seen from the other end.
  '/checkout',
]);

describe('every navigation target is a registered route', () => {
  it('finds targets to check, so the test cannot pass by finding nothing', () => {
    // Without this the whole file quietly becomes a no-op the first time
    // somebody changes how navigation is written.
    expect(navigationTargets().length).toBeGreaterThan(3);
  });

  it('has no navigation to a route that does not exist', () => {
    const routes = registeredRoutes();
    const broken = navigationTargets()
      .filter(({ target }) => !isRegistered(target, routes))
      .filter(({ target }) => !KNOWN_BROKEN.has(target.split(/[?#]/)[0]))
      .map(({ file, target }) => `${file.replace(SRC, 'src')} -> ${target}`);

    expect(
      broken,
      'these navigate to paths App.tsx does not register, so they land on ' +
        'NotFound. A user who did everything right is told the page is missing.',
    ).toEqual([]);
  });

  it('every known-broken entry is still actually broken', () => {
    // A ratchet that lists a route which now exists is a ratchet nobody has
    // shrunk. This makes leaving a fixed entry in place fail rather than pass.
    const routes = registeredRoutes();
    for (const target of KNOWN_BROKEN) {
      expect(isRegistered(target, routes), `${target} is registered now; remove it from KNOWN_BROKEN`).toBe(false);
    }
  });

  it('registers the route sign-in sends people to', () => {
    // The specific regression: a correct sign-in must land somewhere real.
    const signin = readFileSync(join(SRC, 'pages', 'Signin.tsx'), 'utf8');
    const after = /navigate\(\s*['"](\/[^'"]*)['"]\s*\)/.exec(signin);
    expect(after, 'Signin.tsx no longer navigates anywhere after success').not.toBeNull();
    expect(registeredRoutes()).toContain(after?.[1]);
  });
});
