/**
 * Which company the signed-in user is acting as, shared across every page.
 *
 * This file used to hold a parallel, fake auth system: `signIn()` returned a
 * hardcoded mock company and a fake session token for ANY credentials, and
 * `switchCompany()` logged a message and did nothing. It was wired into
 * App.tsx (mounted on every page) but nothing called `useCompany()` anywhere,
 * so it was live and dangerous rather than merely unused: the first page
 * written against it would have gotten a company that always exists and
 * credentials that always work.
 *
 * Real auth is `hooks/useAuth.tsx`, backed by Supabase Auth and the signin
 * edge function fixed in #140. This file has exactly one job now: given a
 * signed-in user, which of their companies are they acting as, and let them
 * change it. See #22.
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';

import { useAuth } from '@/hooks/useAuth';
import {
  clearCurrentCompanyId,
  getCurrentCompanyId,
  resolveCurrentCompany,
  setCurrentCompanyId,
} from '@/lib/currentCompany';
import { fetchMyCompanies, type MyCompany } from '@/lib/myCompanies';

interface CompanyContextValue {
  /** Every company this user belongs to (or every company, for a developer grant). */
  companies: MyCompany[];
  /** The selected company, or null if none is chosen yet. */
  current: MyCompany | null;
  loading: boolean;
  error: string | null;
  /**
   * More than one company exists and none is selected. The acceptance
   * criterion this exists for: "With several memberships and none chosen,
   * the UI says so rather than showing an empty screen." A page that needs a
   * company checks this and shows a message, rather than rendering as though
   * zero rows is the honest answer to its query.
   */
  needsChoice: boolean;
  select: (companyId: string) => void;
}

const CompanyContext = createContext<CompanyContextValue | undefined>(undefined);

export function useCompany(): CompanyContextValue {
  const context = useContext(CompanyContext);
  if (context === undefined) {
    throw new Error('useCompany must be used within a CompanyProvider');
  }
  return context;
}

export function CompanyProvider({ children }: { children: ReactNode }) {
  const { user, loading: authLoading } = useAuth();
  const [companies, setCompanies] = useState<MyCompany[]>([]);
  const [currentId, setCurrentId] = useState<string | null>(getCurrentCompanyId());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (authLoading) return;

    if (!user) {
      // Signed out. A stale id here would ride along into the next person's
      // session on a shared browser: harmless (RLS refuses a company they do
      // not belong to), but confusing, since their own list would show
      // nothing as current until this provider re-validated it.
      clearCurrentCompanyId();
      setCompanies([]);
      setCurrentId(null);
      setLoading(false);
      setError(null);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    void (async () => {
      try {
        const list = await fetchMyCompanies();
        if (cancelled) return;
        setCompanies(list);

        const resolved = resolveCurrentCompany(list, getCurrentCompanyId());
        if (resolved === null) {
          // Zero companies, or several with no valid stored choice. Either
          // way there is nothing correct to auto-select.
          clearCurrentCompanyId();
        } else {
          // Re-asserting even an already-persisted choice is cheap and
          // covers the one-membership case, where resolveCurrentCompany
          // picked a company that was never actually written to storage yet.
          setCurrentCompanyId(resolved.company_id);
        }
        setCurrentId(resolved?.company_id ?? null);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Could not load your companies.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [user, authLoading]);

  const select = useCallback(
    (companyId: string) => {
      // Refuses silently rather than throwing: a stale switcher rendered
      // against an old companies list (a race during a refetch) should not
      // crash the page over a selection that is about to be replaced anyway.
      if (!companies.some((c) => c.company_id === companyId)) return;
      setCurrentCompanyId(companyId);
      setCurrentId(companyId);
    },
    [companies],
  );

  const current = useMemo(
    () => companies.find((c) => c.company_id === currentId) ?? null,
    [companies, currentId],
  );

  const needsChoice = !loading && error === null && companies.length > 1 && current === null;

  const value: CompanyContextValue = {
    companies,
    current,
    loading,
    error,
    needsChoice,
    select,
  };

  return <CompanyContext.Provider value={value}>{children}</CompanyContext.Provider>;
}
