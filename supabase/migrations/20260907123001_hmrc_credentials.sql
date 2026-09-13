-- Where a company's HMRC connection lives.
--
-- NOT append-only, unlike hmrc_submissions, and the difference is deliberate.
-- A submission is a historical fact and must never change. A token is current
-- state: it is refreshed, and the old value is worthless and worth forgetting.
-- Making this append-only would keep every expired refresh token for ever,
-- which is a growing pile of credentials with no reason to exist.
--
-- THE TOKENS ARE CIPHERTEXT WHEN THEY ARRIVE. The service encrypts before the
-- value reaches Postgres, so the database never sees the key and a stolen
-- backup is useless on its own (#109 q3). That is why these are bytea and not
-- text: it is not a format detail, it is the whole point, and a text column
-- would invite somebody to write a plaintext value into it.
--
-- Nothing in SQL can decrypt these. Nothing should.

CREATE TABLE IF NOT EXISTS public.hmrc_credentials (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- One connection per company. HMRC issues tokens against a VRN, and a
    -- second row for the same company would be two identities filing as one.
    company_id               uuid NOT NULL UNIQUE REFERENCES public.companies(id),

    access_token_ciphertext  bytea NOT NULL,
    refresh_token_ciphertext bytea NOT NULL,
    access_token_expires_at  timestamptz NOT NULL,
    scope                    text NOT NULL,

    -- Sandbox tokens must never be mistaken for production ones. Same reasoning
    -- as hmrc_submissions.environment, and the two must agree at submit time.
    environment              text NOT NULL,

    connected_at             timestamptz NOT NULL DEFAULT now(),
    connected_by             uuid NOT NULL REFERENCES auth.users(id),
    refreshed_at             timestamptz,

    CONSTRAINT hmrc_credentials_environment_check
        CHECK (environment IN ('sandbox', 'production'))
);

COMMENT ON TABLE public.hmrc_credentials IS
  'HMRC OAuth tokens, encrypted by the service before they arrive. The database holds ciphertext and never the key. See #109 q3.';

-- N1. Deny by default, then a policy scoped to the caller's company.
ALTER TABLE public.hmrc_credentials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hmrc_credentials_read_own ON public.hmrc_credentials;
CREATE POLICY hmrc_credentials_read_own
    ON public.hmrc_credentials
    FOR SELECT
    TO authenticated
    USING (company_id = public.current_company_id());

-- The policy decides WHICH ROWS. The grants below decide WHICH COLUMNS, and
-- that is the part that matters here: a person may see that their company is
-- connected and when the token expires. They may never see the token itself,
-- not even encrypted, because ciphertext plus time is a target and there is no
-- reason for a browser to hold one.
REVOKE ALL ON public.hmrc_credentials FROM anon, authenticated;
GRANT SELECT (company_id, access_token_expires_at, scope, environment,
              connected_at, refreshed_at)
    ON public.hmrc_credentials TO authenticated;

-- The service reads and writes the whole row. It holds the key.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hmrc_credentials TO service_role;

-- Prove it, rather than assert it.
DO $$
DECLARE
    v_company uuid;
    v_user    uuid;
    v_refused boolean;
BEGIN
    INSERT INTO auth.users (id, email)
    VALUES (gen_random_uuid(), 'hmrc-cred-probe@example.invalid')
    RETURNING id INTO v_user;

    INSERT INTO public.companies (id, name)
    VALUES (gen_random_uuid(), 'hmrc credential probe')
    RETURNING id INTO v_company;

    INSERT INTO public.hmrc_credentials
        (company_id, access_token_ciphertext, refresh_token_ciphertext,
         access_token_expires_at, scope, environment, connected_by)
    VALUES
        (v_company, '\x00'::bytea, '\x01'::bytea,
         now() + interval '4 hours', 'read:vat write:vat', 'sandbox', v_user);

    -- A second connection for one company must be refused.
    v_refused := false;
    BEGIN
        INSERT INTO public.hmrc_credentials
            (company_id, access_token_ciphertext, refresh_token_ciphertext,
             access_token_expires_at, scope, environment, connected_by)
        VALUES
            (v_company, '\x02'::bytea, '\x03'::bytea,
             now() + interval '4 hours', 'read:vat', 'sandbox', v_user);
    EXCEPTION WHEN unique_violation THEN
        v_refused := true;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'a company was allowed two HMRC connections';
    END IF;

    -- An unknown environment must be refused.
    v_refused := false;
    BEGIN
        UPDATE public.hmrc_credentials SET environment = 'staging'
         WHERE company_id = v_company;
    EXCEPTION WHEN check_violation THEN
        v_refused := true;
    END;
    IF NOT v_refused THEN
        RAISE EXCEPTION 'an unknown HMRC environment was accepted';
    END IF;

    -- authenticated must not hold the token columns at all.
    IF EXISTS (
        SELECT 1 FROM information_schema.column_privileges
         WHERE table_schema = 'public'
           AND table_name = 'hmrc_credentials'
           AND grantee = 'authenticated'
           AND column_name IN ('access_token_ciphertext', 'refresh_token_ciphertext')
    ) THEN
        RAISE EXCEPTION 'authenticated was granted a token column';
    END IF;

    RAISE EXCEPTION 'probe-complete: rolling back';
EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM <> 'probe-complete: rolling back' THEN
            RAISE;
        END IF;
END;
$$;
