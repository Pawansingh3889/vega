import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { AlertCircle, CheckCircle2, Loader2, Shield, Calendar, Clock, ExternalLink, ArrowLeft } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useBusinessAuth } from '@/hooks/useBusinessAuth';
import { useCompany } from '@/contexts/CompanyContext';
import { getHmrcStatus, type HmrcStatus } from '@/lib/hmrc/api';

export default function HmrcStatusPage() {
  const { user, loading: authLoading } = useAuth();
  // isOwnerOrAdmin() checks membership of the profile's ONE default company
  // (useAuth().company, resolved from profiles.company_id at sign-in), not
  // the company selected below. For a user whose profile default and
  // selected company are the same, which is everyone today, this is correct.
  // For a genuine multi-company user who switches away from their default,
  // the permission check would still be answering for the WRONG company.
  // Fixing that means teaching useBusinessAuth to check company_users against
  // the selected company rather than the profile's fixed one, a real change
  // to a hook other (currently unwired) screens also depend on, not a
  // mechanical rename. Flagged rather than silently left, or silently
  // widened past what #22 asked for. See the company switcher issue's
  // follow-up notes.
  const { isOwnerOrAdmin, loading: permLoading } = useBusinessAuth();
  const { current, loading: companyLoading, needsChoice } = useCompany();
  const [status, setStatus] = useState<HmrcStatus | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const companyId = current?.company_id;

  useEffect(() => {
    // Clearing the flag on every path out, not only on the path that fetches.
    //
    // The first version returned early here and cleared it only in the fetch's
    // `finally`, so isLoading stayed true forever for anyone who did not reach
    // the fetch. The loading check below sits ABOVE the redirect to /signin, so
    // the commonest visitor of all, someone not signed in, got an endless
    // spinner instead of the sign-in page.
    if (!user) {
      setIsLoading(false);
      return;
    }
    if (companyLoading) return;
    if (!companyId) {
      // Said out loud, and distinguishing the two real causes (#22): no
      // company at all, or several with none chosen yet. A blank card would
      // read as "not connected" either way, which is a different and more
      // reassuring thing than either truth. SECURITY.md N5.
      setError(
        needsChoice
          ? 'Choose a company on the dashboard to see its HMRC connection.'
          : 'Your account is not linked to a company, so there is no HMRC connection to show.',
      );
      setIsLoading(false);
      return;
    }

    let cancelled = false;
    const fetchStatus = async () => {
      try {
        const data = await getHmrcStatus(companyId);
        // The page can unmount mid-request. Setting state afterwards warns in
        // development and, worse, can show a stale company's status.
        if (!cancelled) setStatus(data);
      } catch (err) {
        if (cancelled) return;
        // The service writes its refusals to be read by a person, so the
        // message is shown rather than replaced with a generic one.
        setError(
          err instanceof Error ? err.message : 'Could not load the HMRC connection status.',
        );
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    };

    fetchStatus();
    return () => {
      cancelled = true;
    };
  }, [user, companyId, companyLoading, needsChoice]);

  // Before the spinner, deliberately. A signed-out visitor should reach the
  // sign-in page, not wait behind a load that will never complete.
  if (!authLoading && !user) {
    return <Navigate to="/signin" replace />;
  }

  if (authLoading || permLoading || companyLoading || isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-subtle">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  if (!isOwnerOrAdmin()) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-subtle p-4">
        <Card className="w-full max-w-md">
          <CardHeader className="text-center">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-destructive/10 flex items-center justify-center">
              <AlertCircle className="h-8 w-8 text-destructive" />
            </div>
            <CardTitle className="text-xl">Access Denied</CardTitle>
            <CardDescription>
              Only company owners and administrators can view HMRC connection status.
            </CardDescription>
          </CardHeader>
        </Card>
      </div>
    );
  }

  const isConnected = status?.connected ?? false;
  const isReauthDue = status?.reauthorisation_due ?? false;
  const isGrantExpired = status?.grant_has_expired ?? false;
  const needsRefresh = status?.access_token_needs_refresh ?? false;

  return (
    <div className="min-h-screen bg-gradient-subtle p-4">
      <div className="w-full max-w-3xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Button variant="ghost" size="icon" onClick={() => window.history.back()}>
              <ArrowLeft className="h-5 w-5" />
            </Button>
            <div>
              <h1 className="text-3xl font-bold">HMRC Connection Status</h1>
              <p className="text-muted-foreground mt-1">
                Detailed view of your MTD VAT connection and grant expiry timeline.
              </p>
            </div>
          </div>
        </div>

        {/* Main Status Card */}
        <Card className="shadow-elevated">
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <Shield className="h-5 w-5" />
                  Connection Overview
                </CardTitle>
              </div>
              {isConnected && (
                <span className="px-3 py-1 rounded-full text-sm font-medium bg-green-100 text-green-800">
                  Connected
                </span>
              )}
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {status === null ? (
              <p className="text-sm text-muted-foreground">Unable to load connection status</p>
            ) : isConnected ? (
              <div className="space-y-6">
                {/* Status badges */}
                <div className="flex flex-wrap gap-2">
                  <span className={`px-3 py-1 rounded-full text-sm font-medium ${
                    isGrantExpired ? 'bg-destructive/10 text-destructive border border-destructive/20' :
                    isReauthDue ? 'bg-warning/10 text-warning border border-warning/20' :
                    'bg-green-100 text-green-800'
                  }`}>
                    {isGrantExpired && (
                      <>
                        <AlertCircle className="inline h-3 w-3 mr-1" /> Grant Expired
                      </>
                    )}
                    {isReauthDue && !isGrantExpired && (
                      <>
                        <AlertCircle className="inline h-3 w-3 mr-1" /> Reauthorisation Due
                      </>
                    )}
                    {!isReauthDue && !isGrantExpired && (
                      <>
                        <CheckCircle2 className="inline h-3 w-3 mr-1" /> Active
                      </>
                    )}
                  </span>
                  <span className="px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
                    {status.environment === 'production' ? 'Production' : 'Sandbox'}
                  </span>
                  {status.scope && (
                    <span className="px-3 py-1 rounded-full text-sm font-medium bg-muted text-muted-foreground">
                      Scopes: {status.scope}
                    </span>
                  )}
                </div>

                {/* Timeline visualization */}
                <div className="p-4 rounded-lg border bg-muted/30">
                  <h4 className="font-medium mb-4">Grant Timeline (18-month wall)</h4>
                  <div className="space-y-3 text-sm">
                    <div className="flex items-center gap-3">
                      <Calendar className="h-4 w-4 text-muted-foreground flex-shrink-0" />
                      <div className="flex-1">
                        <p className="text-muted-foreground">Connected</p>
                        <p className="font-mono">
                          {status.connected_at ? new Date(status.connected_at).toLocaleDateString() : 'Unknown'}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      <Calendar className="h-4 w-4 text-muted-foreground flex-shrink-0" />
                      <div className="flex-1">
                        <p className="text-muted-foreground">Grant Expires</p>
                        <p className="font-mono font-medium text-destructive">
                          {status.grant_expires_at ? new Date(status.grant_expires_at).toLocaleDateString() : 'Unknown'}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      <Clock className="h-4 w-4 text-muted-foreground flex-shrink-0" />
                      <div className="flex-1">
                        <p className="text-muted-foreground">Warning Threshold (90 days before expiry)</p>
                        <p className="font-mono">
                          {status.reauthorisation_due !== undefined 
                            ? (isReauthDue ? 'Passed' : 'Not yet reached') 
                            : 'Unknown'}
                        </p>
                      </div>
                    </div>
                  </div>
                  
                  {/* Progress bar */}
                  {status.connected_at && status.grant_expires_at && (
                    <div className="mt-4">
                      <div className="flex justify-between text-xs text-muted-foreground mb-1">
                        <span>Connected</span>
                        <span>Now</span>
                        <span>Expires</span>
                      </div>
                      <div className="h-2 bg-muted rounded-full overflow-hidden">
                        <div 
                          className={`h-full rounded-full transition-all ${
                            isGrantExpired ? 'bg-destructive' : isReauthDue ? 'bg-warning' : 'bg-primary'
                          }`}
                          style={{ 
                            width: `${Math.min(100, Math.max(0, 
                              (Date.now() - new Date(status.connected_at).getTime()) / 
                              (new Date(status.grant_expires_at).getTime() - new Date(status.connected_at).getTime()) * 100
                            ))}%` 
                          }}
                        />
                      </div>
                    </div>
                  )}
                </div>

                {/* Token details */}
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="p-3 rounded-lg border">
                    <p className="text-xs text-muted-foreground">Access Token Expires</p>
                    <p className="font-mono text-sm {needsRefresh ? 'text-destructive' : ''}">
                      {status.access_token_expires_at ? new Date(status.access_token_expires_at).toLocaleString() : 'Unknown'}
                      {needsRefresh && ' (refresh needed)'}
                    </p>
                  </div>
                  <div className="p-3 rounded-lg border">
                    <p className="text-xs text-muted-foreground">Grant Expires</p>
                    <p className="font-mono text-sm">
                      {status.grant_expires_at ? new Date(status.grant_expires_at).toLocaleDateString() : 'Unknown'}
                    </p>
                  </div>
                  <div className="p-3 rounded-lg border">
                    <p className="text-xs text-muted-foreground">Connected Since</p>
                    <p className="font-mono text-sm">
                      {status.connected_at ? new Date(status.connected_at).toLocaleDateString() : 'Unknown'}
                    </p>
                  </div>
                  <div className="p-3 rounded-lg border">
                    <p className="text-xs text-muted-foreground">Environment</p>
                    <p className="font-mono text-sm capitalize">
                      {status.environment ?? 'Unknown'}
                    </p>
                  </div>
                </div>

                {/* Warning banners */}
                {isGrantExpired && (
                  <div className="p-4 rounded-lg border-2 border-destructive bg-destructive/5">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-destructive flex-shrink-0 mt-0.5" />
                      <div>
                        <p className="font-medium text-destructive">Grant Expired: Cannot File</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          The 18-month authorisation grant has expired. HMRC will refuse any token refresh and all MTD calls will fail. 
                          You must reconnect to HMRC before any VAT returns can be filed.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

                {isReauthDue && !isGrantExpired && (
                  <div className="p-4 rounded-lg border-2 border-warning bg-warning/5">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" />
                      <div>
                        <p className="font-medium text-warning">Reauthorisation Due Within 90 Days</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          Your HMRC authorisation grant expires within 90 days. Plan to reconnect before it expires to avoid filing disruption.
                          The warning appears a full quarter ahead so it cannot fall entirely inside one VAT period.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

                {needsRefresh && !isReauthDue && !isGrantExpired && (
                  <div className="p-4 rounded-lg border-2 border-blue-200 bg-blue-50">
                    <div className="flex items-start gap-3">
                      <AlertCircle className="h-5 w-5 text-blue-600 flex-shrink-0 mt-0.5" />
                      <div>
                        <p className="font-medium text-blue-800">Token Refresh Needed</p>
                        <p className="text-sm text-muted-foreground mt-1">
                          The access token is close to expiry and will be refreshed on the next MTD call. This is normal operation.
                        </p>
                      </div>
                    </div>
                  </div>
                )}

              </div>
            ) : (
              <div className="space-y-4 text-center py-8">
                <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-amber-100 flex items-center justify-center">
                  <AlertCircle className="h-8 w-8 text-amber-600" />
                </div>
                <CardTitle className="text-xl">Not Connected to HMRC</CardTitle>
                <CardDescription>
                  Your company has not yet authorised Vega to access MTD VAT data on HMRC.
                </CardDescription>
                <Button 
                  onClick={() => window.location.href = '/hmrc/connect'}
                  className="w-full sm:w-auto btn-gradient mt-4"
                  size="lg"
                >
                  <ExternalLink className="mr-2 h-4 w-4" />
                  Connect to HMRC
                </Button>
              </div>
            )}

            {error && (
              <div className="p-4 rounded-lg border border-destructive/30 bg-destructive/5 text-destructive text-sm">
                {error}
              </div>
            )}

          </CardContent>
        </Card>

        {/* Quick Links */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5" />
              Quick Actions
            </CardTitle>
          </CardHeader>
          <CardContent className="grid gap-3 sm:grid-cols-2">
            <Button 
              variant="outline" 
              onClick={() => window.location.href = '/hmrc/obligations'}
              disabled={!isConnected}
              className="h-auto py-4"
            >
              <Calendar className="mr-2 h-4 w-4" />
              <div className="text-left">
                <p className="font-medium">View VAT Obligations</p>
                <p className="text-xs text-muted-foreground">See what periods HMRC expects returns for</p>
              </div>
            </Button>
            <Button 
              variant="outline" 
              onClick={() => window.location.href = '/vat'}
              className="h-auto py-4"
            >
              <Calendar className="mr-2 h-4 w-4" />
              <div className="text-left">
                <p className="font-medium">VAT Return Preview</p>
                <p className="text-xs text-muted-foreground">Preview boxes 1-9 for any period</p>
              </div>
            </Button>
          </CardContent>
        </Card>

        {/* Info Card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5" />
              Security & Compliance
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm text-muted-foreground">
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
              <p>Tokens encrypted at rest using Fernet (AES-128-GCM)</p>
            </div>
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
              <p>Refresh tokens rotate on each use; old tokens invalidated</p>
            </div>
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
              <p>Only 'read:vat' and 'write:vat' scopes requested</p>
            </div>
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
              <p>Fraud prevention headers collected from browser (never invented server-side)</p>
            </div>
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
              <p>18-month grant expiry monitored; warning appears 90 days before expiry</p>
            </div>
            <div className="flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
              <p>Connection status scoped to your company via X-Vega-Company header</p>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}