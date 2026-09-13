-- Restrict auth_rate_limits to service_role.
--
-- The inherited migrations 20250823112326 and 20250823112352 both create:
--
--   CREATE POLICY "Anyone can check rate limits"
--   ON public.auth_rate_limits FOR SELECT USING (true);
--
-- No later migration drops it, and migration 344 fixed only the lockout upsert's
-- index. A rebuild from migrations alone therefore ships a table holding
-- hashed_email, ip_address, attempt_count and blocked_until readable by anon:
-- hash a candidate address, look it up, and the public key becomes an account
-- existence oracle plus a live feed of who is locked out.
--
-- Fixing the lockout makes this worse rather than better. Before migration 344
-- the table stayed empty because no attempt was ever recorded, so the oracle had
-- nothing to leak. A working lockout fills it.
--
-- Only the service role touches this table. Nothing in the client needs to read
-- it: the rate limit decision is made server side by the sign-in function.

-- The public read policy, created by 20250823112326 and 20250823112352.
DROP POLICY IF EXISTS "Anyone can check rate limits" ON public.auth_rate_limits;

-- An untargeted FOR ALL USING (true) from 20250823112438, superseded by the
-- service_role policy a later migration added. Dropped so one rule governs this
-- table rather than three of overlapping reach.
DROP POLICY IF EXISTS "System can manage rate limits" ON public.auth_rate_limits;

ALTER TABLE public.auth_rate_limits ENABLE ROW LEVEL SECURITY;

-- "Service role can manage rate limits" already exists and is correct, so this
-- migration deliberately does not add a second one. Two identical policies read as
-- two rules and get maintained as two. Assert it is there instead.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'auth_rate_limits'
      AND roles::text = '{service_role}'
      AND cmd = 'ALL'
  ) THEN
    CREATE POLICY "Service role can manage rate limits"
      ON public.auth_rate_limits
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END
$$;

-- The rate limit decision is made server side by the sign-in function, so nothing
-- in the client needs to reach this table at all. Remove the grants as well as the
-- policy: dropping a policy leaves the grant standing for the next policy someone
-- adds carelessly.
REVOKE ALL ON public.auth_rate_limits FROM anon, authenticated;
