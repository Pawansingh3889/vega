import { useMemo, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/hooks/useAuth';
import { useCompany } from '@/contexts/CompanyContext';
import { Loader2, Receipt } from 'lucide-react';
import { required } from '@/integrations/supabase/client';

// The API service's origin. See scripts/deploy-api.sh, which prints this same
// value, and the connect-src entries in index.html and public/_headers: a
// browser refuses a call the CSP does not name, and it does so without any
// error the page can see.
const API_URL = required('VITE_API_URL', import.meta.env.VITE_API_URL);

interface VatBoxes {
  box_1_vat_due_sales: string;
  box_2_vat_due_acquisitions: string;
  box_3_total_vat_due: string;
  box_4_vat_reclaimed: string;
  box_5_net_vat: string;
  box_6_total_sales_ex_vat: string;
  box_7_total_purchases_ex_vat: string;
  box_8_goods_to_eu: string;
  box_9_goods_from_eu: string;
  line_count: number;
}

// The HMRC box headings, so the screen reads like the return an accountant
// files. Numbers arrive as strings from the API on purpose: a VAT figure
// through a JavaScript float is a rounding bug waiting for a quarter end, so
// they are displayed as text and never parsed.
const BOXES: Array<{ key: keyof Omit<VatBoxes, 'line_count'>; label: string }> = [
  { key: 'box_1_vat_due_sales', label: 'VAT due on sales and other outputs' },
  { key: 'box_2_vat_due_acquisitions', label: 'VAT due on acquisitions from other EC Member States' },
  { key: 'box_3_total_vat_due', label: 'Total VAT due (boxes 1 and 2)' },
  { key: 'box_4_vat_reclaimed', label: 'VAT reclaimed on purchases and other inputs' },
  { key: 'box_5_net_vat', label: 'Net VAT to be reclaimed from or paid to HMRC (boxes 3 and 4)' },
  { key: 'box_6_total_sales_ex_vat', label: 'Total value of sales and other outputs excluding VAT' },
  { key: 'box_7_total_purchases_ex_vat', label: 'Total value of purchases and other inputs excluding VAT' },
  { key: 'box_8_goods_to_eu', label: 'Dispatches of goods from Northern Ireland to the EU, excluding VAT' },
  { key: 'box_9_goods_from_eu', label: 'Acquisitions of goods from the EU to Northern Ireland, excluding VAT' },
];

// Default to the current VAT quarter to date. A preview of a half-open
// quarter is the useful default for a screen whose inputs are editable;
// the filing itself is a Phase 4 concern and will want closed periods.
function currentQuarterStart(now = new Date()): string {
  const quarterMonth = Math.floor(now.getUTCMonth() / 3) * 3;
  return new Date(Date.UTC(now.getUTCFullYear(), quarterMonth, 1)).toISOString().slice(0, 10);
}

function today(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

const getErrorMessage = (body: unknown): string => {
  if (
    body &&
    typeof body === 'object' &&
    'error' in body &&
    body.error &&
    typeof body.error === 'object' &&
    'message' in body.error &&
    typeof body.error.message === 'string'
  ) {
    return body.error.message;
  }
  return 'The API returned an error it did not describe.';
};

export default function VatPreview() {
  const { user, session, loading } = useAuth();
  // The company itself, and switching it, is shared with every other page
  // (#22): choosing here is the same choice Dashboard and HmrcStatus see, not
  // a preference local to this form. Before this, three pages resolved "which
  // company" three separate, disagreeing ways.
  const { companies, current, loading: companiesLoading, error: companiesError, select } =
    useCompany();
  const [periodStart, setPeriodStart] = useState<string>(currentQuarterStart);
  const [periodEnd, setPeriodEnd] = useState<string>(today);
  const [boxes, setBoxes] = useState<VatBoxes | null>(null);
  const [failure, setFailure] = useState<{ status: number; message: string } | null>(null);
  const [isFetching, setIsFetching] = useState(false);

  // Period inputs are editable, so both dates must be present and ordered
  // before a request is worth making.
  const periodIsValid = useMemo(
    () => Boolean(periodStart && periodEnd && periodStart <= periodEnd),
    [periodStart, periodEnd],
  );

  if (loading || companiesLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-subtle">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/signin" replace />;
  }

  const fetchPreview = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (current === null || !periodIsValid) return;
    setIsFetching(true);
    setFailure(null);
    setBoxes(null);
    try {
      const response = await fetch(
        `${API_URL}/api/v1/vat/preview?period_start=${periodStart}&period_end=${periodEnd}`,
        {
          headers: {
            Authorization: `Bearer ${session?.access_token ?? ''}`,
            'X-Vega-Company': current.company_id,
          },
        },
      );
      const body: unknown = await response.json().catch(() => null);
      if (!response.ok) {
        setFailure({ status: response.status, message: getErrorMessage(body) });
        return;
      }
      setBoxes((body as { data: VatBoxes }).data);
    } catch (err) {
      // fetch throws a TypeError for anything below HTTP: an unreachable
      // origin, a CSP the browser refused, a CORS refusal. The page cannot
      // tell which, and must not pretend otherwise to the user.
      //
      // It CAN tell the console, which a bare `catch {}` here did not: the
      // browser refuses a CSP-blocked connection before fetch() gets an event
      // describing why, so with nothing logged the only trace was this
      // generic message, and finding the actual cause (two independent CSP
      // bugs, see #143) meant reading source rather than reading a log.
      console.error('[VatPreview] fetch failed:', err);
      setFailure({
        status: 0,
        message:
          'Could not reach the API at all. Check the network tab: this is usually an unreachable origin, a CSP connect-src gap, or a CORS refusal.',
      });
    } finally {
      setIsFetching(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-subtle p-4">
      <div className="w-full max-w-2xl">
        <Card className="shadow-elevated">
          <CardHeader className="text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-primary/10 flex items-center justify-center">
              <Receipt className="h-8 w-8 text-primary" />
            </div>
            <CardTitle className="text-2xl">VAT Return Preview</CardTitle>
            <CardDescription>
              Boxes 1 to 9, derived from treatment codes over a period. No box is
              ever typed. Figures are derived server side; this screen files
              nothing.
            </CardDescription>
          </CardHeader>

          <CardContent>
            {companiesError && (
              <p className="text-sm text-destructive mb-4">
                Could not load your companies: {companiesError}
              </p>
            )}

            <form onSubmit={fetchPreview} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="company">Company</Label>
                {companies.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    {companiesError ? 'Company list unavailable.' : 'No company membership found for this account.'}
                  </p>
                ) : (
                  <select
                    id="company"
                    className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                    value={current?.company_id ?? ''}
                    onChange={(e) => select(e.target.value)}
                  >
                    {/* current is null with >1 company and none chosen yet
                        (#22's "say so, do not show empty" case). A disabled
                        placeholder is the honest state of the control:
                        nothing is selected because nothing has been chosen. */}
                    {current === null && (
                      <option value="" disabled>
                        Choose a company
                      </option>
                    )}
                    {companies.map((c) => (
                      <option key={c.company_id} value={c.company_id}>
                        {c.company_name}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="period-start">Period start</Label>
                  <Input
                    id="period-start"
                    type="date"
                    value={periodStart}
                    onChange={(e) => setPeriodStart(e.target.value)}
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="period-end">Period end</Label>
                  <Input
                    id="period-end"
                    type="date"
                    value={periodEnd}
                    onChange={(e) => setPeriodEnd(e.target.value)}
                    required
                  />
                </div>
              </div>

              <Button type="submit" className="w-full btn-gradient" disabled={isFetching || current === null || !periodIsValid}>
                {isFetching ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Deriving figures...
                  </>
                ) : (
                  'Show Return'
                )}
              </Button>
            </form>

            {failure && (
              <div className="mt-6 p-4 rounded-md border border-destructive/30 bg-destructive/5 space-y-1">
                {failure.status === 401 && (
                  <p className="text-sm font-medium text-destructive">Session expired (401).</p>
                )}
                {failure.status === 409 && (
                  <p className="text-sm font-medium text-destructive">No company selected (409).</p>
                )}
                {failure.status === 422 && (
                  <p className="text-sm font-medium text-destructive">The return could not be derived (422).</p>
                )}
                {failure.status === 0 && (
                  <p className="text-sm font-medium text-destructive">Unreachable.</p>
                )}
                <p className="text-sm text-muted-foreground">{failure.message}</p>
                {failure.status === 401 && (
                  <p className="text-sm">
                    <a href="/signin" className="text-primary underline">Sign in again</a> and come back to this page.
                  </p>
                )}
              </div>
            )}

            {boxes && (
              <div className="mt-6 space-y-3">
                {boxes.line_count === 0 && (
                  <p className="text-sm text-amber-600">
                    No invoice lines at all in this period. A nil return and a
                    period with no data are different things; this is the
                    second one.
                  </p>
                )}
                <dl className="divide-y divide-border">
                  {BOXES.map(({ key, label }, index) => (
                    <div key={key} className="flex items-baseline justify-between gap-4 py-2">
                      <dt className="text-sm text-muted-foreground">
                        <span className="font-medium text-foreground mr-2">Box {index + 1}</span>
                        {label}
                      </dt>
                      <dd className="font-mono text-sm whitespace-nowrap">£{boxes[key]}</dd>
                    </div>
                  ))}
                </dl>
                <p className="text-xs text-muted-foreground">
                  {boxes.line_count} line{boxes.line_count === 1 ? '' : 's'} produced these figures.
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
