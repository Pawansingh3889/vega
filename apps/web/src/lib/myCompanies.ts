/**
 * The companies the signed-in user belongs to.
 *
 * One place, because the detached-call bug below was written twice: once in
 * VatPreview.tsx and once, copied from it, in Dashboard.tsx. Both pages then
 * failed to resolve a company, silently, while the database returned the right
 * answer to the same query.
 */

import { supabase } from '@/integrations/supabase/client';

export interface MyCompany {
  company_id: string;
  company_name: string;
  is_current: boolean;
}

/**
 * Call the my_companies() RPC.
 *
 * `.bind(supabase)` is load-bearing. Both call sites did:
 *
 *     const rpc = supabase.rpc as unknown as (...) => ...;
 *     await rpc('my_companies');
 *
 * which detaches the method from its object. supabase-js reads `this.rest`
 * inside rpc(), so the call threw `Cannot read properties of undefined
 * (reading 'rest')` before any request was made. Neither page had a try/catch
 * around it, so the rejection escaped, no state was ever set, and the page
 * rendered its empty state: "not linked to a company". The database was
 * returning the company correctly the whole time.
 *
 * The cast is still needed for a different reason: types.ts is the fork's stale
 * generated client and predates my_companies(), so rpc() cannot name it. See
 * #23. Casting the BOUND function keeps the type fix and the binding together,
 * which is what makes it hard to reintroduce one without the other.
 */
export async function fetchMyCompanies(): Promise<MyCompany[]> {
  const rpc = supabase.rpc.bind(supabase) as unknown as (
    fn: 'my_companies',
  ) => PromiseLike<{ data: MyCompany[] | null; error: { message: string } | null }>;

  const { data, error } = await rpc('my_companies');
  if (error !== null) {
    // Thrown rather than returned empty. An empty list means "you belong to no
    // company", which is a real and different answer from "we could not ask".
    throw new Error(error.message);
  }
  return data ?? [];
}
