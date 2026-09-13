import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { Resend } from "https://esm.sh/resend@2.0.0";

const resend = new Resend(Deno.env.get("RESEND_API_KEY"));

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'X-XSS-Protection': '1; mode=block',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

interface SendOtpRequest {
  email: string;
  purpose: string;
}

// Helper function to generate 6-digit OTP
function generateOTP(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// Helper function to hash OTP
async function hashOTP(otp: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(otp);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
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
    console.log('Received request to send-otp function');
    const { email, purpose }: SendOtpRequest = await req.json();
    console.log('Request details:', { email, purpose });

    if (!email || !purpose) {
      console.error('Missing email or purpose');
      return new Response(
        JSON.stringify({ error: "Email and purpose are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client with service role key
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Check if email is already registered (only for business_registration)
    if (purpose === 'business_registration') {
      const { data: existingRequest, error: checkError } = await supabase
        .from("business_registration_requests")
        .select("id, status")
        .eq("email", email)
        .limit(1)
        .maybeSingle();

      if (checkError) {
        console.error('Database check error:', checkError);
      } else if (existingRequest) {
        const message = existingRequest.status === 'pending' 
          ? 'This email has a pending registration request'
          : 'This email is already registered';
        
        return new Response(
          JSON.stringify({ 
            error: message,
            status: existingRequest.status
          }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Check rate limiting - max 3 OTPs per hour per email
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { data: recentOtps, error: countError } = await supabase
      .from("email_otps")
      .select("id")
      .eq("email", email)
      .gte("created_at", oneHourAgo);

    if (countError) {
      console.error("Rate limit check error:", countError);
      return new Response(
        JSON.stringify({ error: "Failed to check rate limits" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (recentOtps && recentOtps.length >= 3) {
      // Log security event for rate limit hit
      await supabase.from('security_audit_log').insert({
        action: 'otp_rate_limit_exceeded',
        details: { email, attempt_count: recentOtps.length },
        ip_address: req.headers.get('x-forwarded-for') || 'unknown',
        severity: 'medium'
      });
      
      return new Response(
        JSON.stringify({ error: "Too many OTP requests. Please try again in an hour." }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Generate OTP and hash it
    const otp = generateOTP();
    const otpHash = await hashOTP(otp);

    // Store OTP in database (expires in 3 minutes)
    const expiresAt = new Date(Date.now() + 3 * 60 * 1000).toISOString();
    const { error: insertError } = await supabase
      .from("email_otps")
      .insert({
        email,
        otp_hash: otpHash,
        expires_at: expiresAt,
        attempt_count: 0
      });

    if (insertError) {
      console.error("OTP storage error:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to generate OTP" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Send OTP via Resend
    try {
      const emailHtml = `
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background-color: #4F46E5; color: white; padding: 20px; text-align: center; }
              .content { background-color: #f9fafb; padding: 30px; border-radius: 8px; margin: 20px 0; }
              .otp-code { font-size: 32px; font-weight: bold; letter-spacing: 8px; text-align: center; 
                          background-color: white; padding: 20px; border-radius: 8px; 
                          border: 2px solid #4F46E5; color: #4F46E5; margin: 20px 0; }
              .warning { background-color: #FEF3C7; padding: 15px; border-radius: 6px; margin: 20px 0; }
              .footer { text-align: center; color: #6B7280; font-size: 14px; margin-top: 20px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>Verification Code</h1>
              </div>
              <div class="content">
                <p>Hello,</p>
                <p>Your verification code is:</p>
                <div class="otp-code">${otp}</div>
                <div class="warning">
                  <strong>⏰ This code expires in 3 minutes</strong>
                </div>
                <p>Enter this code to complete your ${purpose} verification.</p>
                <p>If you didn't request this code, please ignore this email.</p>
              </div>
              <div class="footer">
                <p>This is an automated message, please do not reply.</p>
              </div>
            </div>
          </body>
        </html>
      `;

      const { data: emailData, error: emailError } = await resend.emails.send({
        from: 'Verification <onboarding@resend.dev>',
        to: [email],
        subject: 'Your Verification Code',
        html: emailHtml,
      });

      if (emailError) {
        console.error("Resend email error:", emailError);
        throw emailError;
      }

      console.log("Email sent successfully via Resend:", emailData);
      
      // Log successful OTP generation
      await supabase.from('security_audit_log').insert({
        action: 'otp_sent',
        details: { email, purpose, email_id: emailData?.id },
        ip_address: req.headers.get('x-forwarded-for') || 'unknown',
        severity: 'low'
      });
    } catch (emailError) {
      console.error("Email sending error:", emailError);
      return new Response(
        JSON.stringify({ error: "Failed to send email" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: "OTP sent successfully. Please check your email.",
        expiresIn: 180 // 3 minutes in seconds
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Send OTP error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});