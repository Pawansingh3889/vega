/**
 * The postcode client, against a stubbed fetch and the real response shape
 * the server produces once #148 fixed it (a raw dataclass 500d on every
 * successful lookup, and the only tests that existed mocked it away).
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

const { lookupPostcode, PostcodeApiError } = await import('./postcode');
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

const REAL_SHAPED_RESULT = {
  postcode: 'HX76AB',
  count: 1,
  addresses: [
    {
      line_1: 'Flat 2',
      line_2: '14 Mill Road',
      line_3: null,
      line_4: null,
      town_or_city: 'Hebden Bridge',
      county: 'West Yorkshire',
      postcode: 'HX76AB',
      formatted_address: 'Flat 2, 14 Mill Road, Hebden Bridge, HX7 6AB',
    },
  ],
};

describe('lookupPostcode', () => {
  it('unwraps the data envelope, matching the shape the server actually sends', async () => {
    fetchMock.mockResolvedValue(respond(200, { data: REAL_SHAPED_RESULT }));

    await expect(lookupPostcode('HX7 6AB')).resolves.toEqual(REAL_SHAPED_RESULT);
  });

  it('sends the Authorization header, and no X-Vega-Company', async () => {
    // Postcode lookup is not scoped to a company at all
    // (PERMISSIONS = {"postcode.lookup": "authenticated"}), so there is
    // nothing to send, unlike every HMRC call.
    fetchMock.mockResolvedValue(respond(200, { data: REAL_SHAPED_RESULT }));

    await lookupPostcode('HX7 6AB');

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = new Headers(init.headers);
    expect(headers.get('Authorization')).toBe('Bearer test-token');
    expect(headers.has('X-Vega-Company')).toBe(false);
  });

  it('percent-encodes the postcode into the query string', async () => {
    fetchMock.mockResolvedValue(respond(200, { data: REAL_SHAPED_RESULT }));

    await lookupPostcode('HX7 6AB');

    const [url] = fetchMock.mock.calls[0] as [string];
    expect(url).toContain('postcode=HX7%206AB');
  });

  it('surfaces the not_configured message and 503 status for an operator to act on', async () => {
    fetchMock.mockResolvedValue(
      respond(503, {
        error: {
          code: 'not_configured',
          message: 'Postcode lookup is not configured on this deployment: set GETADDRESS_API_KEY.',
        },
      }),
    );

    await expect(lookupPostcode('HX7 6AB')).rejects.toMatchObject({
      status: 503,
      code: 'not_configured',
      message: expect.stringContaining('GETADDRESS_API_KEY'),
    });
  });

  it('surfaces the malformed message distinctly from not_found', async () => {
    fetchMock.mockResolvedValue(
      respond(422, { error: { code: 'malformed', message: 'Postcode format is invalid' } }),
    );
    await expect(lookupPostcode('nonsense')).rejects.toMatchObject({ code: 'malformed' });

    fetchMock.mockResolvedValue(
      respond(422, {
        error: { code: 'not_found', message: 'Postcode does not resolve to any addresses' },
      }),
    );
    await expect(lookupPostcode('XX99 9XX')).rejects.toMatchObject({ code: 'not_found' });
  });

  it('does not say "undefined" when the body is not the error envelope', async () => {
    fetchMock.mockResolvedValue(respond(500, 'gateway exploded'));
    await expect(lookupPostcode('HX7 6AB')).rejects.toThrow('The service answered 500.');
  });

  it('refuses before calling out when there is no session', async () => {
    vi.mocked(supabase.auth.getSession).mockResolvedValueOnce({
      data: { session: null },
    } as Awaited<ReturnType<typeof supabase.auth.getSession>>);

    await expect(lookupPostcode('HX7 6AB')).rejects.toBeInstanceOf(PostcodeApiError);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
