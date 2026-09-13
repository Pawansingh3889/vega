/**
 * The RPC call must stay bound to its client.
 *
 * `const rpc = supabase.rpc; await rpc(...)` detaches the method. supabase-js
 * reads `this.rest` inside it, so the call throws `Cannot read properties of
 * undefined (reading 'rest')` before any request leaves the browser. It was
 * written that way in VatPreview.tsx and copied into Dashboard.tsx, and both
 * pages then reported "not linked to a company" while the database was
 * answering the same query correctly.
 *
 * tsc cannot catch it: the cast to a plain function signature is what discards
 * the `this` requirement, and the cast exists for an unrelated reason (#23).
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it, vi } from 'vitest';

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) return sourceFiles(full);
    return /\.tsx?$/.test(entry) && !/\.test\.tsx?$/.test(entry) ? [full] : [];
  });
}

describe('supabase.rpc is never detached from its client', () => {
  it('no source file assigns supabase.rpc without binding it', () => {
    const offenders: string[] = [];
    for (const file of sourceFiles(SRC)) {
      // Comments stripped first. myCompanies.ts documents the bug by quoting
      // the broken line, and a scanner that reads its own explanation as a
      // violation is a scanner people delete.
      const source = readFileSync(file, 'utf8')
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/^\s*\/\/.*$/gm, '');
      // `supabase.rpc` used as a value rather than called immediately, and not
      // followed by .bind(...) or .call(...).
      for (const m of source.matchAll(/supabase\.rpc(?!\s*[(.])/g)) {
        const after = source.slice(m.index ?? 0, (m.index ?? 0) + 60);
        if (!/\.bind\s*\(|\.call\s*\(|\.apply\s*\(/.test(after)) {
          offenders.push(`${file.replace(SRC, 'src')}: ${after.split('\n')[0].trim()}`);
        }
      }
    }
    expect(
      offenders,
      'these take supabase.rpc as a value without binding it. Called later, ' +
        '`this` is undefined and supabase-js throws on this.rest before any ' +
        'request is made. Use fetchMyCompanies(), or .bind(supabase).',
    ).toEqual([]);
  });
});

describe('fetchMyCompanies', () => {
  it('calls the rpc with its client as `this`', async () => {
    // The regression, asserted directly: a stub that reads `this` the way
    // supabase-js does, and throws if it is missing.
    const client: Record<string, unknown> = { rest: 'present' };
    client.rpc = vi.fn(function (this: unknown, _fn: string) {
      if (this === undefined || (this as { rest?: string }).rest !== 'present') {
        throw new TypeError("Cannot read properties of undefined (reading 'rest')");
      }
      return Promise.resolve({
        data: [{ company_id: 'c1', company_name: 'Pennine Bakehouse Ltd', is_current: true }],
        error: null,
      });
    });

    vi.resetModules();
    vi.doMock('@/integrations/supabase/client', () => ({ supabase: client }));
    const { fetchMyCompanies } = await import('./myCompanies');

    await expect(fetchMyCompanies()).resolves.toEqual([
      { company_id: 'c1', company_name: 'Pennine Bakehouse Ltd', is_current: true },
    ]);
  });

  it('throws when the rpc errors rather than returning an empty list', async () => {
    // An empty list means "you belong to no company". A failed call does not,
    // and reporting the two the same way is what put "not linked to a company"
    // on screen when the real answer was "the call threw".
    const client: Record<string, unknown> = { rest: 'present' };
    client.rpc = vi.fn(() => Promise.resolve({ data: null, error: { message: 'boom' } }));

    vi.resetModules();
    vi.doMock('@/integrations/supabase/client', () => ({ supabase: client }));
    const { fetchMyCompanies } = await import('./myCompanies');

    await expect(fetchMyCompanies()).rejects.toThrow('boom');
  });
});
