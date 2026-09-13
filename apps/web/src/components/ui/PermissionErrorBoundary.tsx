import React from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { AlertTriangle, RefreshCcw } from 'lucide-react';

interface PermissionErrorBoundaryProps {
  children: React.ReactNode;
  fallback?: React.ReactNode;
}

interface PermissionErrorBoundaryState {
  hasError: boolean;
  error?: any;
}

export class PermissionErrorBoundary extends React.Component<
  PermissionErrorBoundaryProps,
  PermissionErrorBoundaryState
> {
  constructor(props: PermissionErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: any) {
    return { hasError: true, error };
  }

  componentDidCatch(error: any, errorInfo: any) {
    console.error('[PermissionErrorBoundary] Caught error:', error);
    console.error('[PermissionErrorBoundary] Component stack:', errorInfo?.componentStack);
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: undefined });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <Card className="max-w-md mx-auto">
          <CardHeader className="text-center">
            <AlertTriangle className="h-12 w-12 text-destructive mx-auto mb-4" />
            <CardTitle>Something went wrong</CardTitle>
          </CardHeader>
          <CardContent className="text-center space-y-4">
            <p className="text-sm text-muted-foreground">
              There was an error loading this section. Please try again.
            </p>
            <Button 
              onClick={this.handleRetry} 
              variant="outline" 
              size="sm"
              className="w-full"
            >
              <RefreshCcw className="mr-2 h-4 w-4" />
              Try Again
            </Button>
          </CardContent>
        </Card>
      );
    }

    return this.props.children;
  }
}