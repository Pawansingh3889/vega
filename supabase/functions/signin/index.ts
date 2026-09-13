// Resolve a Business ID and username to the email GoTrue knows.
//
// That is ALL this does, and the narrowness is the point. The version this
// replaces verified the password itself, against `company_users.password_hash`,
// and its final fallback was:
//
//     return providedPassword === storedPasswordHash;
//
// a plain string comparison against whatever the column held. `seed.sql` stores
// the literal 'managed-by-gotrue' there, precisely because passwords are NOT
// kept in that column, so typing `managed-by-gotrue` satisfied this function.
// Only supabase.auth.signInWithPassword() on the next line in Signin.tsx
// stopped the request, and a check that is always backstopped by another check
// is not a check.
//
// Passwords live in GoTrue and are verified by GoTrue. This function never
// receives one, so there is nothing here to compare, log or leak.

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

// The dev server and whatever the app is served from. The previous file built
// this list and then never used it: getCorsHeaders returned `origin || '*'`,
// reflecting any origin that asked. An allowlist that is defined and ignored is
// worse than none, because it reads as protection in review.
const ALLOWED_ORIGINS = [
  "http://localhost:8080",
  "http://127.0.0.1:8080",
];

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "geolocation=(), microphone=(), camera=()",
} as const;

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
    ...SECURITY_HEADERS,
  };
  // Only echo an origin that is actually on the list. An unlisted origin gets
  // no ACAO header at all, and the browser refuses the response, which is the
  // behaviour the list was written for.
  if (ALLOWED_ORIGINS.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

// VG-0000-MM-YYYY, the shape generate_business_ref_no() builds (migration 0011).
const BUSINESS_REF = /^VG-\d{4}-\d{2}-\d{4}$/;

// Letters, digits, dot, dash, underscore. Anything else is refused rather than
// escaped, because this value reaches a PostgREST filter. The previous file
// interpolated it straight into
// `.or(`username.ilike.${name},email.ilike.${name}`)`, where a comma or a
// bracket rewrites the filter and a bare `*` matches every user.
const USERNAME = /^[A-Za-z0-9._-]{1,64}$/;

interface SigninRequest {
  businessRefNo?: unknown;
  username?: unknown;
}

serve(async (req: Request): Promise<Response> => {
  const cors = corsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  // One refusal for every "we will not tell you why" case. Whether the business
  // exists, whether the username exists, and whether the two go together are
  // all the same answer, so this endpoint cannot be used to enumerate either.
  const refuse = () =>
    new Response(JSON.stringify({ success: false, error: "Invalid credentials" }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  try {
    const body = (await req.json()) as SigninRequest;
    const businessRefNo = typeof body.businessRefNo === "string" ? body.businessRefNo.trim() : "";
    const username = typeof body.username === "string" ? body.username.trim() : "";

    if (!BUSINESS_REF.test(businessRefNo) || !USERNAME.test(username)) {
      return refuse();
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Scoped to the company, which the previous version did not do: it filtered
    // on username alone, so the Business ID the form collects and validates was
    // never used. Two companies each with a user called `admin` matched two
    // rows, .single() failed, and both were told their credentials were wrong.
    const { data, error } = await supabase
      .from("company_users")
      .select("id, email, status, companies!inner(id, business_ref_no, status)")
      .eq("companies.business_ref_no", businessRefNo)
      .ilike("username", username)
      .maybeSingle();

    if (error !== null || data === null) {
      return refuse();
    }
    if (data.status !== "ACTIVE") {
      return new Response(
        JSON.stringify({
          success: false,
          blocked: true,
          error: "This account is blocked. Please contact your administrator.",
        }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } },
      );
    }

    const company = Array.isArray(data.companies) ? data.companies[0] : data.companies;
    if (company === undefined || company.status !== "active") {
      return refuse();
    }

    return new Response(
      JSON.stringify({
        success: true,
        user: { id: data.id, email: data.email },
        company: {
          id: company.id,
          businessRefNo: company.business_ref_no,
          status: company.status,
        },
      }),
      { status: 200, headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (error) {
    // Never the caught value. It can carry the request body, and the request
    // body is why this endpoint exists.
    console.error("signin: unhandled error", error instanceof Error ? error.message : "unknown");
    return new Response(JSON.stringify({ success: false, error: "Internal server error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
