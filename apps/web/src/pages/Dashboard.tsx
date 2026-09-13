/**
 * Where sign-in lands.
 *
 * Until now it landed nowhere: Signin.tsx did navigate('/dashboard') and no
 * such route existed, so a correct sign-in fell through App.tsx's `path="*"`
 * and rendered "Oops! Page not found". The credentials were right and the app
 * said the page was missing, which reads as the sign-in having failed.
 *
 * This deliberately does NOT wire up components/layout/DashboardLayout and its
 * navigation-sidebar. Those are inherited Rigel scaffolding: ten modules that
 * do not exist in Vega, and a hardcoded "Welcome back, Girish!", which is a
 * stranger's name. Linking to screens that are not built would repeat the bug
 * this page exists to fix, one level down.
 *
 * So it lists what genuinely works and says plainly what does not.
 *
 * This is also home base for the company switcher (#22). Company state
 * itself lives in CompanyContext, shared with every other page, so choosing
 * here is what every page sees, not a local preference this one page has.
 */

import { Link, Navigate } from 'react-router-dom';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { AlertCircle, ArrowRight, Building2, Calculator, Loader2, Shield } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useCompany } from '@/contexts/CompanyContext';

/** The screens that exist and have a working backend behind them. */
const BUILT = [
  {
    to: '/vat',
    icon: Calculator,
    title: 'VAT return preview',
    description: 'Boxes 1 to 9 for a period, derived server side from your invoices.',
  },
  {
    to: '/hmrc/status',
    icon: Shield,
    title: 'HMRC connection',
    description: 'Whether this company can file, and when the 18 month grant expires.',
  },
] as const;

export default function Dashboard() {
  const { user, loading: authLoading } = useAuth();
  const { companies, current, loading: companyLoading, error, needsChoice, select } = useCompany();

  // Before the spinner. A signed-out visitor should reach sign-in rather than
  // wait behind a load that will never start. Same ordering bug as #131.
  if (!authLoading && !user) {
    return <Navigate to="/signin" replace />;
  }

  if (authLoading || companyLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-subtle">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-subtle p-4">
      <div className="w-full max-w-3xl mx-auto space-y-6 py-8">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-3xl font-bold">{current?.company_name ?? 'Vega'}</h1>
            <p className="text-muted-foreground mt-1">
              Signed in as {user?.email ?? 'an unknown account'}
            </p>
          </div>

          {/* Shown whenever there is a choice to make, not only when one is
              still unresolved. A single-company user never sees this: there
              is nothing for them to choose. */}
          {companies.length > 1 && (
            <label className="text-sm">
              <span className="sr-only">Company</span>
              <select
                className="border rounded-md px-3 py-2 text-sm bg-background"
                value={current?.company_id ?? ''}
                onChange={(e) => select(e.target.value)}
              >
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
            </label>
          )}
        </div>

        {error !== null && (
          <div className="p-4 rounded-lg border border-destructive/30 bg-destructive/5 text-destructive text-sm flex gap-3">
            <AlertCircle className="h-5 w-5 flex-shrink-0 mt-0.5" />
            <div>
              <p className="font-medium">Could not load your companies</p>
              <p className="mt-1">{error}</p>
            </div>
          </div>
        )}

        {error === null && companies.length === 0 && (
          <div className="p-4 rounded-lg border bg-muted/30 text-sm">
            {/* Said out loud rather than shown as an empty page. A blank
                dashboard reads as "nothing to do", which is a different and
                more reassuring thing than "we could not tell". */}
            Your account is not linked to a company yet, so there is nothing to
            show. An owner needs to add you to one.
          </div>
        )}

        {needsChoice && (
          <div className="p-4 rounded-lg border border-warning/30 bg-warning/5 text-sm flex gap-3">
            <Building2 className="h-5 w-5 flex-shrink-0 mt-0.5" />
            <div>
              {/* The acceptance criterion #22 exists for: several
                  memberships, none chosen, the UI has to say so rather than
                  showing an empty screen that looks like a bug. */}
              <p className="font-medium">You belong to more than one company</p>
              <p className="mt-1">Choose one above to see its VAT return and HMRC connection.</p>
            </div>
          </div>
        )}

        <div className="grid gap-4 sm:grid-cols-2">
          {BUILT.map(({ to, icon: Icon, title, description }) => (
            <Card key={to} className="shadow-elevated">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Icon className="h-5 w-5" />
                  {title}
                </CardTitle>
                <CardDescription>{description}</CardDescription>
              </CardHeader>
              <CardContent>
                {/* Not disabled while needsChoice: VatPreview and HmrcStatus
                    each say plainly why they cannot show anything without a
                    chosen company (same acceptance criterion, handled where
                    the actual gap is, rather than by blocking the link here
                    and leaving the reason unstated). */}
                <Button asChild variant="secondary" className="w-full">
                  <Link to={to}>
                    Open <ArrowRight className="ml-2 h-4 w-4" />
                  </Link>
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Building2 className="h-5 w-5" />
              Not built yet
            </CardTitle>
            <CardDescription>
              Stock, purchasing, sales and reporting are on the roadmap and have no
              screens. They are listed here rather than shown as menu items that
              lead nowhere.
            </CardDescription>
          </CardHeader>
        </Card>
      </div>
    </div>
  );
}
