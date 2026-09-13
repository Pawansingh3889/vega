import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ApproveRegistrationRequest {
  requestId: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Verify the user is a super admin
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      console.error("Auth error:", authError);
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Check if user is super admin
    if (user.email !== 'rigelenterpriseinfo@gmail.com') {
      console.log(`Non-super-admin attempted approval: ${user.email}`);
      return new Response(
        JSON.stringify({ error: "Forbidden: Super admin access required" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { requestId }: ApproveRegistrationRequest = await req.json();

    if (!requestId) {
      return new Response(
        JSON.stringify({ error: "Request ID is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get the registration request
    const { data: request, error: fetchError } = await supabase
      .from("business_registration_requests")
      .select("*")
      .eq("id", requestId)
      .single();

    if (fetchError || !request) {
      console.error("Request fetch error:", fetchError);
      return new Response(
        JSON.stringify({ error: "Registration request not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (request.status !== 'pending') {
      return new Response(
        JSON.stringify({ error: `Request already ${request.status}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create the company
    const { data: companyData, error: companyError } = await supabase
      .from("companies")
      .insert({
        name: request.business_name,
        email: request.email,
        phone: request.phone,
        address_line1: request.address_line1,
        address_line2: request.address_line2,
        state: request.state,
        postcode: request.postcode,
        country: request.country,
        vat_number: request.vat_number,
        status: 'active',
        subscription_status: 'trial'
      })
      .select()
      .single();

    if (companyError) {
      console.error("Company creation error:", companyError);
      return new Response(
        JSON.stringify({ error: "Failed to create company" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create the admin user
    const { error: userError } = await supabase
      .from("company_users")
      .insert({
        company_id: companyData.id,
        // admin_details is a jsonb blob on the request row, not three columns.
        username: request.admin_details?.username,
        email: request.email,
        password_hash: request.admin_details?.password_hash,
        access_type: 'OWNER',
        status: 'ACTIVE'
      });

    if (userError) {
      console.error("User creation error:", userError);
      // Rollback company creation
      await supabase.from("companies").delete().eq("id", companyData.id);
      
      return new Response(
        JSON.stringify({ error: "Failed to create admin user" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update registration request status
    const { error: updateError } = await supabase
      .from("business_registration_requests")
      .update({
        status: 'approved',
        // The table records a review, not an approval specifically: the same
        // two columns carry a rejection. reviewed_by/reviewed_at and
        // created_company_id are the real names; approved_* and company_id
        // never existed, so this update silently wrote nothing that stuck.
        reviewed_at: new Date().toISOString(),
        reviewed_by: user.id,
        created_company_id: companyData.id
      })
      .eq("id", requestId);

    if (updateError) {
      console.error("Request update error:", updateError);
    }

    console.log(`Registration approved by ${user.email} for company: ${companyData.business_ref_no}`);

    return new Response(
      JSON.stringify({ 
        success: true,
        companyId: companyData.id,
        businessRefNo: companyData.business_ref_no,
        message: "Registration approved successfully"
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Approve registration error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
