import React, { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { 
  Loader2, 
  LogIn, 
  Building2,
  User,
  Lock,
  AlertCircle,
  CheckCircle
} from 'lucide-react';

const GatedSignin = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { toast } = useToast();
  
  const [isLoading, setIsLoading] = useState(false);
  const [formData, setFormData] = useState({
    username: '',
    password: ''
  });

  const message = location.state?.message;


  const handleInputChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const validateForm = () => {
    const { username, password } = formData;

    if (!username.trim()) {
      toast({ title: "Username is required", variant: "destructive" });
      return false;
    }

    if (!password) {
      toast({ title: "Password is required", variant: "destructive" });
      return false;
    }

    return true;
  };

  const handleSignin = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) return;

    setIsLoading(true);
    try {
      console.log('[SIGNIN] Attempting sign in for:', formData.username);
      
      // Call edge function with proper error handling
      const { data, error: invokeError } = await supabase.functions.invoke('signin', {
        body: {
          username: formData.username.trim(),
          password: formData.password
        }
      });
      
      if (invokeError) {
        console.error('[SIGNIN] Invoke error:', invokeError);
        throw new Error(invokeError.message || 'Failed to call sign-in function');
      }
      
      console.log('[SIGNIN] Response received:', data);
      
      if (data?.success) {
        // Sign in with Supabase Auth
        const { error: authError } = await supabase.auth.signInWithPassword({
          email: data.user.email,
          password: formData.password
        });

        if (authError) {
          throw new Error('Authentication failed: ' + authError.message);
        }

        toast({
          title: "Sign In Successful!",
          description: `Welcome back, ${data.user.email}!`
        });

        navigate('/dashboard');
      } else {
        throw new Error(data.error || 'Sign in failed');
      }
    } catch (error: any) {
      console.error('Signin error:', error);
      
      let errorMessage = error.message || "Please check your credentials and try again.";
      
      // Provide more helpful error messages
      if (errorMessage.includes('Failed to fetch') || errorMessage.includes('NetworkError')) {
        errorMessage = "Network error: Unable to connect to authentication service. Please check your internet connection and ensure edge functions are deployed.";
      } else if (errorMessage.includes('CORS')) {
        errorMessage = "CORS error: Authentication service configuration issue. Please contact support.";
      }
      
      toast({
        title: "Sign In Failed",
        description: errorMessage,
        variant: "destructive"
      });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-subtle flex items-center justify-center">
      <div className="content-container w-full max-w-md mx-4">
        {/* Success Message */}
        {message && (
          <Card className="mb-6 border-success/20 bg-success/5">
            <CardContent className="pt-6">
              <div className="flex items-start space-x-3">
                <CheckCircle className="h-5 w-5 text-success mt-0.5" />
                <p className="text-sm text-success">{message}</p>
              </div>
            </CardContent>
          </Card>
        )}

        <Card className="shadow-elevated">
          <CardHeader className="text-center">
            <Building2 className="h-12 w-12 text-primary mx-auto mb-4" />
            <CardTitle className="text-3xl">Business Portal</CardTitle>
            <CardDescription className="text-lg">
              Sign in to access your business dashboard
            </CardDescription>
          </CardHeader>

          <CardContent>
            <form onSubmit={handleSignin} className="space-y-6">
              <div className="space-y-2">
                <Label htmlFor="username" className="flex items-center gap-2">
                  <User className="h-4 w-4" />
                  Username or Email
                </Label>
                <Input
                  id="username"
                  value={formData.username}
                  onChange={(e) => handleInputChange('username', e.target.value)}
                  placeholder="Enter your username or email"
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="password" className="flex items-center gap-2">
                  <Lock className="h-4 w-4" />
                  Password
                </Label>
                <Input
                  id="password"
                  type="password"
                  value={formData.password}
                  onChange={(e) => handleInputChange('password', e.target.value)}
                  placeholder="Enter your password"
                  required
                />
              </div>

              <Button
                type="submit"
                disabled={isLoading}
                className="w-full btn-gradient text-lg py-6"
                size="lg"
              >
                {isLoading ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Signing In...
                  </>
                ) : (
                  <>
                    <LogIn className="mr-2 h-5 w-5" />
                    Sign In
                  </>
                )}
              </Button>
            </form>

            <Separator className="my-6" />

            <div className="text-center space-y-4">
              <Button
                variant="link"
                onClick={() => navigate('/gated/forgot-password')}
                className="text-primary hover:text-primary/80"
              >
                Forgot Password?
              </Button>

              <div className="bg-muted/50 p-4 rounded-lg">
                <div className="flex items-start space-x-2">
                  <AlertCircle className="h-4 w-4 text-muted-foreground mt-0.5" />
                  <div className="text-xs text-muted-foreground">
                    <p className="font-medium mb-1">Need help?</p>
                    <p>Only businesses with verified payment can access this portal. Contact support if you're having trouble signing in.</p>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="text-center mt-6">
          <Button
            variant="ghost"
            onClick={() => navigate('/')}
            className="text-muted-foreground hover:text-foreground"
          >
            ← Back to Home
          </Button>
        </div>
      </div>
    </div>
  );
};

export default GatedSignin;