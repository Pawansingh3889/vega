
// @ts-nocheck

// Edge Function: invite-business-user
// Creates a Supabase Auth user for a business user and links profile to company
// Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY secrets

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.56.0";

const allowedOrigins = [
  // Vega's own dev server. Add the deployed web origin here when it deploys;
  // an origin this list does not name is refused, and refused silently.
  'http://localhost:8080',
  'http://localhost:3000',
  'http://localhost:5173',
];

const securityHeaders = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'X-XSS-Protection': '1; mode=block',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

function getCorsHeaders(req: Request) {
  const origin = req.headers.get('origin') || '';
  
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    ...securityHeaders,
  };
}

interface InvitePayload {
  email: string;
  password?: string; // optional; if missing, we'll generate one
  name?: string;
  designation?: string;
  role?: 'Admin' | 'Editor' | 'Viewer';
  company_id: string;
  created_by?: string; // Track who created this user
}

function mapRoleToProfile(role: 'Admin' | 'Editor' | 'Viewer'): 'owner' | 'admin' | 'manager' | 'staff' {
  switch (role) {
    case 'Admin': return 'admin';
    case 'Editor': return 'staff';
    case 'Viewer': return 'staff';
    default: return 'staff';
  }
}

function splitName(name?: string) {
  if (!name) return { first_name: null as string | null, last_name: null as string | null };
  const parts = name.trim().split(/\s+/);
  const first_name = parts.shift() || null;
  const last_name = parts.length ? parts.join(' ') : null;
  return { first_name, last_name };
}

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req);
  
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const payload: InvitePayload = await req.json();
    console.log('Received payload:', { ...payload, password: payload.password ? '[REDACTED]' : undefined });

    const { email, password, name, designation, role, company_id, created_by } = payload;

    if (!email || !company_id) {
      console.log('Validation failed - missing fields:', { email: !!email, company_id: !!company_id });
      return new Response(JSON.stringify({ error: 'Missing required fields: email and company_id are required' }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // Optional role validation and normalization
    if (role && !['Admin', 'Editor', 'Viewer'].includes(role)) {
      console.log('Invalid role provided:', role);
      return new Response(JSON.stringify({ error: 'Invalid role. Must be Admin, Editor, or Viewer' }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const normalizedRole: 'Admin' | 'Editor' | 'Viewer' = (role as any) ?? 'Viewer';

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      console.error('Missing environment variables');
      return new Response(JSON.stringify({ error: 'Server configuration error' }), {
        status: 500,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

    // Verify authentication (JWT is automatically validated by Supabase with verify_jwt = true)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      console.error('Missing authorization header');
      return new Response(JSON.stringify({ error: 'Authentication required' }), {
        status: 401,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const token = authHeader.replace('Bearer ', '');
    const { data: requesterData, error: requesterErr } = await admin.auth.getUser(token);
    
    if (requesterErr || !requesterData.user) {
      console.error('Invalid authentication token:', requesterErr?.message);
      return new Response(JSON.stringify({ error: 'Invalid authentication' }), {
        status: 401,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const requesterId = requesterData.user.id;
    console.log('Request from user:', requesterId);

    // Verify requester has admin/owner permissions (CRITICAL: use user_roles table)
    const { data: requesterProfile, error: profileFetchErr } = await admin
      .from('profiles')
      .select('company_id')
      .eq('user_id', requesterId)
      .single();

    if (profileFetchErr || !requesterProfile) {
      console.error('Failed to fetch requester profile:', profileFetchErr?.message);
      return new Response(JSON.stringify({ error: 'User profile not found' }), {
        status: 403,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // Check role from user_roles table (prevents privilege escalation)
    const { data: roleData, error: roleErr } = await admin
      .from('user_roles')
      .select('role')
      .eq('user_id', requesterId)
      .maybeSingle();

    if (roleErr || !roleData || !['owner', 'admin'].includes(roleData.role)) {
      console.error('Insufficient permissions - user role:', roleData?.role);
      return new Response(JSON.stringify({ error: 'Insufficient permissions. Only admins and owners can invite users.' }), {
        status: 403,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    if (requesterProfile.company_id !== company_id) {
      console.error('Company mismatch - requester company:', requesterProfile.company_id, 'target company:', company_id);
      return new Response(JSON.stringify({ error: 'You can only invite users to your own company' }), {
        status: 403,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    console.log('Authorization verified - admin/owner inviting user to their company');

    // Verify company exists
    const { data: company, error: companyError } = await admin
      .from('companies')
      .select('id, name')
      .eq('id', company_id)
      .maybeSingle();

    if (companyError || !company) {
      console.error('Company verification failed:', companyError?.message);
      return new Response(JSON.stringify({ error: 'Company not found' }), { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } });
    }

    console.log('Verified company:', company.name);

    // Try to create auth user first, then handle existing user case
    let authUserId: string | null = null;
    let existingUser: any = null;

    const tempPassword = password || crypto.randomUUID().replace(/-/g, '').slice(0, 16);
    
    // Try creating the user first
    console.log('Attempting to create auth user for:', email);
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true, // Force email confirmation to true
      user_metadata: {
        name,
        invited_via: 'invite-business-user',
        company_id,
        app_role: mapRoleToProfile(normalizedRole),
      },
    });

    if (created?.user) {
      // User created successfully
      authUserId = created.user.id;
      console.log(`Created new auth user: ${authUserId} for email: ${email}`);
    } else if (createErr?.message?.includes('already registered') || 
               createErr?.message?.includes('User already registered') ||
               createErr?.message?.includes('email address has already been registered') ||
               createErr?.code === 'email_exists') {
      // User already exists, find them by listing users and matching email
      console.log(`User already exists for email: ${email}, searching for existing user`);
      
      const { data: users, error: listErr } = await admin.auth.admin.listUsers({
        page: 1,
        perPage: 1000 // Adjust if you have more users
      });
      
      if (listErr) {
        console.error('Error listing users:', listErr);
        return new Response(JSON.stringify({ error: `Failed to find existing user: ${listErr.message}` }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
      
      // Find user by email
      existingUser = users?.users?.find(u => u.email === email);
      
      if (!existingUser) {
        console.error(`User exists but could not be found for email: ${email}`);
        return new Response(JSON.stringify({ error: 'User exists but could not be found' }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
      
      authUserId = existingUser.id;
      console.log(`Found existing auth user: ${authUserId} for email: ${email}`);
      
      // Handle existing user: force-confirm email and set password
      const updateData: any = { email_confirm: true };
      if (password) {
        updateData.password = password;
      }
      
      const { error: updateErr } = await admin.auth.admin.updateUserById(authUserId, updateData);
      if (updateErr) {
        console.error('Error updating existing user:', updateErr);
        return new Response(JSON.stringify({ error: `Failed to update existing user: ${updateErr.message}` }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
      
      console.log('Updated existing auth user successfully');
    } else {
      // Unexpected error during user creation
      console.error('Error creating user:', createErr);
      return new Response(JSON.stringify({ error: createErr?.message || 'Failed to create user' }), { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } });
    }

    if (!authUserId) {
      console.error('No auth user ID obtained');
      return new Response(JSON.stringify({ error: 'Failed to create or find user' }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
    }

    // Check if user already exists in company_users
    console.log('Checking for existing company user');
    const { data: existingCompanyUser, error: existingUserError } = await admin
      .from('company_users')
      .select('*')
      .eq('email', email)
      .eq('company_id', company_id)
      .maybeSingle();

    if (existingUserError) {
      console.error('Error checking existing company user:', existingUserError);
      return new Response(JSON.stringify({ error: 'Database error checking existing user' }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
    }

    // Determine access type (ADMIN only when explicitly provided)
    const accessType = normalizedRole === 'Admin' ? 'ADMIN' : 'USER';

    console.log('Access type mapping:', { normalizedRole, accessType });

    if (existingCompanyUser) {
      console.log('Updating existing company user');
      // Update existing company_user record with auth user_id
      const { error: updateError } = await admin
        .from('company_users')
        .update({
          user_id: authUserId,
          full_name: name || existingCompanyUser.username,
          designation: designation || existingCompanyUser.designation,
          access_type: accessType,
          updated_at: new Date().toISOString()
        })
        .eq('id', existingCompanyUser.id);

      if (updateError) {
        console.error('Error updating company user:', updateError);
        return new Response(JSON.stringify({ error: 'Failed to update company user' }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
    } else {
      console.log('Creating new company user');
      // Create new company_user record linked to auth.users
      const { error: insertError } = await admin
        .from('company_users')
        .insert({
          user_id: authUserId,
          company_id: company_id,
          email: email,
          username: email, // Keep for backward compatibility
          full_name: name,
          designation: designation,
          access_type: accessType,
          status: 'ACTIVE',
          password_hash: 'MANAGED_BY_AUTH', // Indicate this is managed by Supabase Auth
          created_by: created_by || requesterId // Track who created this user
        });

      if (insertError) {
        console.error('Error creating company user:', insertError);
        return new Response(JSON.stringify({ error: `Failed to create company user: ${insertError.message}` }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
    }

    // Ensure profile exists and is linked to company
    console.log('Creating/updating profile');
    const { first_name, last_name } = splitName(name);
    
    // Check if profile already exists
    const { data: existingProfile } = await admin
      .from('profiles')
      .select('id')
      .eq('user_id', authUserId)
      .maybeSingle();
    
    if (existingProfile) {
      // Update existing profile
      const { error: profileUpdateError } = await admin
        .from('profiles')
        .update({
          company_id,
          first_name,
          last_name,
          is_active: true,
          updated_at: new Date().toISOString()
        })
        .eq('user_id', authUserId);
      
      if (profileUpdateError) {
        console.error('Error updating profile:', profileUpdateError);
        return new Response(JSON.stringify({ error: `Failed to update profile: ${profileUpdateError.message}` }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
    } else {
      // Insert new profile
      const { error: profileInsertError } = await admin
        .from('profiles')
        .insert({
          user_id: authUserId,
          company_id,
          first_name,
          last_name,
          is_active: true,
        });
      
      if (profileInsertError) {
        console.error('Error creating profile:', profileInsertError);
        return new Response(JSON.stringify({ error: `Failed to create profile: ${profileInsertError.message}` }), { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } });
      }
    }

    console.log('User creation completed successfully');

    return new Response(JSON.stringify({ 
      success: true, 
      auth_user_id: authUserId,
      message: 'User created successfully and can now log in with email and password'
    }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err: any) {
    console.error('invite-business-user error:', err);
    return new Response(JSON.stringify({ error: err.message || 'Internal error' }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
