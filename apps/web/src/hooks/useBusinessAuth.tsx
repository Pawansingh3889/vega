import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface BusinessUser {
  id: string;
  username: string;
  email: string;
  access_type: 'OWNER' | 'ADMIN' | 'USER';
  status: 'ACTIVE' | 'INACTIVE';
  company_id: string;
}

interface SectionPermissions {
  [sectionKey: string]: 'read' | 'edit';
}

export const useBusinessAuth = () => {
  const { user, company } = useAuth();
  const [businessUser, setBusinessUser] = useState<BusinessUser | null>(null);
  const [sectionPermissions, setSectionPermissions] = useState<SectionPermissions>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchAllData = async () => {
      if (!user?.email || !user?.id || !company?.id) {
        setBusinessUser(null);
        setSectionPermissions({});
        setLoading(false);
        return;
      }
      
      try {
        // Fetch business user from company_users table
        const { data: businessUserData, error: businessUserError } = await supabase
          .from('company_users')
          .select('id, user_id, email, username, access_type, company_id, full_name, designation, status')
          .eq('user_id', user.id)
          .eq('company_id', company.id)
          .maybeSingle();

        if (businessUserError) {
          console.error('[BusinessAuth] Error fetching business user:', businessUserError);
        }

        // Fetch section permissions
        const { data: permData, error: permError } = await supabase
          .from('company_user_section_permissions')
          .select('access_sections')
          .eq('company_id', company.id)
          .eq('user_email', user.email)
          .maybeSingle();

        if (permError) {
          console.error('[BusinessAuth] Error fetching section permissions:', permError);
        }

        setBusinessUser(businessUserData as BusinessUser);
        setSectionPermissions((permData?.access_sections as SectionPermissions) || {});
        
      } catch (error) {
        console.error('[BusinessAuth] Error:', error);
      } finally {
        setLoading(false);
      }
    };
    
    fetchAllData();
  }, [user?.email, user?.id, company?.id]);

  const fetchBusinessUser = async () => {
    try {
      const { data, error } = await supabase
        .from('company_users')
        .select('id, user_id, email, username, access_type, company_id, full_name, designation, status')
        .eq('user_id', user?.id)
        .eq('company_id', company?.id)
        .maybeSingle();

      if (error) {
        console.error('[BusinessAuth] Error refetching business user:', error);
      } else {
        setBusinessUser(data as BusinessUser);
      }
    } catch (error) {
      console.error('[BusinessAuth] Business user refetch error:', error);
    }
  };

  const getEffectiveRole = (): 'OWNER' | 'ADMIN' | 'MANAGER' | 'STAFF' | 'USER' => {
    return businessUser?.access_type || 'USER';
  };

  const hasAccess = (section: string): boolean | undefined => {
    // Return undefined during loading to indicate "don't know yet"
    if (loading) return undefined;
    
    // Only check section permissions after loading completes
    return sectionPermissions[section] === 'read' || sectionPermissions[section] === 'edit';
  };

  const hasEditAccess = (section: string): boolean | undefined => {
    // Return undefined during loading to indicate "don't know yet"
    if (loading) return undefined;
    
    // Special handling for company_profile - OWNER and ADMIN always have access
    if (section === 'company_profile') {
      const role = businessUser?.access_type;
      if (role === 'OWNER' || role === 'ADMIN') {
        return true;
      }
    }
    
    // Only check section permissions after loading completes
    return sectionPermissions[section] === 'edit';
  };

  const canPerformAction = (section: string, action: 'read' | 'edit'): boolean | undefined => {
    if (action === 'read') {
      return hasAccess(section);
    }
    return hasEditAccess(section);
  };

  const isOwnerOrAdmin = (): boolean => {
    const effectiveRole = getEffectiveRole();
    return effectiveRole === 'OWNER' || effectiveRole === 'ADMIN';
  };

  const canManageUsers = (): boolean => {
    const effectiveRole = getEffectiveRole();
    return effectiveRole === 'OWNER' || effectiveRole === 'ADMIN';
  };

  const canManageRoles = (targetRole: 'owner' | 'admin' | 'manager' | 'staff'): boolean => {
    const effectiveRole = getEffectiveRole();
    
    // Only owners can create other owners
    if (targetRole === 'owner') {
      return effectiveRole === 'OWNER';
    }
    
    // Owners and admins can manage other roles below them
    if (targetRole === 'admin') {
      return effectiveRole === 'OWNER';
    }
    
    if (targetRole === 'manager' || targetRole === 'staff') {
      return effectiveRole === 'OWNER' || effectiveRole === 'ADMIN';
    }
    
    return false;
  };

  const canManageCompany = (): boolean => {
    return isOwnerOrAdmin();
  };

  const updateSectionPermissions = async (userEmail: string, permissions: SectionPermissions) => {
    if (!company?.id) return;

    try {
      const { error } = await supabase
        .from('company_user_section_permissions')
        .upsert({
          company_id: company.id,
          user_email: userEmail,
          access_sections: permissions
        }, {
          onConflict: 'company_id,user_email'
        });

      if (error) throw error;
      
      // Refresh permissions if updating current user
      if (userEmail === user?.email) {
        setSectionPermissions(permissions);
      }
    } catch (error) {
      console.error('Error updating section permissions:', error);
      throw error;
    }
  };

  return {
    businessUser,
    sectionPermissions,
    loading,
    hasAccess,
    hasEditAccess,
    canPerformAction,
    isOwnerOrAdmin,
    canManageCompany,
    canManageUsers,
    canManageRoles,
    getEffectiveRole,
    updateSectionPermissions,
    refetch: fetchBusinessUser
  };
};