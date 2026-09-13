-- Make the failed-login lockout actually record attempts.
--
-- supabase/functions/signin upserts into auth_rate_limits with
-- ON CONFLICT (hashed_email), but 20250929210816 created only a plain btree
-- index on that column when it replaced the plaintext email column. Postgres
-- rejects the upsert with 42P10 ("no unique or exclusion constraint matching
-- the ON CONFLICT specification"), PostgREST turns that into a 400, and the
-- function discarded the error. The result: no attempt was ever recorded and
-- the 15 minute block never fired.

-- Collapse duplicates before the unique index, keeping the most recent attempt
-- per identifier. Rate-limit counters are ephemeral, so the older rows carry
-- nothing worth preserving. Rows with a NULL hashed_email predate the column
-- and are left alone: a plain unique index treats NULLs as distinct.
DELETE FROM public.auth_rate_limits a
USING public.auth_rate_limits b
WHERE a.hashed_email IS NOT NULL
  AND a.hashed_email = b.hashed_email
  AND (a.last_attempt, a.id) < (b.last_attempt, b.id);

DROP INDEX IF EXISTS public.idx_auth_rate_limits_hashed_email;

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_rate_limits_hashed_email
  ON public.auth_rate_limits (hashed_email);
