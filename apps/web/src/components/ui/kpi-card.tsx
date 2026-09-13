import React, { useEffect, useState } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { LucideIcon, TrendingUp, TrendingDown } from 'lucide-react';
import { cn } from '@/lib/utils';

interface KPICardProps {
  title: string;
  value: number | string;
  prefix?: string;
  suffix?: string;
  trend?: {
    value: number;
    isPositive: boolean;
    label?: string;
  };
  icon: LucideIcon;
  variant?: 'default' | 'success' | 'warning' | 'danger' | 'info';
  action?: {
    label: string;
    onClick: () => void;
  };
  sparklineData?: number[];
  loading?: boolean;
}

export const KPICard: React.FC<KPICardProps> = ({
  title,
  value,
  prefix = '',
  suffix = '',
  trend,
  icon: Icon,
  variant = 'default',
  action,
  sparklineData,
  loading = false,
}) => {
  const [displayValue, setDisplayValue] = useState(0);

  // Animated counter effect
  useEffect(() => {
    if (typeof value !== 'number' || loading) return;
    
    const duration = 1000;
    const steps = 60;
    const stepValue = value / steps;
    let currentStep = 0;

    const timer = setInterval(() => {
      currentStep++;
      if (currentStep <= steps) {
        setDisplayValue(Math.floor(stepValue * currentStep));
      } else {
        setDisplayValue(value);
        clearInterval(timer);
      }
    }, duration / steps);

    return () => clearInterval(timer);
  }, [value, loading]);

  const variantStyles = {
    default: 'border-border bg-card',
    success: 'border-green-500/30 bg-gradient-to-br from-green-500/5 to-green-500/10',
    warning: 'border-amber-500/30 bg-gradient-to-br from-amber-500/5 to-amber-500/10',
    danger: 'border-red-500/30 bg-gradient-to-br from-red-500/5 to-red-500/10',
    info: 'border-blue-500/30 bg-gradient-to-br from-blue-500/5 to-blue-500/10',
  };

  const iconStyles = {
    default: 'text-muted-foreground bg-muted',
    success: 'text-green-600 bg-green-500/10',
    warning: 'text-amber-600 bg-amber-500/10',
    danger: 'text-red-600 bg-red-500/10',
    info: 'text-blue-600 bg-blue-500/10',
  };

  if (loading) {
    return (
      <Card className="border shadow-sm">
        <CardContent className="p-6">
          <div className="space-y-4 animate-pulse">
            <div className="h-4 bg-muted rounded w-1/2" />
            <div className="h-12 bg-muted rounded w-3/4" />
            <div className="h-3 bg-muted rounded w-1/3" />
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className={cn(
      'border transition-all duration-300 hover:shadow-lg hover:scale-[1.02]',
      variantStyles[variant]
    )}>
      <CardContent className="p-5 space-y-3">
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium text-muted-foreground mb-2 line-clamp-1">{title}</p>
          </div>
          <div className={cn(
            'p-2.5 rounded-xl flex-shrink-0',
            iconStyles[variant]
          )}>
            <Icon className="h-5 w-5" />
          </div>
        </div>

        <div className="space-y-2">
          <div className="text-3xl font-bold tracking-tight break-words">
            {prefix}{typeof value === 'number' ? displayValue.toLocaleString('en-IN') : value}{suffix}
          </div>

          {trend && (
            <div className="flex flex-col gap-1">
              <div className={cn(
                'inline-flex items-center gap-1 text-xs font-medium px-2 py-1 rounded-md w-fit',
                trend.isPositive ? 'text-green-600 bg-green-500/10' : 'text-red-600 bg-red-500/10'
              )}>
                {trend.isPositive ? (
                  <TrendingUp className="h-3 w-3 flex-shrink-0" />
                ) : (
                  <TrendingDown className="h-3 w-3 flex-shrink-0" />
                )}
                <span className="whitespace-nowrap">{trend.isPositive ? '+' : ''}{trend.value}%</span>
              </div>
              {trend.label && (
                <span className="text-xs text-muted-foreground">{trend.label}</span>
              )}
            </div>
          )}
        </div>

        {sparklineData && sparklineData.length > 0 && (
          <div className="h-8 flex items-end gap-0.5">
            {sparklineData.map((value, index) => {
              const maxValue = Math.max(...sparklineData);
              const height = (value / maxValue) * 100;
              return (
                <div
                  key={index}
                  className={cn(
                    'flex-1 rounded-sm transition-all',
                    variant === 'success' ? 'bg-green-500/30' :
                    variant === 'warning' ? 'bg-amber-500/30' :
                    variant === 'danger' ? 'bg-red-500/30' :
                    variant === 'info' ? 'bg-blue-500/30' :
                    'bg-primary/30'
                  )}
                  style={{ height: `${height}%` }}
                />
              );
            })}
          </div>
        )}

        {action && (
          <button
            onClick={action.onClick}
            className="mt-3 text-sm font-medium text-primary hover:underline"
          >
            {action.label} →
          </button>
        )}
      </CardContent>
    </Card>
  );
};
