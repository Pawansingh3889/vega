/**
 * Two real bugs, proven against the actual index.html, not a hand-built
 * fixture. Both were silent because their trigger condition (a local
 * Supabase URL) has never been true in this project's normal dev setup, so a
 * hand-built fixture that only exercised the "obviously fine" shape would
 * have missed exactly what broke.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { devOrigins, widenConnectSrc } from './devCsp';

const REAL_INDEX_HTML = readFileSync(
  resolve(dirname(fileURLToPath(import.meta.url)), '../../index.html'),
  'utf8',
);

describe('widenConnectSrc against the real index.html', () => {
  it('finds and widens the actual CSP meta tag, not the comment above it', () => {
    // The comment above the tag says "connect-src" twice in prose, which is
    // exactly what broke the unanchored version of this.
    expect(REAL_INDEX_HTML).toMatch(/connect-src/);

    const widened = widenConnectSrc(REAL_INDEX_HTML, ['http://localhost:8010']);

    const metaTag = /<meta http-equiv="Content-Security-Policy"[^>]*>/.exec(widened)?.[0];
    expect(metaTag, 'no CSP meta tag found after widening').toBeDefined();
    expect(metaTag).toContain('http://localhost:8010');
  });

  it('leaves the comment above the tag untouched', () => {
    const commentBefore = /<!--[\s\S]*?-->/.exec(REAL_INDEX_HTML)?.[0];
    const widened = widenConnectSrc(REAL_INDEX_HTML, ['http://localhost:8010']);
    const commentAfter = /<!--[\s\S]*?-->/.exec(widened)?.[0];
    expect(commentAfter).toBe(commentBefore);
  });

  it('does not touch the rest of the policy', () => {
    const widened = widenConnectSrc(REAL_INDEX_HTML, ['http://localhost:8010']);
    // script-src, style-src etc. sit either side of connect-src in the same
    // attribute. An over-broad match would corrupt them too.
    expect(widened).toContain("script-src 'self' 'unsafe-inline'");
    expect(widened).toContain("frame-ancestors 'none'");
  });

  it('is a no-op with nothing to add', () => {
    expect(widenConnectSrc(REAL_INDEX_HTML, [])).toBe(REAL_INDEX_HTML);
  });

  it('appends more than one origin correctly', () => {
    const widened = widenConnectSrc(REAL_INDEX_HTML, ['http://a.test', 'ws://a.test']);
    const metaTag = /<meta http-equiv="Content-Security-Policy"[^>]*>/.exec(widened)?.[0] ?? '';
    expect(metaTag).toContain('http://a.test ws://a.test');
  });
});

describe('widenConnectSrc against the exact shape that broke it', () => {
  it('does not let a comment above the tag consume the match', () => {
    // The minimum reproduction: any HTML comment mentioning "connect-src"
    // before the real tag. An unanchored /connect-src[^;"]*/  matches the
    // comment's occurrence first and, because [^;"] matches newlines, keeps
    // consuming until the next ; or " character, which lands inside the real
    // tag: the widening applies to the wrong span and the tag itself never
    // changes.
    const html =
      '<!-- connect-src is explained here, in prose, before the real tag. -->\n' +
      '<meta http-equiv="Content-Security-Policy" content="default-src \'self\'; connect-src \'self\'" />';

    const widened = widenConnectSrc(html, ['http://localhost:8010']);

    expect(widened).toContain(
      'content="default-src \'self\'; connect-src \'self\' http://localhost:8010"',
    );
    // The comment must survive character for character.
    expect(widened).toContain(
      '<!-- connect-src is explained here, in prose, before the real tag. -->',
    );
  });
});

describe('devOrigins', () => {
  it('widens for a local Supabase URL, over both http and ws', () => {
    expect(devOrigins('http://127.0.0.1:54321', undefined)).toEqual([
      'http://127.0.0.1:54321',
      'ws://127.0.0.1:54321',
    ]);
  });

  it('does not widen for the hosted Supabase project', () => {
    // The normal case in this repo, and the reason both bugs went unnoticed:
    // this condition being false meant the plugin never ran at all.
    expect(devOrigins('https://kscgvfzzzbmqohuuiiab.supabase.co', undefined)).toEqual([]);
  });

  it('widens for a local API URL, taking only its origin', () => {
    expect(devOrigins('', 'http://localhost:8010/api/v1')).toEqual(['http://localhost:8010']);
  });

  it('does not widen for a deployed https API URL', () => {
    expect(devOrigins('', 'https://vega-api.fly.dev')).toEqual([]);
  });

  it('does nothing at all with nothing local configured', () => {
    expect(devOrigins('https://kscgvfzzzbmqohuuiiab.supabase.co', 'https://vega-api.fly.dev')).toEqual(
      [],
    );
  });

  it('does not throw on a malformed API URL', () => {
    expect(() => devOrigins('', 'not a url')).not.toThrow();
    expect(devOrigins('', 'not a url')).toEqual([]);
  });
});
