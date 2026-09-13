import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';

import { getCurrentCompanyId } from '@/lib/currentCompany';

// No fallback, deliberately.
//
// This file previously defaulted to a hardcoded URL and anon key when the
// environment was missing. Those literals pointed at project
// the upstream fork's project, not Vega's. Since an anon key
// is public by design and Rigel's still works, a missing or mistyped variable
// did not fail: the app silently connected to another product's database and
// looked entirely healthy while reading someone else's rows.
//
// Failing at startup with a message naming the missing variable is the only
// honest option (SECURITY.md N6: a control that cannot report its own failure
// is not a control).
export function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(
      `${name} is not set. Copy .env.example to .env and fill in the Vega project's ` +
        `values. There is no default: the previous one pointed at a different product's database.`,
    );
  }
  return value;
}

export const SUPABASE_URL = required(
  'VITE_SUPABASE_URL',
  import.meta.env.VITE_SUPABASE_URL,
);
const SUPABASE_PUBLISHABLE_KEY = required(
  'VITE_SUPABASE_PUBLISHABLE_KEY',
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
);

// Import the supabase client like this:
// import { supabase } from "@/integrations/supabase/client";

/**
 * Attach X-Vega-Company to a request's headers, correctly, regardless of what
 * shape `init.headers` arrives in.
 *
 * Extracted and exported so it is testable with a caller-controlled input
 * shape, rather than trusting whatever supabase-js happens to construct.
 * That distinction is not academic: a previous version of this used
 * `{ ...init?.headers, 'X-Vega-Company': companyId }`, which is correct when
 * `init.headers` is a plain object and silently produces `{}` when it is a
 * real Headers instance, because Headers stores its entries behind getters
 * and an iterator, not as the object's own enumerable properties. A test that
 * only ever exercised whatever shape the test environment's fetch mock
 * happened to receive passed regardless of which case ran, and a real
 * browser, where supabase-js constructs a genuine Headers instance carrying
 * apikey and Authorization, dropped both of them. Every signed-in query
 * failed with "No API key found in request" the instant a company was ever
 * selected, which in practice is almost immediately.
 *
 * `new Headers(...)` is the one interface that correctly normalises all
 * three valid HeadersInit shapes, a Headers instance, an array of pairs, or a
 * plain object, without this loss, which is why the fix reaches for it
 * explicitly rather than trusting a spread to do the same thing.
 */
export function withCompanyHeader(init: RequestInit | undefined, companyId: string): RequestInit {
  const headers = new Headers(init?.headers);
  headers.set('X-Vega-Company', companyId);
  return { ...init, headers };
}

export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: localStorage, // TODO: Migrate to httpOnly cookies for enhanced security
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
  global: {
    // X-Vega-Company, on every PostgREST request this client makes.
    // current_company_id() (every RLS policy's source of truth) reads this
    // header, and only auto-resolves without it when the caller has exactly
    // one membership. A user with more than one company gets NULL back from
    // every query and sees an empty screen, correctly deny-by-default and
    // otherwise indistinguishable from "you have no data". A custom fetch is
    // the supported way to attach a header that changes at runtime: the
    // header options passed to createClient() are fixed at construction, and
    // recreating the client on every company switch would drop its
    // in-memory auth state. See #22 and lib/currentCompany.ts.
    fetch: (input, init) => {
      const companyId = getCurrentCompanyId();
      if (companyId === null) return fetch(input, init);
      return fetch(input, withCompanyHeader(init, companyId));
    },
  },
});
