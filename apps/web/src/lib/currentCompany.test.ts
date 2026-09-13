/**
 * The one place the selected company id lives. Every PostgREST request goes
 * through the custom fetch in integrations/supabase/client.ts, which reads
 * this module directly, so a bug here is silent everywhere: a query would
 * just come back RLS-empty rather than throw.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('currentCompany', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.resetModules();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it('is null with nothing selected and nothing persisted', async () => {
    const { getCurrentCompanyId } = await import('./currentCompany');
    expect(getCurrentCompanyId()).toBeNull();
  });

  it('returns what was set, without a reload', async () => {
    const { getCurrentCompanyId, setCurrentCompanyId } = await import('./currentCompany');
    setCurrentCompanyId('company-1');
    expect(getCurrentCompanyId()).toBe('company-1');
  });

  it('persists across a reload', async () => {
    // "Reload" simulated by resetting the module registry, so the module's
    // top-level `let current = ...` re-runs from a clean slate and has to
    // read localStorage again rather than keep the in-memory value.
    const first = await import('./currentCompany');
    first.setCurrentCompanyId('company-1');

    vi.resetModules();
    const second = await import('./currentCompany');
    expect(second.getCurrentCompanyId()).toBe('company-1');
  });

  it('clearCurrentCompanyId removes it, including across a reload', async () => {
    const first = await import('./currentCompany');
    first.setCurrentCompanyId('company-1');
    first.clearCurrentCompanyId();
    expect(first.getCurrentCompanyId()).toBeNull();

    vi.resetModules();
    const second = await import('./currentCompany');
    expect(second.getCurrentCompanyId()).toBeNull();
  });

  it('does not throw when localStorage is unavailable', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'localStorage');
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      get() {
        throw new DOMException('blocked', 'SecurityError');
      },
    });

    try {
      vi.resetModules();
      // The failure this guards: private browsing, or a browser configured
      // to block site data, both throw on ANY access to window.localStorage,
      // including the module-load-time read. A selection still has to work
      // for the rest of the tab's life even though it cannot survive a reload.
      await expect(import('./currentCompany')).resolves.toBeDefined();
      const mod = await import('./currentCompany');
      expect(mod.getCurrentCompanyId()).toBeNull();
      expect(() => mod.setCurrentCompanyId('company-1')).not.toThrow();
      expect(mod.getCurrentCompanyId()).toBe('company-1');
      expect(() => mod.clearCurrentCompanyId()).not.toThrow();
    } finally {
      if (original) Object.defineProperty(window, 'localStorage', original);
    }
  });
});

describe('resolveCurrentCompany', () => {
  const companyA = { company_id: 'a', company_name: 'Pennine Bakehouse Ltd', is_current: false };
  const companyB = { company_id: 'b', company_name: 'Calder Valley Farm Shop', is_current: false };

  it('keeps a valid persisted choice, even with several companies', async () => {
    const { resolveCurrentCompany } = await import('./currentCompany');
    expect(resolveCurrentCompany([companyA, companyB], 'b')).toEqual(companyB);
  });

  it('auto-selects the only company, with nothing persisted', async () => {
    // Mirrors current_company_id()'s own behaviour: one membership resolves
    // without a header at all, so it resolves here without a stored choice too.
    const { resolveCurrentCompany } = await import('./currentCompany');
    expect(resolveCurrentCompany([companyA], null)).toEqual(companyA);
  });

  it('replaces a persisted choice that is no longer a membership', async () => {
    // Membership was revoked, or this is a different user's stale id on a
    // shared browser. Either way it is not a fault to surface, only a
    // choice that needs remaking.
    const { resolveCurrentCompany } = await import('./currentCompany');
    expect(resolveCurrentCompany([companyA], 'gone')).toEqual(companyA);
  });

  it('needs a choice with several companies and nothing valid persisted', async () => {
    const { resolveCurrentCompany } = await import('./currentCompany');
    expect(resolveCurrentCompany([companyA, companyB], null)).toBeNull();
    expect(resolveCurrentCompany([companyA, companyB], 'gone')).toBeNull();
  });

  it('resolves to null with no companies at all', async () => {
    const { resolveCurrentCompany } = await import('./currentCompany');
    expect(resolveCurrentCompany([], null)).toBeNull();
    expect(resolveCurrentCompany([], 'anything')).toBeNull();
  });
});
