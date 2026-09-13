import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { LucideIcon, AlertCircle, AlertTriangle, Info, CheckCircle } from 'lucide-react';
import { cn } from '@/lib/utils';

type AlertPriority = 'critical' | 'high' | 'medium' | 'info';

interface AlertCardProps {
  title: string;
  description: string;
  priority: AlertPriority;
  count?: number;
  value?: string;
  icon?: LucideIcon;
  actions?: Array<{
    label: string;
    onClick: () => void;
    variant?: 'default' | 'outline' | 'ghost';
  }>;
  timestamp?: string;
  className?: string;
}

const priorityConfig: Record<AlertPriority, {
  icon: LucideIcon;
  color: string;
  bgColor: string;
  borderColor: string;
  badge: string;
}> = {
  critical: {
    icon: AlertCircle,
    color: 'text-red-600',
    bgColor: 'bg-red-500/5',
    borderColor: 'border-red-500/30',
    badge: 'destructive',
  },
  high: {
    icon: AlertTriangle,
    color: 'text-amber-600',
    bgColor: 'bg-amber-500/5',
    borderColor: 'border-amber-500/30',
    badge: 'default',
  },
  medium: {
    icon: Info,
    color: 'text-blue-600',
    bgColor: 'bg-blue-500/5',
    borderColor: 'border-blue-500/30',
    badge: 'secondary',
  },
  info: {
    icon: CheckCircle,
    color: 'text-green-600',
    bgColor: 'bg-green-500/5',
    borderColor: 'border-green-500/30',
    badge: 'outline',
  },
};

export const AlertCard: React.FC<AlertCardProps> = ({
  title,
  description,
  priority,
  count,
  value,
  icon,
  actions = [],
  timestamp,
  className,
}) => {
  const config = priorityConfig[priority];
  const IconComponent = icon || config.icon;

  return (
    <Card className={cn(
      'border transition-all duration-300 hover:shadow-md',
      config.borderColor,
      config.bgColor,
      className
    )}>
      <CardContent className="p-4">
        <div className="flex items-start gap-3">
          <div className={cn(
            'p-2 rounded-lg mt-0.5',
            config.color,
            config.bgColor
          )}>
            <IconComponent className="h-5 w-5" />
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-2 mb-1">
              <div className="flex items-center gap-2">
                <Badge variant={config.badge as any} className="text-xs">
                  {priority.toUpperCase()}
                </Badge>
                {count !== undefined && (
                  <span className={cn('text-sm font-semibold', config.color)}>
                    {count} {count === 1 ? 'Item' : 'Items'}
                  </span>
                )}
              </div>
              {timestamp && (
                <span className="text-xs text-muted-foreground whitespace-nowrap">
                  {timestamp}
                </span>
              )}
            </div>

            <h4 className="font-semibold text-foreground mb-1">
              {title}
            </h4>
            <p className="text-sm text-muted-foreground mb-2">
              {description}
            </p>

            {value && (
              <p className={cn('text-sm font-semibold mb-3', config.color)}>
                {value}
              </p>
            )}

            {actions.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {actions.map((action, index) => (
                  <Button
                    key={index}
                    size="sm"
                    variant={action.variant || 'default'}
                    onClick={action.onClick}
                  >
                    {action.label}
                  </Button>
                ))}
              </div>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
