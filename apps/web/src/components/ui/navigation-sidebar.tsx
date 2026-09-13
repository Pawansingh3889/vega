import React from 'react';
import { cn } from '@/lib/utils';
import { useBusinessAuth } from '@/hooks/useBusinessAuth';
import { 
  BarChart3, 
  Package, 
  ShoppingCart, 
  FileText, 
  RotateCcw, 
  CreditCard, 
  TrendingUp, 
  MapPin, 
  Bot, 
  Users, 
  Building2,
  Settings
} from 'lucide-react';

interface NavigationSidebarProps {
  activeView?: string;
  onNavigate: (view: string) => void;
  className?: string;
}

interface NavigationItem {
  id: string;
  label: string;
  icon: React.ElementType;
  section?: string; // Section permission required
  public?: boolean; // Always visible (dashboard, profile)
}

const navigationItems: NavigationItem[] = [
  { id: 'dashboard', label: 'Welcome back, Girish!', icon: BarChart3, public: true },
  { id: 'inventory', label: 'Inventory', icon: Package, section: 'inventory' },
  { id: 'purchase', label: 'Purchase', icon: ShoppingCart, section: 'purchase' },
  { id: 'sales', label: 'Sales', icon: FileText, section: 'sales' },
  { id: 'returns', label: 'Returns', icon: RotateCcw, section: 'returns' },
  { id: 'payments', label: 'Payments', icon: CreditCard, section: 'payments' },
  { id: 'reports', label: 'Reports', icon: TrendingUp, section: 'reports' },
  { id: 'tracking', label: 'Track & Trace', icon: MapPin, section: 'tracking' },
  { id: 'ai', label: 'AI Assistant', icon: Bot, section: 'ai' },
  { id: 'users', label: 'Team Management', icon: Users, section: 'users' },
  { id: 'profile', label: 'Company Profile', icon: Building2, public: true },
  { id: 'settings', label: 'Settings', icon: Settings, section: 'settings' },
];

export const NavigationSidebar: React.FC<NavigationSidebarProps> = ({
  activeView = 'dashboard',
  onNavigate,
  className
}) => {
  const { hasAccess, loading: authLoading } = useBusinessAuth();

  // Filter navigation items based on permissions
  const visibleItems = authLoading 
    ? navigationItems.filter(item => item.public) // Show only public items during load
    : navigationItems.filter(item => {
        // Show public items (dashboard, profile) to everyone
        if (item.public) return true;
        
        // If section permission is defined, check access (explicitly check for true)
        if (item.section) {
          return hasAccess(item.section) === true;
        }
        
        return true;
      });

  return (
    <div className={cn(
      "w-64 bg-background border-r border-border flex flex-col h-screen overflow-y-auto",
      className
    )}>
      <div className="p-3 sm:p-4 border-b border-border">
        <h2 className="text-base sm:text-lg font-semibold text-foreground">Navigation</h2>
      </div>
      
      <nav className="flex-1 p-2">
        <ul className="space-y-1">
          {visibleItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeView === item.id;
            
            return (
              <li key={item.id}>
                <button
                  onClick={() => onNavigate(item.id)}
                  className={cn(
                    "w-full flex items-center gap-2 sm:gap-3 px-2 sm:px-3 py-3 text-sm rounded-md transition-colors text-left min-h-[48px]",
                    isActive 
                      ? "bg-primary text-primary-foreground font-medium" 
                      : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                  )}
                >
                  <Icon className="h-4 w-4 flex-shrink-0" />
                  <span className="truncate">{item.label}</span>
                </button>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
};