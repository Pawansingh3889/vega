/**
 * Which company the signed-in user is currently acting as.
 *
 * One value, held in one place, read by the Supabase client on every request
 * and by every page that needs it. Before this there were THREE independent
 * mechanisms answering "what company is this": Dashboard.tsx and
 * VatPreview.tsx each called my_companies() separately and picked is_current
 * themselves, and HmrcStatus.tsx read user.user_metadata.company_id, a
 * different value entirely, baked in at signup and never updated. None of the
 * three agreed with each other, and none of them let a user with more than
 * one company choose. See #22.
 *
 * `current_company_id()` (the Postgres function every RLS policy calls)
 * resolves from the X-Vega-Company request header, and only falls back to
 * auto-selecting when the caller has EXACTLY one membership. So a value held
 * only in React state is not enough: it has to reach every PostgREST request,
 * which is what the custom fetch in integrations/supabase/client.ts reads
 * this module for.
 */

const STORAGE_KEY = 'vega.company.selected';

let current: string | null = null;
try {
  // Read once at module load, synchronously, so the very first request this
  // tab makes (before any React effect has run) already carries the header
  // from a previous session, rather than the RLS deny-by-default answer for
  // one request and the right answer from the second.
  current = localStorage.getItem(STORAGE_KEY);
} catch {
  // Private browsing, or a browser configured to block site data. Falling
  // back to "no persisted choice" is correct: a multi-company user asked once
  // per tab is not a security problem, only a small inconvenience.
  current = null;
}

/** The company id to send as X-Vega-Company, or null if none is selected. */
export function getCurrentCompanyId(): string | null {
  return current;
}

/** Select a company. Persists across a reload, per #22's acceptance. */
export function setCurrentCompanyId(companyId: string): void {
  current = companyId;
  try {
    localStorage.setItem(STORAGE_KEY, companyId);
  } catch {
    // Selection still works for the rest of this tab's life; it just will
    // not survive a reload. Not worth failing the switch over.
  }
}

/** Sign-out clears this. A residual id would otherwise ride along into the
 * NEXT person's session on a shared browser, harmlessly refused by RLS but
 * confusing: their own company list would show nothing as current on first
 * paint until the provider re-validates against their actual memberships. */
export function clearCurrentCompanyId(): void {
  current = null;
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Nothing to clean up if storage was never reachable.
  }
}


import type { MyCompany } from './myCompanies';

/**
 * Which company should be selected, given the fetched list and whatever id
 * was persisted from a previous session.
 *
 * Pure and separate from CompanyProvider's effect so it is directly
 * testable: this is the decision the acceptance criteria in #22 actually
 * describe, and a bug in it is invisible in the UI right up until someone
 * has exactly the membership shape that trips it.
 *
 * Mirrors current_company_id() (the Postgres function every RLS policy
 * calls), which auto-resolves without a header only when the caller has
 * EXACTLY one membership. Selecting that one company here too means a
 * single-company user never sees a switcher and never needs one; the header
 * this produces and the header the server would have inferred anyway agree.
 */
export function resolveCurrentCompany(
  companies: readonly MyCompany[],
  persistedId: string | null,
): MyCompany | null {
  if (persistedId !== null) {
    const persisted = companies.find((c) => c.company_id === persistedId);
    if (persisted !== undefined) return persisted;
  }
  if (companies.length === 1) return companies[0];
  return null;
}
