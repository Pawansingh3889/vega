/**
 * Calls to the FastAPI service's postcode lookup endpoint.
 *
 * Unlike the HMRC calls in lib/hmrc/api.ts, this one carries no
 * X-Vega-Company header. Postcode lookup is not scoped to a company at all
 * (modules/postcode/__init__.py: PERMISSIONS = {"postcode.lookup":
 * "authenticated"}, not tied to membership of anything), so there is nothing
 * to send.
 */

import { supabase, required } from '@/integrations/supabase/client';

const API_URL = required('VITE_API_URL', import.meta.env.VITE_API_URL);

/** One candidate address, as the server returns it. */
export interface PostcodeAddress {
  line_1: string | null;
  line_2: string | null;
  line_3: string | null;
  line_4: string | null;
  town_or_city: string | null;
  county: string | null;
  postcode: string;
  formatted_address: string;
}

export interface PostcodeLookupResult {
  postcode: string;
  addresses: PostcodeAddress[];
  count: number;
}

/** Raised when the service answers, but with a refusal rather than data. */
export class PostcodeApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
  ) {
    super(message);
    this.name = 'PostcodeApiError';
  }
}

async function authHeaders(): Promise<Record<string, string>> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new PostcodeApiError('You are not signed in.', 401);
  }
  return { Authorization: `Bearer ${session.access_token}` };
}

/**
 * Read the service's error envelope, or fall back to the status line.
 *
 * The service writes these messages to be read by a person: `not_configured`
 * says the deployment has no key and manual entry still works; `malformed`
 * and `not_found` describe the postcode itself. Replacing any of them with a
 * generic string throws away the only part worth showing.
 */
async function refusal(response: Response): Promise<PostcodeApiError> {
  const body: unknown = await response.json().catch(() => null);
  const error =
    typeof body === 'object' && body !== null && 'error' in body
      ? (body as { error?: { code?: string; message?: string } }).error
      : undefined;
  return new PostcodeApiError(
    error?.message ?? `The service answered ${response.status}.`,
    response.status,
    error?.code,
  );
}

/**
 * Addresses for a UK postcode.
 *
 * Refuses rather than returning an empty list on any failure: `not_found` and
 * `not_configured` and `malformed` are three different, distinguishable
 * situations (SECURITY.md N6 in spirit, applied to a screen rather than a
 * ledger), and a caller that wants "no addresses" and "the service is down"
 * to read the same way can still catch and coalesce this itself.
 */
export async function lookupPostcode(postcode: string): Promise<PostcodeLookupResult> {
  const response = await fetch(
    `${API_URL}/api/v1/postcode/lookup?postcode=${encodeURIComponent(postcode)}`,
    { headers: await authHeaders() },
  );
  if (!response.ok) {
    throw await refusal(response);
  }
  const body = (await response.json()) as { data: PostcodeLookupResult };
  return body.data;
}
