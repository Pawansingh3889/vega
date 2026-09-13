-- Minimal Supabase-shaped shim so the project's migrations can replay on stock Postgres.
-- Covers only what the 227 migrations actually reference: the three PostgREST roles,
-- an auth schema with a users table, and the uuid/crypto helpers.

create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit password 'devlocal';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin nologin noinherit;
  end if;
end
$$;

grant anon, authenticated, service_role to authenticator;

create schema if not exists auth authorization supabase_auth_admin;
grant usage on schema auth to anon, authenticated, service_role;

-- Trimmed stand-in for auth.users: the columns the migrations reference.
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  encrypted_password text,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create or replace function auth.uid() returns uuid
  language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create or replace function auth.role() returns text
  language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.role', true), '')::text $$;

-- auth.jwt() returns the decoded JWT claims as jsonb. Three policies in the
-- inherited baseline read it, and without it the whole policy section of the
-- dump aborts, leaving tables created but RLS never enabled. Same contract as
-- Supabase's: the claims set by the request, empty object when unauthenticated.
create or replace function auth.jwt() returns jsonb
  language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), ''),
    '{}'
  )::jsonb
$$;

create or replace function auth.email() returns text
  language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.email', true), '')::text $$;

grant usage on schema public to anon, authenticated, service_role;

-- Supabase's default grants.
--
-- The baseline was dumped with --no-privileges, so it carries no GRANTs at all.
-- Without these, every query as anon or authenticated fails with insufficient
-- privilege, and an RLS test against that database proves nothing: it would be
-- denied for the wrong reason, and would keep passing after the policies were
-- deleted.
--
-- Supabase's own model is broad table grants with row level security doing the
-- actual restriction, which is what this reproduces. Migrations that REVOKE from
-- these roles (0002 on auth_rate_limits) run afterwards and still take effect.

grant usage on schema public to anon, authenticated, service_role;

grant all on all tables    in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all functions in schema public to anon, authenticated, service_role;

-- Tables created by the migrations that run after this file need the same
-- treatment, which is what Supabase uses default privileges for.
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
