/**
 * The sign-in form's Business ID rule against the one the database generates.
 *
 * These drifted apart and nobody noticed: migration 0011 changed the generated
 * prefix from "Rigel-" to "VG-", the form kept demanding "BUS-", and the result
 * was that no company this system creates could sign in. The form refused the
 * value before a request was ever sent, so no log anywhere recorded it.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));

/** The rule the sign-in form applies, read out of the page itself. */
function signinPattern(): RegExp {
  const source = readFileSync(resolve(here, './Signin.tsx'), 'utf8');
  const found = /businessRefNo[\s\S]{0,80}?test\(\s*\/\^?([^/]+)\/\s*\.test|\/(\^VG-[^/]+)\/\.test/.exec(
    source,
  );
  const body = found?.[1] ?? found?.[2];
  if (body === undefined) {
    throw new Error(
      'could not find the Business ID pattern in Signin.tsx. If the validation was ' +
        'rewritten, update this test rather than deleting it: the last time these two ' +
        'drifted, sign-in was impossible for every real company.',
    );
  }
  return new RegExp(body.startsWith('^') ? body : `^${body}`);
}

/** The format generate_business_ref_no() builds, from migration 0011. */
function generatedFormat(): string {
  const migration = readFileSync(
    resolve(here, '../../../../supabase/migrations/0011_fix_company_ref_generator.sql'),
    'utf8',
  );
  const line = /RETURN\s+'VG-'\s*\|\|[^;]+;/.exec(migration);
  if (line === null) {
    throw new Error('generate_business_ref_no no longer returns a VG- reference');
  }
  return line[0];
}

describe('the sign-in form and the database agree on a Business ID', () => {
  it('accepts the reference the seeded demo company actually holds', () => {
    // Read straight out of London on 2026-09-07.
    expect('VG-1001-09-2026').toMatch(signinPattern());
  });

  it('accepts the shape the generator builds', () => {
    // LPAD(counter, 4) then month then year.
    for (const ref of ['VG-0001-01-2026', 'VG-9999-12-2099', 'VG-1001-09-2026']) {
      expect(ref).toMatch(signinPattern());
    }
  });

  it('still refuses the inherited India format', () => {
    // Not nostalgia: accepting both would hide the next drift instead of
    // failing on it.
    expect('BUS-20250827-ABC12').not.toMatch(signinPattern());
  });

  it('refuses obvious rubbish', () => {
    for (const ref of ['', 'VG-', 'VG-1-09-2026', 'vg-1001-09-2026', 'VG-1001-09-26']) {
      expect(ref).not.toMatch(signinPattern());
    }
  });

  it('fails loudly if the migration stops generating VG- references', () => {
    // The pairing is the point. If the generator changes prefix again, this
    // says so here rather than at somebody's sign-in screen.
    expect(generatedFormat()).toContain("'VG-'");
  });
});
