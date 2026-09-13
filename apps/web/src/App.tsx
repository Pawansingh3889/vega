import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "@/hooks/useAuth";
import { CompanyProvider } from "@/contexts/CompanyContext";
import { ErrorBoundary } from "@/components/ui/ErrorBoundary";

import Index from "@/pages/Index";
import Auth from "@/pages/Auth";
import EnhancedAuth from "@/pages/EnhancedAuth";
import Signin from "@/pages/Signin";
import GatedSignin from "@/pages/GatedSignin";
import BusinessRegistration from "@/pages/BusinessRegistration";
import GatedBusinessRegistration from "@/pages/GatedBusinessRegistration";
import GatedForgotPassword from "@/pages/GatedForgotPassword";
import GatedResetPassword from "@/pages/GatedResetPassword";
import PasswordReset from "@/pages/PasswordReset";
import EmailConfirmation from "@/pages/EmailConfirmation";
import EmailVerification from "@/pages/EmailVerification";
import VatPreview from "@/pages/VatPreview";
import Dashboard from "@/pages/Dashboard";
import HmrcStatusPage from "@/pages/HmrcStatus";
import NotFound from "@/pages/NotFound";

// Phase 0 routes only: the marketing entry and the authentication surface.
// Operational routes (inventory, sales, purchasing, traceability) arrive with
// the phases that build them. See ROADMAP.md.
const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <ErrorBoundary>
      <AuthProvider>
        <CompanyProvider>
          <TooltipProvider>
            <Toaster />
            <Sonner />
            <BrowserRouter>
              <Routes>
                <Route path="/" element={<Index />} />
                <Route path="/auth" element={<Auth />} />
                <Route path="/auth/enhanced" element={<EnhancedAuth />} />
                <Route path="/signin" element={<Signin />} />
                <Route path="/gated/signin" element={<GatedSignin />} />
                <Route path="/register" element={<BusinessRegistration />} />
                <Route path="/gated/register" element={<GatedBusinessRegistration />} />
                <Route path="/gated/forgot-password" element={<GatedForgotPassword />} />
                <Route path="/gated/reset-password" element={<GatedResetPassword />} />
                <Route path="/password-reset" element={<PasswordReset />} />
                <Route path="/email-confirmation" element={<EmailConfirmation />} />
                <Route path="/email-verification" element={<EmailVerification />} />
                {/* First operational surface: the Phase 2 VAT preview endpoint
                    finally has a caller. See ROADMAP.md Phase 2. */}
                <Route path="/vat" element={<VatPreview />} />

                {/* Phase 4. Only /hmrc/status, because it is the only one of
                    these whose endpoint the server actually registers. The
                    connect, callback and obligations pages are written and
                    parked on an unmerged branch: routing to them now would
                    advertise four screens, three of which 404 on first use. */}
                {/* Where sign-in lands. Missing until now, so a correct
                    sign-in fell through to NotFound. */}
                <Route path="/dashboard" element={<Dashboard />} />

                <Route path="/hmrc/status" element={<HmrcStatusPage />} />

                <Route path="*" element={<NotFound />} />
              </Routes>
            </BrowserRouter>
          </TooltipProvider>
        </CompanyProvider>
      </AuthProvider>
    </ErrorBoundary>
  </QueryClientProvider>
);

export default App;
