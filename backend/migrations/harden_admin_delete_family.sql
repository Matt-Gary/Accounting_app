-- Migration: harden admin_delete_family
-- Purpose: Replace the previous admin_delete_family implementation, which
-- relied on a `_doomed` snapshot of (auth_id, profile_id) collected at the
-- start of the function. The snapshot approach was fragile: any profile
-- present in the family but not in the snapshot (e.g. virtual "General
-- Shared" profiles introduced by add_virtual_profile.sql) would not be
-- deleted, and the final DELETE FROM families would then fail with FK
-- violation `profiles_family_id_fkey`.
--
-- Fix: delete every dependent row directly by `family_id` (or via a fresh
-- subquery on profiles) instead of via a snapshot. The only thing we
-- snapshot is the set of `auth_id`s that need to be purged from
-- `auth.users` after the transaction — virtual profiles have NULL
-- `auth_id` and are intentionally excluded from that snapshot.
--
-- Date: 2026-05-19

CREATE OR REPLACE FUNCTION admin_delete_family(p_family_id UUID)
RETURNS TABLE(auth_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Snapshot only what we need to return: auth_ids for the post-txn
  -- auth.users purge. Virtual profiles (auth_id IS NULL) are excluded —
  -- they have no auth row to delete.
  CREATE TEMP TABLE _doomed_auth ON COMMIT DROP AS
    SELECT p.auth_id
      FROM profiles p
      WHERE p.family_id = p_family_id
        AND p.auth_id IS NOT NULL;

  -- Family-scoped rows.
  DELETE FROM expenses               WHERE family_id = p_family_id;
  DELETE FROM recurring_expenses     WHERE family_id = p_family_id;
  DELETE FROM family_category_hidden WHERE family_id = p_family_id;
  DELETE FROM categories             WHERE family_id = p_family_id;
  DELETE FROM payment_methods        WHERE family_id = p_family_id;
  DELETE FROM family_invites         WHERE family_id = p_family_id;

  -- Per-profile rows (earnings/investments are scoped by profile id, not
  -- family id). Use a fresh subquery so any profile currently in the
  -- family is covered, including virtual profiles.
  DELETE FROM earnings
    WHERE user_id IN (SELECT id FROM profiles WHERE family_id = p_family_id);
  DELETE FROM investments
    WHERE user_id IN (SELECT id FROM profiles WHERE family_id = p_family_id);

  -- Membership + profile + family last. Profiles are deleted by family_id
  -- directly so the DELETE and the FK constraint on families look at the
  -- same column — no row can survive the snapshot/delete mismatch that
  -- bit the previous implementation.
  DELETE FROM family_members WHERE family_id = p_family_id;
  DELETE FROM profiles       WHERE family_id = p_family_id;
  DELETE FROM families       WHERE id = p_family_id;

  RETURN QUERY SELECT a.auth_id FROM _doomed_auth a;
END;
$$;

REVOKE ALL ON FUNCTION admin_delete_family(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_delete_family(UUID) FROM anon;
REVOKE ALL ON FUNCTION admin_delete_family(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_family(UUID) TO service_role;

COMMENT ON FUNCTION admin_delete_family IS
  'Super Admin only. Atomically deletes a family and every owned row '
  '(members, expenses, earnings, investments, recurring_expenses, '
  'family-scoped categories/payment_methods/invites/hidden, profiles '
  '— including virtual profiles). Returns each affected auth.users id '
  'so the caller can purge Supabase Auth. '
  'closing_day_overrides is intentionally not touched (global table).';
