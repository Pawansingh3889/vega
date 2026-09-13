"""SECURITY.md N1: tenant isolation, proven rather than asserted.

Rigel did not demonstrate that row level security works. It demonstrated how RLS
fails silently: a SECURITY DEFINER helper referencing a dropped column returned
empty result sets instead of an error, and a human found it by clicking a menu
item. Empty is what a working policy looks like from the outside, which is why
every assertion here that expects to see nothing is paired with one that expects
to see something.
"""

from __future__ import annotations

import uuid

import asyncpg
import pytest

from .conftest import Tenants, act_as

pytestmark = pytest.mark.asyncio


async def visible_skus(db: asyncpg.Connection) -> set[str]:
    rows = await db.fetch("SELECT sku FROM public.products ORDER BY sku")
    return {r["sku"] for r in rows}


# --- the boundary between two different users -------------------------------


async def test_a_user_sees_only_their_own_company(db: asyncpg.Connection, tenants: Tenants) -> None:
    async with db.transaction():
        await act_as(db, tenants.solo_user)
        assert await visible_skus(db) == {"A-001"}


async def test_a_stranger_sees_nothing(db: asyncpg.Connection, tenants: Tenants) -> None:
    async with db.transaction():
        await act_as(db, tenants.outsider)
        assert await visible_skus(db) == set()


async def test_anon_sees_nothing(db: asyncpg.Connection, tenants: Tenants) -> None:
    async with db.transaction():
        await act_as(db, None, role="anon")
        assert await visible_skus(db) == set()


# --- the case N1 was strengthened to cover ----------------------------------
# One person, two companies. The boundary must follow the session, not a row in
# profiles chosen by an unordered LIMIT 1.


async def test_dual_member_sees_company_a_when_acting_in_a(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    async with db.transaction():
        await act_as(db, tenants.dual_user, tenants.company_a)
        assert await visible_skus(db) == {"A-001"}


async def test_dual_member_sees_company_b_when_acting_in_b(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    async with db.transaction():
        await act_as(db, tenants.dual_user, tenants.company_b)
        assert await visible_skus(db) == {"B-001"}


async def test_the_boundary_actually_flips(db: asyncpg.Connection, tenants: Tenants) -> None:
    """The two assertions above could both pass if the helper ignored the header
    and each happened to match. Prove the same connection sees different data."""
    async with db.transaction():
        await act_as(db, tenants.dual_user, tenants.company_a)
        first = await visible_skus(db)
        await act_as(db, tenants.dual_user, tenants.company_b)
        second = await visible_skus(db)
    assert first == {"A-001"}
    assert second == {"B-001"}
    assert first != second


async def test_dual_member_with_no_company_chosen_sees_nothing(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """Ambiguity resolves to nothing, not to an arbitrary company. This is what
    the old unordered LIMIT 1 got wrong."""
    async with db.transaction():
        await act_as(db, tenants.dual_user, None)
        assert await visible_skus(db) == set()


async def test_a_header_naming_a_company_you_are_not_in_is_refused(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The header is a request, not an assertion. Membership answers it."""
    async with db.transaction():
        await act_as(db, tenants.solo_user, tenants.company_b)
        assert await visible_skus(db) == set()


async def test_an_unknown_company_id_is_refused(db: asyncpg.Connection, tenants: Tenants) -> None:
    async with db.transaction():
        await act_as(db, tenants.dual_user, uuid.uuid4())
        assert await visible_skus(db) == set()


async def test_writes_respect_the_session_company(db: asyncpg.Connection, tenants: Tenants) -> None:
    """Reads are half the boundary. A user acting in A must not write into B."""
    async with db.transaction():
        await act_as(db, tenants.dual_user, tenants.company_a)
        # The refused INSERT aborts its transaction, so it needs a savepoint of
        # its own or nothing after it can run.
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            async with db.transaction():
                await db.execute(
                    "INSERT INTO public.products (company_id, sku, name)"
                    " VALUES ($1, 'X-001', 'Smuggled')",
                    tenants.company_b,
                )
        # And the boundary still holds afterwards, rather than the connection
        # having been left in a state where everything fails for another reason.
        assert await visible_skus(db) == {"A-001"}


# --- N1's structural rules, generated over the live schema -------------------


async def test_every_table_has_rls_enabled(db: asyncpg.Connection) -> None:
    rows = await db.fetch(
        """SELECT t.tablename FROM pg_tables t
             JOIN pg_class c ON c.relname = t.tablename
             JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
            WHERE t.schemaname = 'public' AND NOT c.relrowsecurity"""
    )
    assert [r["tablename"] for r in rows] == []


async def test_no_table_is_left_without_a_policy(db: asyncpg.Connection) -> None:
    """RLS enabled with no policy denies everything, which is the safe end. This
    is what catches a new table added without coverage."""
    rows = await db.fetch(
        """SELECT t.tablename FROM pg_tables t
            WHERE t.schemaname = 'public'
              AND NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.tablename = t.tablename)"""
    )
    assert [r["tablename"] for r in rows] == []


async def test_no_security_definer_has_a_mutable_search_path(db: asyncpg.Connection) -> None:
    rows = await db.fetch(
        """SELECT p.proname FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
            WHERE p.prosecdef
              AND (p.proconfig IS NULL
                   OR NOT EXISTS (
                        SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'
                   ))"""
    )
    assert [r["proname"] for r in rows] == []


async def test_no_policy_is_unconditionally_open(db: asyncpg.Connection) -> None:
    """The shape of an inherited defect: a world-readable auth table.

    A policy with no TO clause defaults to `public`, which is normal and fine:
    the inherited "Company isolation" policies are all shaped that way and it is
    the USING expression that does the scoping. What is never fine is a policy
    whose USING expression is literally true for a role that is not
    service_role, because that reads every row for anyone who can reach it.
    """
    rows = await db.fetch(
        """SELECT tablename, policyname, roles::text AS roles FROM pg_policies
            WHERE schemaname = 'public'
              AND roles::text <> '{service_role}'
              AND qual IN ('true', '(true)')
              -- Reference data is identical for every tenant and deliberately
              -- readable by any signed-in user: VAT treatments, their rates, and
              -- sourced FX. Readable by `authenticated`, never by `anon`, and
              -- writable only by migration.
              AND NOT (tablename IN ('vat_treatments', 'vat_rates', 'fx_rates')
                       AND roles::text IN ('{authenticated}', '{vega_api}')
                       AND cmd IN ('SELECT', 'INSERT'))"""
    )
    assert [(r["tablename"], r["policyname"], r["roles"]) for r in rows] == []


# --- the developer override, which is a deliberate cross-tenant hole ---------
# It exists so a named account can inspect any company while the product is
# being built. Every test here is about keeping it narrow: it must work when
# invoked, and must not fire by accident, on expiry, or for anyone else.


async def grant_developer(
    db: asyncpg.Connection, email: str, days: int = 30, reason: str | None = None
) -> None:
    await db.execute(
        """INSERT INTO public.developer_access (email, reason, expires_at)
           VALUES ($1, $2, now() + make_interval(days => $3))
           ON CONFLICT (email) DO UPDATE
             SET expires_at = EXCLUDED.expires_at, reason = EXCLUDED.reason""",
        email,
        reason or "Automated test of the developer override behaviour.",
        days,
    )


async def test_developer_can_act_in_a_company_they_do_not_belong_to(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    await grant_developer(db, "solo@example.test")
    async with db.transaction():
        # solo_user belongs to company A only.
        await act_as(db, tenants.solo_user, tenants.company_b)
        assert await visible_skus(db) == {"B-001"}


async def test_developer_without_a_company_header_does_not_see_everything(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The override requires a company to be asked for. A developer who chooses
    nothing is treated like anyone else, so it never fires by accident."""
    await grant_developer(db, "solo@example.test")
    async with db.transaction():
        await act_as(db, tenants.solo_user, None)
        assert await visible_skus(db) == {"A-001"}


async def test_an_expired_grant_does_nothing(db: asyncpg.Connection, tenants: Tenants) -> None:
    """Expiry is enforced in the database, so a lapsed grant stops working
    without anyone remembering to delete the row."""
    await db.execute(
        """INSERT INTO public.developer_access (email, reason, granted_at, expires_at)
           VALUES ($1, $2, now() - interval '90 days', now() - interval '1 day')
           ON CONFLICT (email) DO UPDATE
             SET granted_at = EXCLUDED.granted_at, expires_at = EXCLUDED.expires_at""",
        "solo@example.test",
        "A deliberately lapsed grant, used to prove expiry is enforced.",
    )
    async with db.transaction():
        await act_as(db, tenants.solo_user, tenants.company_b)
        assert await visible_skus(db) == set()


async def test_the_override_is_off_for_everyone_else(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """Granting one account must not widen anybody else's reach."""
    await grant_developer(db, "solo@example.test")
    async with db.transaction():
        await act_as(db, tenants.dual_user, tenants.company_a)
        assert await visible_skus(db) == {"A-001"}
    async with db.transaction():
        await act_as(db, tenants.outsider, tenants.company_a)
        assert await visible_skus(db) == set()


async def test_developer_access_is_unreadable_through_the_api(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The list of who holds a backdoor is not something a signed-in user gets
    to enumerate."""
    await grant_developer(db, "solo@example.test")
    async with db.transaction():
        await act_as(db, tenants.solo_user, tenants.company_a)
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            async with db.transaction():
                await db.fetch("SELECT email FROM public.developer_access")


async def test_a_grant_cannot_be_immortal(db: asyncpg.Connection) -> None:
    """No expiry means a permanent backdoor wearing a temporary label, so the
    column is NOT NULL and the constraint refuses a backdated window."""
    with pytest.raises(asyncpg.PostgresError):
        async with db.transaction():
            await db.execute(
                """INSERT INTO public.developer_access (email, reason, expires_at)
                   VALUES ('forever@example.test',
                           'An attempt to grant access that never expires.',
                           now() - interval '1 day')"""
            )


# --- SECURITY.md N2: append-only ledgers ------------------------------------
# The point of these tables is that somebody can be told, later and under
# pressure, that nothing was quietly changed. So the tests run as the OWNER,
# which bypasses row level security entirely. If append-only only held for
# ordinary roles it would be worthless exactly when it matters.

# A BEFORE ROW trigger only fires when there is a row, and DELETE over an empty
# table is a harmless no-op. So each test seeds its own row first: otherwise it
# passes against a table with no protection at all, which is the vacuous-check
# failure this project keeps finding.

APPEND_ONLY = ["security_audit_log", "transaction_audit_log", "batch_movements", "fx_rates"]


async def seed_ledger_row(db: asyncpg.Connection, table: str, tenants: Tenants) -> None:
    if table == "security_audit_log":
        await db.execute(
            """INSERT INTO public.security_audit_log (action, details, severity)
               VALUES ('vega.append_only_test', '{}'::jsonb, 'info')"""
        )
    elif table == "transaction_audit_log":
        await db.execute(
            """INSERT INTO public.transaction_audit_log (table_name, record_id, action)
               VALUES ('products', gen_random_uuid(), 'INSERT')"""
        )
    elif table == "fx_rates":
        await db.execute(
            """INSERT INTO public.fx_rates
                   (base_currency, quote_currency, rate, rate_date, source)
               VALUES ('EUR', 'GBP', 0.8412, current_date, 'test')"""
        )
    elif table == "batch_movements":
        batch = await db.fetchval(
            """INSERT INTO public.batches
                   (company_id, product_id, batch_code, quantity_received)
               SELECT $1, p.id, 'AO-TEST', 10
                 FROM public.products p WHERE p.company_id = $1 LIMIT 1
               RETURNING id""",
            tenants.company_a,
        )
        await db.execute(
            """INSERT INTO public.batch_movements
                   (company_id, batch_id, movement_type, quantity)
               VALUES ($1, $2, 'receipt', 10)""",
            tenants.company_a,
            batch,
        )


@pytest.mark.parametrize("table", APPEND_ONLY)
async def test_the_ledger_refuses_an_update(
    db: asyncpg.Connection, tenants: Tenants, table: str
) -> None:
    await seed_ledger_row(db, table, tenants)
    assert await db.fetchval(f"SELECT count(*) FROM public.{table}") > 0, (
        "no row to protect, so this test would pass against no protection at all"
    )
    with pytest.raises(asyncpg.PostgresError, match="append-only"):
        async with db.transaction():
            await db.execute(f"UPDATE public.{table} SET id = id")


@pytest.mark.parametrize("table", APPEND_ONLY)
async def test_the_ledger_refuses_a_delete(
    db: asyncpg.Connection, tenants: Tenants, table: str
) -> None:
    await seed_ledger_row(db, table, tenants)
    assert await db.fetchval(f"SELECT count(*) FROM public.{table}") > 0
    with pytest.raises(asyncpg.PostgresError, match="append-only"):
        async with db.transaction():
            await db.execute(f"DELETE FROM public.{table}")


async def test_the_ledger_still_accepts_an_append(db: asyncpg.Connection) -> None:
    """Append-only must not mean write-nothing. A refusal that also blocks the
    legitimate path gets removed by whoever hits it at 2am."""
    row = await db.fetchval(
        """INSERT INTO public.security_audit_log (action, details, severity)
           VALUES ('vega.test_append', '{}'::jsonb, 'info') RETURNING id"""
    )
    assert row is not None


async def test_the_refusal_says_what_to_do_instead(db: asyncpg.Connection) -> None:
    """N6: an error saying only 'not permitted' leaves the reader guessing. This
    one names the table, the operation, and the way forward."""
    await db.execute(
        """INSERT INTO public.security_audit_log (action, details, severity)
           VALUES ('vega.message_test', '{}'::jsonb, 'info')"""
    )
    try:
        async with db.transaction():
            await db.execute("DELETE FROM public.security_audit_log")
    except asyncpg.PostgresError as exc:
        message = str(exc)
    else:
        pytest.fail("the delete was not refused")
    assert "security_audit_log" in message
    assert "DELETE" in message
    assert "appending" in message


# --- N1 for the HMRC submission record ---------------------------------------
# A filed VAT return is the most sensitive row in this schema: it is the number
# a company told the government, under a VAT registration number. The boundary
# is asserted here rather than left to the structural checks above, which only
# prove that RLS is on and a policy exists, not that the policy is the right one.


async def _seed_submission(
    db: asyncpg.Connection, company: uuid.UUID, user: uuid.UUID, period_key: str
) -> None:
    """Written as the service does it: no policy lets `authenticated` insert."""
    await db.execute(
        """INSERT INTO public.hmrc_submissions
             (company_id, vrn, period_key, period_start, period_end,
              payload, environment, submitted_by)
           VALUES ($1, '123456789', $2, DATE '2026-07-01', DATE '2026-09-30',
                   '{"vatDueSales": "1.00"}'::jsonb, 'sandbox', $3)""",
        company,
        period_key,
        user,
    )


async def visible_period_keys(db: asyncpg.Connection) -> set[str]:
    rows = await db.fetch("SELECT period_key FROM public.hmrc_submissions")
    return {r["period_key"] for r in rows}


async def test_a_company_cannot_read_another_companys_vat_submission(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    await _seed_submission(db, tenants.company_a, tenants.solo_user, "A-Q1")
    await _seed_submission(db, tenants.company_b, tenants.dual_user, "B-Q1")

    async with db.transaction():
        await act_as(db, tenants.solo_user)
        assert await visible_period_keys(db) == {"A-Q1"}


async def test_a_stranger_sees_no_submissions(db: asyncpg.Connection, tenants: Tenants) -> None:
    await _seed_submission(db, tenants.company_a, tenants.solo_user, "A-Q1")

    async with db.transaction():
        await act_as(db, tenants.outsider)
        assert await visible_period_keys(db) == set()


async def test_anon_sees_no_submissions(db: asyncpg.Connection, tenants: Tenants) -> None:
    await _seed_submission(db, tenants.company_a, tenants.solo_user, "A-Q1")

    async with db.transaction():
        await act_as(db, None, role="anon")
        assert await visible_period_keys(db) == set()


async def test_a_dual_member_sees_only_the_company_they_are_acting_in(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """The case N1 exists for: one person, two companies, two tax identities.

    Filing under the wrong one is not a leak, it is a misfiled return.
    """
    await _seed_submission(db, tenants.company_a, tenants.dual_user, "A-Q1")
    await _seed_submission(db, tenants.company_b, tenants.dual_user, "B-Q1")

    async with db.transaction():
        await act_as(db, tenants.dual_user, company=tenants.company_a)
        assert await visible_period_keys(db) == {"A-Q1"}

    async with db.transaction():
        await act_as(db, tenants.dual_user, company=tenants.company_b)
        assert await visible_period_keys(db) == {"B-Q1"}


async def test_authenticated_cannot_write_a_submission(
    db: asyncpg.Connection, tenants: Tenants
) -> None:
    """N3's shape. The server produces what gets filed, so there is no INSERT
    policy for `authenticated` and a browser session cannot invent a return."""
    async with db.transaction():
        await act_as(db, tenants.solo_user)
        # A nested transaction is a savepoint. Without it the refused INSERT
        # aborts the outer transaction and the failure that surfaces is the
        # cleanup, not the refusal this test is about.
        with pytest.raises(asyncpg.PostgresError):
            async with db.transaction():
                await _seed_submission(db, tenants.company_a, tenants.solo_user, "FORGED")
