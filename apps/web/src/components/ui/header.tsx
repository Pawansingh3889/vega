import React from 'react';
import { Button } from '@/components/ui/button';
import { User, LogOut } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useBusinessAuth } from '@/hooks/useBusinessAuth';
import { useIsMobile } from '@/hooks/use-mobile';
import { useNavigate } from 'react-router-dom';

interface HeaderProps {
  title?: string;
  subtitle?: string;
  actions?: React.ReactNode;
  showSearch?: boolean;
  showWelcome?: boolean;
}

export const Header: React.FC<HeaderProps> = ({
  title,
  subtitle,
  actions,
  showSearch: _showSearch = true,
  showWelcome = false
}) => {
  const { user, signOut, company, profile } = useAuth();
  const { businessUser } = useBusinessAuth();
  const isMobile = useIsMobile();
  const navigate = useNavigate();

  const getDisplayName = () => {
    // Debug logging to see what data we have
    console.log('Header Debug - Profile:', profile);
    console.log('Header Debug - BusinessUser:', businessUser);
    console.log('Header Debug - User:', user);
    
    // First priority: profile first_name and last_name
    if (profile?.first_name && profile?.last_name) {
      const fullName = `${profile.first_name} ${profile.last_name}`;
      console.log('Header Debug - Using full name:', fullName);
      return fullName;
    }
    
    // Second priority: just first_name
    if (profile?.first_name) {
      console.log('Header Debug - Using first name:', profile.first_name);
      return profile.first_name;
    }
    
    // Third priority: businessUser username
    if (businessUser?.username) {
      console.log('Header Debug - Using business username:', businessUser.username);
      return businessUser.username;
    }
    
    // Fallback: user email
    if (user?.email) {
      console.log('Header Debug - Using user email:', user.email);
      return user.email;
    }
    
    console.log('Header Debug - No name found, returning null');
    return null;
  };

  const displayName = getDisplayName();

  return (
    <header className="bg-gradient-primary border-b border-border/20 sticky top-0 inset-x-0 w-screen z-40 backdrop-blur supports-[backdrop-filter]:bg-gradient-primary/95 shadow-lg">
      <div className="px-4 md:px-6 py-4 md:py-5">
        <div className="flex items-center">
          {/* Left Section - Title/Welcome */}
          <div className="flex-1 min-w-0 pr-4">
            {showWelcome ? (
              <div className="space-y-1">
                <h1 className="text-lg md:text-2xl font-bold text-white drop-shadow-sm truncate">
                  {displayName ? `Welcome back, ${displayName}! 👋` : 'Welcome back! 👋'}
                </h1>
                <p className="text-xs md:text-sm text-white/80 hidden sm:block">
                  Here's what's happening with your business today
                </p>
              </div>
            ) : (
              <div className="space-y-1">
                <h1 className="text-lg md:text-xl font-semibold text-white drop-shadow-sm truncate">
                  {title}
                </h1>
                {subtitle && (
                  <p className="text-xs md:text-sm text-white/80 hidden sm:block">
                    {subtitle}
                  </p>
                )}
              </div>
            )}
          </div>

          {/* Center Section - Company Badge (Hidden on mobile) */}
          {!isMobile && company && (
            <div className="absolute left-1/2 transform -translate-x-1/2">
              <div className="bg-white/95 backdrop-blur-sm border border-white/30 rounded-xl px-5 py-3 shadow-lg ring-1 ring-black/10">
                <div className="text-center">
                  <div className="text-sm font-semibold text-gray-900 whitespace-nowrap">
                    {company.name || 'Unknown Company'}
                  </div>
                  <div className="text-xs text-gray-600 mt-0.5">
                    ID: {company.business_ref_no || company.id || 'No ID'}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Right Section - Actions */}
          <div className="flex items-center gap-2 md:gap-3 flex-1 justify-end pl-4">
            {actions}
            
            {user ? (
              <Button
                onClick={signOut}
                variant="ghost"
                size={isMobile ? "sm" : "sm"}
                className="text-white hover:bg-white/20 hover:text-white min-h-[44px] md:min-h-auto border border-white/20"
              >
                <LogOut className="h-4 w-4 md:mr-2" />
                <span className="hidden md:inline">Sign Out</span>
              </Button>
            ) : (
              <Button 
                onClick={() => navigate('/auth')}
                variant="ghost" 
                size={isMobile ? "sm" : "sm"} 
                className="text-white hover:bg-white/20 hover:text-white min-h-[44px] md:min-h-auto border border-white/20"
              >
                <User className="h-4 w-4 md:mr-2" />
                <span className="hidden md:inline">Sign In</span>
              </Button>
            )}
          </div>
        </div>
      </div>
    </header>
  );
};