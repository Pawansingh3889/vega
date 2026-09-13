/**
 * The HMRC client, against a stubbed fetch.
 *
 * The first version of this file shipped with no tests and called four
 * endpoints the server does not register, so the tests that matter most here
 * are the ones that pin the request to the shape the service actually accepts:
 * the company header it refuses without, and the error envelope it answers with.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/integrations/supabase/client', () => ({
  required: (_name: string, value: string | undefined) => value ?? 'https://api.test',
  supabase: {
    auth: {
      getSession: vi.fn(async () => ({
        data: { session: { access_token: 'test-token' } },
      })),
    },
  },
}));

const { getHmrcStatus, HmrcApiError } = await import('./api');
const { supabase } = await import('@/integrations/supabase/client');

function respond(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe('getHmrcStatus', () => {
  it('unwraps the data envelope', async () => {
    fetchMock.mockResolvedValue(respond(200, { data: { connected: false } }));

    await expect(getHmrcStatus('company-1')).resolves.toEqual({ connected: false });
  });

  it('sends the company header the server refuses without', async () => {
    // The server answers 422 company_required when this is absent, so omitting
    // it turns every call into a refusal that looks like a server fault.
    fetchMock.mockResolvedValue(respond(200, { data: { connected: false } }));

    await getHmrcStatus('company-42');

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers['X-Vega-Company']).toBe('company-42');
    expect(headers.Authorization).toBe('Bearer test-token');
  });

  it('calls the path the server registers', async () => {
    fetchMock.mockResolvedValue(respond(200, { data: { connected: false } }));

    await getHmrcStatus('company-1');

    const [url] = fetchMock.mock.calls[0] as [string];
    expect(url).toContain('/api/v1/hmrc/status');
  });

  it('surfaces the service message rather than a generic one', async () => {
    // The service writes these to be read by a person. Replacing them with
    // "Failed to fetch HMRC status" throws away the only useful part.
    fetchMock.mockResolvedValue(
      respond(422, {
        error: { code: 'company_required', message: 'Send X-Vega-Company.' },
      }),
    );

    await expect(getHmrcStatus('company-1')).rejects.toThrow('Send X-Vega-Company.');
  });

  it('carries the status and code for the caller to branch on', async () => {
    fetchMock.mockResolvedValue(
      respond(422, { error: { code: 'company_required', message: 'nope' } }),
    );

    await expect(getHmrcStatus('company-1')).rejects.toMatchObject({
      status: 422,
      code: 'company_required',
    });
  });

  it('does not say "undefined" when the body is not the error envelope', async () => {
    // Reading .error.message off a null is how a 500 becomes "undefined" on
    // screen, which tells the reader nothing at all.
    fetchMock.mockResolvedValue(respond(500, 'gateway exploded'));

    await expect(getHmrcStatus('company-1')).rejects.toThrow('The service answered 500.');
  });

  it('refuses before calling out when there is no session', async () => {
    vi.mocked(supabase.auth.getSession).mockResolvedValueOnce({
      data: { session: null },
    } as Awaited<ReturnType<typeof supabase.auth.getSession>>);

    await expect(getHmrcStatus('company-1')).rejects.toBeInstanceOf(HmrcApiError);
    // The important half: no request was made with a missing token.
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
