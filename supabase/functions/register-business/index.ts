import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RegisterBusinessRequest {
  businessDetails: {
    name: string;
    email: string;
    phone: string;
    addrLine1: string;
    addrLine2?: string;
    state: string;
    pinCode: string;
    country: string;
    businessType: string;
    industryType: string;
    gstin?: string;
  };
  username: string;
  password: string;
}

// Helper function to hash password
async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

// Validation functions
function validateUsername(username: string): boolean {
  const regex = /^[A-Za-z][A-Za-z0-9._]{3,19}$/;
  return regex.test(username);
}

function validatePassword(password: string): boolean {
  // At least 8 characters, includes uppercase, lowercase, number, symbol
  const regex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$/;
  return regex.test(password);
}

function validateEmail(email: string): boolean {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return regex.test(email);
}

function validatePhone(phone: string): boolean {
  // E.164 format validation (simplified)
  const regex = /^\+[1-9]\d{1,14}$/;
  return regex.test(phone);
}

// UK VAT registration numbers, not GSTINs. The standard form is GB followed by
// 9 digits; branch traders add a 3-digit suffix; government departments and
// health authorities use the GD and HA forms. The GB prefix is optional in
// everyday use, so it is accepted either way.
//
// Format only. Whether the number is real and belongs to this business is a
// VIES question, and SPEC.md 4.1 puts that in Phase 4.
function validateVatNumber(vatNumber: string): boolean {
  if (!vatNumber) return true; // Optional field
  const value = vatNumber.replace(/[\s-]/g, "").toUpperCase();
  return (
    /^(GB)?\d{9}$/.test(value) ||       // standard
    /^(GB)?\d{12}$/.test(value) ||      // branch trader
    /^(GB)?GD\d{3}$/.test(value) ||     // government department
    /^(GB)?HA\d{3}$/.test(value)        // health authority
  );
}

function validateGSTIN(gstin: string): boolean {
  if (!gstin) return true; // Optional field
  const regex = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[Z]{1}[0-9A-Z]{1}$/;
  return regex.test(gstin) && gstin.length === 15;
}

// Sanitize string input (prevents injection attacks)
function sanitizeString(input: string): string {
  return input.trim().replace(/[<>\"']/g, '');
}

// Validate business details structure to prevent JSONB injection
function validateBusinessDetails(details: any): boolean {
  // Ensure all expected fields are present and have correct types
  const requiredFields = ['name', 'email', 'phone', 'addrLine1', 'state', 'pinCode', 'country', 'businessType', 'industryType'];
  
  for (const field of requiredFields) {
    if (!details[field] || typeof details[field] !== 'string') {
      return false;
    }
    // Check for reasonable length limits
    if (details[field].length > 255) {
      return false;
    }
  }
  
  // Optional fields validation
  if (details.addrLine2 && typeof details.addrLine2 !== 'string') {
    return false;
  }
  
  // Ensure no unexpected fields (prevent JSONB injection)
  const allowedFields = ['name', 'email', 'phone', 'addrLine1', 'addrLine2', 'state', 'pinCode', 'country', 'businessType', 'industryType', 'gstin'];
  const providedFields = Object.keys(details);
  const unexpectedFields = providedFields.filter(f => !allowedFields.includes(f));
  
  if (unexpectedFields.length > 0) {
    console.warn('Unexpected fields in business details:', unexpectedFields);
    return false;
  }
  
  return true;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const { businessDetails, username, password }: RegisterBusinessRequest = await req.json();

    // Validate required fields
    if (!businessDetails || !username || !password) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate business details structure (prevent JSONB injection)
    if (!validateBusinessDetails(businessDetails)) {
      return new Response(
        JSON.stringify({ error: "Invalid business details structure" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate business details
    const {
      name, email, phone, addrLine1, state, pinCode, country,
      businessType, industryType, gstin, addrLine2
    } = businessDetails;

    if (!name || !email || !phone || !addrLine1 || !state || !pinCode || 
        !country || !businessType || !industryType) {
      return new Response(
        JSON.stringify({ error: "Missing required business details" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate formats
    if (!validateUsername(username)) {
      return new Response(
        JSON.stringify({ error: "Invalid username format. Must be 4-20 characters, start with letter, contain only letters, numbers, dots, and underscores." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!validatePassword(password)) {
      return new Response(
        JSON.stringify({ error: "Password must be at least 8 characters with uppercase, lowercase, number, and special character." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!validateEmail(email)) {
      return new Response(
        JSON.stringify({ error: "Invalid email format" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!validatePhone(phone)) {
      return new Response(
        JSON.stringify({ error: "Invalid phone format. Use E.164 format (e.g., +1234567890)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!validateVatNumber(gstin || "")) {
      return new Response(
        JSON.stringify({ error: "Invalid GSTIN format" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client with service role key
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Check if registration request already exists for this email
    const { data: existingRequest, error: checkError } = await supabase
      .from("business_registration_requests")
      .select("id, status")
      .eq("email", email)
      .limit(1);

    if (checkError) {
      console.error("Registration check error:", checkError);
      return new Response(
        JSON.stringify({ error: "Registration validation failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (existingRequest && existingRequest.length > 0) {
      const status = existingRequest[0].status;
      if (status === 'pending') {
        return new Response(
          JSON.stringify({ error: "A registration request with this email is already pending approval" }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      } else if (status === 'approved') {
        return new Response(
          JSON.stringify({ error: "This business is already registered. Please use the sign-in page." }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Hash password
    const passwordHash = await hashPassword(password);

    // Sanitize all string inputs before storage
    const sanitizedData = {
      business_name: sanitizeString(name),
      email: sanitizeString(email),
      phone: sanitizeString(phone),
      address_line1: sanitizeString(addrLine1),
      address_line2: addrLine2 ? sanitizeString(addrLine2) : null,
      city: sanitizeString(state), // Using state as city for now
      state: sanitizeString(state),
      postcode: sanitizeString(pinCode),
      country: sanitizeString(country),
      vat_number: gstin ? sanitizeString(gstin) : null,
      business_type: sanitizeString(businessType),
      industry: sanitizeString(industryType),
      admin_details: {
        username: sanitizeString(username),
        password_hash: passwordHash
      },
      status: 'pending' as const
    };

    // Create registration request (pending super admin approval)
    const { data: requestData, error: requestError } = await supabase
      .from("business_registration_requests")
      .insert(sanitizedData)
      .select()
      .single();

    if (requestError) {
      console.error("Registration request creation error:", requestError);
      return new Response(
        JSON.stringify({ error: "Failed to submit registration request" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Log security event
    await supabase.from('security_audit_log').insert({
      action: 'business_registration_request',
      details: {
        request_id: requestData.id,
        business_name: sanitizedData.business_name,
        email: sanitizedData.email
      },
      ip_address: req.headers.get('x-forwarded-for') || 'unknown',
      severity: 'low'
    });

    return new Response(
      JSON.stringify({ 
        success: true,
        requestId: requestData.id,
        message: "Registration request submitted successfully. Your request is pending approval."
      }),
      { status: 201, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Register business error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
