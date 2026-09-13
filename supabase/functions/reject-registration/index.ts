import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RejectRegistrationRequest {
  requestId: string;
  reason?: string;
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
      console.log(`Non-super-admin attempted rejection: ${user.email}`);
      return new Response(
        JSON.stringify({ error: "Forbidden: Super admin access required" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { requestId, reason }: RejectRegistrationRequest = await req.json();

    if (!requestId) {
      return new Response(
        JSON.stringify({ error: "Request ID is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get the registration request
    const { data: request, error: fetchError } = await supabase
      .from("business_registration_requests")
      .select("id, status, email")
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

    // Update registration request status
    const { error: updateError } = await supabase
      .from("business_registration_requests")
      .update({
        status: 'rejected',
        // Same two review columns as approval; rejected_* never existed.
        reviewed_at: new Date().toISOString(),
        reviewed_by: user.id,
        rejection_reason: reason || 'No reason provided'
      })
      .eq("id", requestId);

    if (updateError) {
      console.error("Request update error:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to reject registration" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Registration rejected by ${user.email} for: ${request.email}`);

    return new Response(
      JSON.stringify({ 
        success: true,
        message: "Registration rejected successfully"
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Reject registration error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
