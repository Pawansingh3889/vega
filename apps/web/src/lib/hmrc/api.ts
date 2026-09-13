/**
 * Calls to the FastAPI service's HMRC endpoints.
 *
 * Only the endpoints that exist are here. The first version of this file also
 * called /hmrc/connect, /hmrc/disconnect, /hmrc/obligations and /hmrc/submit,
 * none of which the server registers: four of five, so most of the UI built on
 * it failed at runtime while compiling, type-checking and looking finished.
 * They come back one at a time as their routes land, so that a function
 * existing here means the call behind it works.
 */

import { supabase, required } from '@/integrations/supabase/client';

const API_URL = required('VITE_API_URL', import.meta.env.VITE_API_URL);

/**
 * The body of GET /api/v1/hmrc/status.
 *
 * The optional fields are absent when `connected` is false, which is why they
 * are optional rather than nullable: the server sends `{connected: false}` and
 * nothing else, instead of nine nulls.
 */
export interface HmrcStatus {
  connected: boolean;
  environment?: 'sandbox' | 'production';
  scope?: string;
  connected_at?: string;
  access_token_expires_at?: string;
  access_token_needs_refresh?: boolean;
  grant_expires_at?: string;
  reauthorisation_due?: boolean;
  grant_has_expired?: boolean;
}

/** Raised when the service answers, but with a refusal rather than data. */
export class HmrcApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
  ) {
    super(message);
    this.name = 'HmrcApiError';
  }
}

async function authHeaders(companyId: string): Promise<Record<string, string>> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new HmrcApiError('You are not signed in.', 401);
  }
  return {
    Authorization: `Bearer ${session.access_token}`,
    // The server refuses without this rather than guessing a company, so it is
    // not optional here either.
    'X-Vega-Company': companyId,
    'Content-Type': 'application/json',
  };
}

/**
 * Read the service's error envelope, or fall back to the status line.
 *
 * The service answers `{error: {code, message}}` and the message is written to
 * be shown to a person, so it is used rather than replaced with a generic
 * string. A response that is not JSON at all still has to produce something
 * better than "undefined", which is what reading `.error.message` off a null
 * gives you.
 */
async function refusal(response: Response): Promise<HmrcApiError> {
  const body: unknown = await response.json().catch(() => null);
  const error =
    typeof body === 'object' && body !== null && 'error' in body
      ? (body as { error?: { code?: string; message?: string } }).error
      : undefined;
  return new HmrcApiError(
    error?.message ?? `The service answered ${response.status}.`,
    response.status,
    error?.code,
  );
}

/** Whether this company can file, and how long that stays true. */
export async function getHmrcStatus(companyId: string): Promise<HmrcStatus> {
  const response = await fetch(`${API_URL}/api/v1/hmrc/status`, {
    headers: await authHeaders(companyId),
  });
  if (!response.ok) {
    throw await refusal(response);
  }
  const body = (await response.json()) as { data: HmrcStatus };
  return body.data;
}
