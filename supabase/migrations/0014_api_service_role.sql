-- The service's own database role, which owns nothing.
--
-- SECURITY.md N2: a table owner bypasses RLS unless FORCE ROW LEVEL SECURITY is
-- set, so the FastAPI role must never own a table and the migration role must
-- never linger in the application's connection string. This creates that role.
--
-- HOW THE SERVICE ACTS. It does not read as itself. A probe confirmed a custom
-- role sees zero rows even with an explicit GRANT SELECT, because every policy
-- in this schema names `authenticated`. Rather than weaken the policies or hand
-- the service BYPASSRLS, the service impersonates: it connects as vega_api and
-- then, per request, does
--
--     SET LOCAL ROLE authenticated;
--     SELECT set_config('request.jwt.claim.sub', <user id>, true);
--     SELECT set_config('request.headers', '{"x-vega-company":"..."}', true);
--
-- which is exactly what PostgREST does. One policy set governs both paths, and
-- the tenant isolation suite already covers it. GRANT authenticated TO vega_api
-- below is what makes SET ROLE possible.
--
-- NO PASSWORD HERE. The role is created NOLOGIN. scripts/provision-api-role.sh
-- reads the password from pass and enables login, so the credential never
-- enters git and this migration stays reviewable.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vega_api') THEN
    CREATE ROLE vega_api NOLOGIN;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO vega_api;

-- The only privilege it needs of its own. Everything else is reached by
-- becoming `authenticated` for the duration of a request.
GRANT authenticated TO vega_api;

-- Reference data the service reads without a user: VAT rates when deriving a
-- return, FX rates when writing one. Read-only, and RLS still applies.
GRANT SELECT ON public.vat_treatments, public.vat_rates TO vega_api;
-- The FX ingestion job is the one thing the service writes as itself, because
-- no user is present when it runs.
GRANT SELECT, INSERT ON public.fx_rates TO vega_api;

-- Reference tables are readable by any signed-in user; the service needs the
-- same reach when acting without one.
CREATE POLICY "Service role reads vat_treatments" ON public.vat_treatments
  FOR SELECT TO vega_api USING (true);
CREATE POLICY "Service role reads vat_rates" ON public.vat_rates
  FOR SELECT TO vega_api USING (true);
CREATE POLICY "Service role reads fx_rates" ON public.fx_rates
  FOR SELECT TO vega_api USING (true);
CREATE POLICY "Service role appends fx_rates" ON public.fx_rates
  FOR INSERT TO vega_api WITH CHECK (true);

-- N2, asserted rather than assumed: this role owns nothing, now or ever.
DO $$
DECLARE owned text;
BEGIN
  SELECT string_agg(c.relname, ', ') INTO owned
    FROM pg_class c
    JOIN pg_roles r ON r.oid = c.relowner
   WHERE r.rolname = 'vega_api';
  IF owned IS NOT NULL THEN
    RAISE EXCEPTION 'vega_api owns objects, which defeats RLS: %', owned;
  END IF;
END
$$;
