
describe('withCompanyHeader', () => {
  it('adds the header to a plain object', async () => {
    const { withCompanyHeader } = await import('./client');
    const result = withCompanyHeader({ headers: { apikey: 'abc' } }, 'company-1');
    const headers = new Headers(result.headers);
    expect(headers.get('apikey')).toBe('abc');
    expect(headers.get('X-Vega-Company')).toBe('company-1');
  });

  it('preserves every entry of a real Headers instance, not just the new one', async () => {
    // The exact regression. supabase-js constructs a genuine Headers instance
    // for every request, carrying apikey and Authorization. A plain object
    // spread over one, `{ ...headersInstance }`, silently produces `{}`:
    // Headers stores entries behind getters and an iterator, not as own
    // enumerable properties, so the spread copies nothing. This shipped to
    // main and broke every signed-in query with "No API key found in
    // request" the instant a company was ever selected.
    const { withCompanyHeader } = await import('./client');
    const original = new Headers({
      apikey: 'the-anon-key',
      Authorization: 'Bearer a-real-token',
      'Content-Type': 'application/json',
    });

    const result = withCompanyHeader({ headers: original }, 'company-1');

    const headers = new Headers(result.headers);
    expect(headers.get('apikey')).toBe('the-anon-key');
    expect(headers.get('authorization')).toBe('Bearer a-real-token');
    expect(headers.get('content-type')).toBe('application/json');
    expect(headers.get('X-Vega-Company')).toBe('company-1');
  });

  it('preserves an array-of-pairs HeadersInit too', async () => {
    // The third valid shape fetch() accepts. Not hypothetical: this is what
    // some fetch polyfills and older call sites construct.
    const { withCompanyHeader } = await import('./client');
    const result = withCompanyHeader(
      { headers: [['apikey', 'abc'], ['x-client-info', 'supabase-js/2.45.0']] },
      'company-1',
    );
    const headers = new Headers(result.headers);
    expect(headers.get('apikey')).toBe('abc');
    expect(headers.get('x-client-info')).toBe('supabase-js/2.45.0');
    expect(headers.get('X-Vega-Company')).toBe('company-1');
  });

  it('works with no init at all', async () => {
    const { withCompanyHeader } = await import('./client');
    const result = withCompanyHeader(undefined, 'company-1');
    expect(new Headers(result.headers).get('X-Vega-Company')).toBe('company-1');
  });

  it('overwrites rather than duplicates an existing X-Vega-Company value', async () => {
    const { withCompanyHeader } = await import('./client');
    const result = withCompanyHeader(
      { headers: new Headers({ 'X-Vega-Company': 'stale' }) },
      'company-2',
    );
    expect(new Headers(result.headers).get('X-Vega-Company')).toBe('company-2');
  });

  it('carries the rest of init through unchanged', async () => {
    const { withCompanyHeader } = await import('./client');
    const result = withCompanyHeader({ method: 'POST', body: 'x' }, 'company-1');
    expect(result.method).toBe('POST');
    expect(result.body).toBe('x');
  });
});

/**
 * The custom fetch that attaches X-Vega-Company to every PostgREST request.
 *
 * This is the mechanism #22's second acceptance criterion actually depends
 * on: "sent on every request". Nothing renders this, so nothing else would
 * catch a regression here except a query silently coming back RLS-empty in
 * production, weeks later, for a user with more than one company.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const originalFetch = global.fetch;

beforeEach(() => {
  localStorage.clear();
  vi.resetModules();
  // required() throws without these, and the real values live in a .env file
  // that CI does not have. A stub origin is enough: nothing in these tests
  // reaches the network for real, only asserts on what would have been sent.
  vi.stubEnv('VITE_SUPABASE_URL', 'https://stub.supabase.co');
  vi.stubEnv('VITE_SUPABASE_PUBLISHABLE_KEY', 'stub-key');
  vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 200 })));
});

afterEach(() => {
  localStorage.clear();
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  global.fetch = originalFetch;
});

describe("the supabase client's fetch", () => {
  it('does not attach X-Vega-Company with nothing selected', async () => {
    const { supabase } = await import('./client');
    const fetchSpy = global.fetch as ReturnType<typeof vi.fn>;

    await supabase.from('companies').select('id');

    const [, init] = fetchSpy.mock.calls[0] as [string, RequestInit];
    const headers = new Headers(init.headers);
    expect(headers.has('X-Vega-Company')).toBe(false);
  });

  it('attaches the selected company to every request, without being told to per call', async () => {
    const { setCurrentCompanyId } = await import('@/lib/currentCompany');
    setCurrentCompanyId('company-1');

    const { supabase } = await import('./client');
    const { fetchMyCompanies } = await import('@/lib/myCompanies');
    const fetchSpy = global.fetch as ReturnType<typeof vi.fn>;

    // Two unrelated calls, through two different call shapes (.from() and the
    // rpc() the app actually uses via fetchMyCompanies()). Neither names the
    // header itself: nobody writing a new query anywhere in the app has to
    // remember to pass it, which is the entire point of doing this in the
    // client's own fetch rather than per call site, the way the three pages
    // used to do it independently.
    await supabase.from('companies').select('id');
    await fetchMyCompanies().catch(() => {
      // The stubbed fetch answers "{}", not a real my_companies() shape, so
      // fetchMyCompanies() throws parsing it. Only the outgoing request
      // matters here, not a well-formed response.
    });

    for (const call of fetchSpy.mock.calls) {
      const [, init] = call as [string, RequestInit];
      const headers = new Headers(init.headers);
      expect(headers.get('X-Vega-Company')).toBe('company-1');
    }
  });

  it('picks up a change without recreating the client', async () => {
    // The switcher calls setCurrentCompanyId and expects the VERY NEXT
    // request, anywhere in the app, to carry the new value. If the client
    // captured the id once at construction this would still show the old one.
    const currentCompany = await import('@/lib/currentCompany');
    currentCompany.setCurrentCompanyId('company-1');

    const { supabase } = await import('./client');
    const fetchSpy = global.fetch as ReturnType<typeof vi.fn>;

    await supabase.from('companies').select('id');
    currentCompany.setCurrentCompanyId('company-2');
    await supabase.from('companies').select('id');

    const headerOf = (call: unknown) => {
      const [, init] = call as [string, RequestInit];
      return new Headers(init.headers).get('X-Vega-Company');
    };
    expect(headerOf(fetchSpy.mock.calls[0])).toBe('company-1');
    expect(headerOf(fetchSpy.mock.calls[1])).toBe('company-2');
  });
});
