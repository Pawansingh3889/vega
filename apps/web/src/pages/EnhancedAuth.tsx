import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Eye, EyeOff, Loader2, Shield, Building2, User, Lock, LogIn } from 'lucide-react';
import { Captcha } from '@/components/ui/captcha';

const EnhancedAuth = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { toast } = useToast();
  const [isLoading, setIsLoading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [passwords, setPasswords] = useState({ password: '', confirmPassword: '' });
  const [showPassword, setShowPassword] = useState(false);
  const [activeTab, setActiveTab] = useState<'signin' | 'forgot'>('signin');
  const [captchaToken, setCaptchaToken] = useState<string>('');
  const [username, setUsername] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [skipRedirect, setSkipRedirect] = useState(false);
  
  const { resetPassword, user, session, loading: authLoading } = useAuth();

  useEffect(() => {
    // Check if there's a tab parameter in the URL
    const searchParams = new URLSearchParams(location.search);
    const tab = searchParams.get('tab');
    if (tab === 'forgot') {
      setActiveTab('forgot');
    }

    // Check if there's a success message from business registration
    const state = location.state as { fromRegistration?: boolean; message?: string };
    if (state?.fromRegistration && state?.message) {
      toast({
        title: "Registration Complete",
        description: state.message,
      });
    }

    setLoading(false);
  }, [location, toast]);

  // Clear any stale auth state on mount and prevent immediate redirect
  useEffect(() => {
    console.log('EnhancedAuth mounted');
    setSkipRedirect(true);
    
    // Clear any stale session when auth page loads
    const clearStaleAuth = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      console.log('Current session check:', !!session);
      if (session) {
        console.log('Clearing existing session to allow login');
        await supabase.auth.signOut();
      }
    };
    clearStaleAuth();
  }, []);

  // Redirect if already logged in with valid session (but not if we just navigated here)
  useEffect(() => {
    console.log('Auth redirect check:', { user: !!user, session: !!session, authLoading, skipRedirect });
    // Don't redirect immediately after mount - give time to clear stale state
    if (skipRedirect) {
      const timer = setTimeout(() => setSkipRedirect(false), 500);
      return () => clearTimeout(timer);
    }
    
    // Only redirect if we have both user AND valid session, and auth is not loading
    if (!authLoading && user && session && !skipRedirect) {
      console.log('Valid session found, redirecting to dashboard');
      navigate('/dashboard');
    }
  }, [user, session, authLoading, navigate, skipRedirect]);

  const handleSignIn = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    
    // Validate form
    const newErrors: Record<string, string> = {};
    
    if (!username.trim()) {
      newErrors.username = 'Username is required';
    }
    
    if (!passwords.password) {
      newErrors.password = 'Password is required';
    }
    
    // Validate captcha if configured with a valid site key
    const captchaElement = document.querySelector('meta[name="turnstile-sitekey"]');
    const siteKey = captchaElement?.getAttribute('content');
    if (siteKey && siteKey.trim() !== '' && !captchaToken) {
      newErrors.captcha = 'Please complete the captcha verification';
    }
    
    setErrors(newErrors);
    if (Object.keys(newErrors).length > 0) return;
    
    setIsLoading(true);

    try {
      const { data, error } = await supabase.functions.invoke('signin', {
        body: {
          username: username.trim(),
          password: passwords.password
        }
      });

      if (error) throw error;

      if (data?.success) {
        // Sign in with Supabase Auth to create a proper session
        const { error: authError } = await supabase.auth.signInWithPassword({
          email: data.user.email,
          password: passwords.password
        });

        if (authError) {
          throw new Error('Authentication failed: ' + authError.message);
        }

        toast({
          title: "Welcome back!",
          description: `Successfully signed in as ${data.user.email}`,
        });
        navigate('/dashboard');
      } else {
        throw new Error(data?.error || 'Sign in failed');
      }
    } catch (error: any) {
      const errorMessage = error.message || "Sign in failed";
      
      if (errorMessage.includes('Invalid credentials') || errorMessage.includes('Invalid')) {
        setErrors({ general: 'Invalid username or password.' });
      } else if (errorMessage.includes('suspended') || errorMessage.includes('not active')) {
        setErrors({ general: 'This account is not active. Contact support.' });
      } else if (errorMessage.includes('attempts') || errorMessage.includes('rate')) {
        setErrors({ general: 'Too many attempts. Try again in a few minutes.' });
      } else {
        setErrors({ general: errorMessage });
      }
      
      toast({
        title: "Sign In Failed",
        description: errorMessage,
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
      setCaptchaToken('');
    }
  };

  const handleForgotPassword = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setIsLoading(true);
    
    const formData = new FormData(e.currentTarget);
    const email = formData.get('email') as string;

    try {
      await resetPassword(email);
      toast({
        title: "Password Reset Email Sent",
        description: "Please check your email for the reset link.",
      });
    } catch (error: any) {
      toast({
        title: "Password Reset Failed",
        description: error.message || "Unable to send reset email. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-subtle flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <Card className="shadow-elevated">
          <CardHeader className="text-center space-y-4">
            <div className="flex justify-center">
              <div className="p-3 rounded-full bg-primary/10">
                <Building2 className="h-8 w-8 text-primary" />
              </div>
            </div>
            <div>
              <CardTitle className="text-2xl">Rigel Inventory</CardTitle>
              <CardDescription>Business Portal</CardDescription>
            </div>
            <div className="flex items-center justify-center gap-2 text-xs text-muted-foreground">
              <Shield className="h-3 w-3" />
              <span>Secured with advanced encryption</span>
            </div>
          </CardHeader>

          <CardContent>
            <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as 'signin' | 'forgot')}>
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="signin">Sign In</TabsTrigger>
                <TabsTrigger value="forgot">Forgot Password</TabsTrigger>
              </TabsList>

              <TabsContent value="signin" className="space-y-4">
                <form onSubmit={handleSignIn} className="space-y-4">
                  {errors.general && (
                    <div className="text-sm text-destructive bg-destructive/10 p-3 rounded-md">
                      {errors.general}
                    </div>
                  )}
                  
                  <div className="space-y-2">
                    <Label htmlFor="username" className="flex items-center gap-2">
                      <User className="h-4 w-4" />
                      Username or Email
                    </Label>
                    <Input
                      id="username"
                      name="username"
                      type="text"
                      placeholder="Enter your username or email"
                      required
                      className={errors.username ? 'border-destructive' : ''}
                      value={username}
                      onChange={(e) => {
                        setUsername(e.target.value);
                        setErrors(prev => ({ ...prev, username: '', general: '' }));
                      }}
                    />
                    {errors.username && (
                      <p className="text-xs text-destructive">{errors.username}</p>
                    )}
                  </div>
                  
                  <div className="space-y-2">
                    <Label htmlFor="password" className="flex items-center gap-2">
                      <Lock className="h-4 w-4" />
                      Password
                    </Label>
                    <div className="relative">
                      <Input
                        id="password"
                        name="password"
                        type={showPassword ? "text" : "password"}
                        placeholder="Enter your password"
                        required
                        autoComplete="current-password"
                        className={`pr-10 ${errors.password ? 'border-destructive' : ''}`}
                        value={passwords.password}
                        onChange={(e) => {
                          setPasswords(prev => ({ ...prev, password: e.target.value }));
                          setErrors(prev => ({ ...prev, password: '', general: '' }));
                        }}
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="absolute right-0 top-0 h-full px-3"
                        onClick={() => setShowPassword(!showPassword)}
                      >
                        {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                      </Button>
                    </div>
                    {errors.password && (
                      <p className="text-xs text-destructive">{errors.password}</p>
                    )}
                  </div>

                  <Captcha 
                    onVerify={(token) => {
                      setCaptchaToken(token);
                      setErrors(prev => ({ ...prev, captcha: '' }));
                    }}
                    onExpire={() => setCaptchaToken('')}
                  />
                  {errors.captcha && (
                    <p className="text-xs text-destructive">{errors.captcha}</p>
                  )}

                  <Button 
                    type="submit" 
                    className="w-full btn-gradient" 
                    size="lg"
                    disabled={isLoading}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Signing in...
                      </>
                    ) : (
                      <>
                        <LogIn className="mr-2 h-4 w-4" />
                        Sign In
                      </>
                    )}
                  </Button>
                </form>
              </TabsContent>

              <TabsContent value="forgot" className="space-y-4">
                <form onSubmit={handleForgotPassword} className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="forgot-email">Email</Label>
                    <Input
                      id="forgot-email"
                      name="email"
                      type="email"
                      placeholder="you@example.com"
                      required
                      autoComplete="email"
                    />
                    <p className="text-xs text-muted-foreground">
                      Enter your registered email address to receive a password reset link.
                    </p>
                  </div>

                  <Button 
                    type="submit" 
                    className="w-full" 
                    disabled={isLoading}
                  >
                    {isLoading ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Sending...
                      </>
                    ) : (
                      "Send Reset Link"
                    )}
                  </Button>
                </form>
              </TabsContent>
            </Tabs>
          </CardContent>

          <CardFooter className="flex-col space-y-4">
            <div className="text-center text-xs text-muted-foreground">
              <p>Only registered, paid businesses can sign in.</p>
              <p className="mt-2">
                By signing in, you agree to our{' '}
                <a href="/terms" className="text-primary hover:underline">Terms of Service</a>
                {' '}and{' '}
                <a href="/privacy" className="text-primary hover:underline">Privacy Policy</a>.
              </p>
            </div>
            
            <Button
              variant="ghost"
              onClick={() => navigate('/')}
              className="w-full"
            >
              ← Back to Home
            </Button>
          </CardFooter>
        </Card>
      </div>
    </div>
  );
};

export default EnhancedAuth;
