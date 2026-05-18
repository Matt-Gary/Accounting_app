-- Migration: super_admin_delete RPCs
-- Purpose: Atomic cascade deletes for the Super Admin dashboard. Each function
-- removes one user (or one whole family) plus every owned row across expenses,
-- earnings, investments, recurring_expenses, family_members, profiles, and
-- family-scoped categories/payment_methods/invites. Returns the affected
-- auth.users id(s) so the caller can purge Supabase Auth in a follow-up call.
--
-- closing_day_overrides is intentionally NOT touched — it is a global table.
-- Date: 2026-05-15

-- =========================================================================
-- admin_delete_user(profile_id)
-- =========================================================================
CREATE OR REPLACE FUNCTION admin_delete_user(p_profile_id UUID)
RETURNS TABLE(auth_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_id UUID;
BEGIN
  SELECT p.auth_id INTO v_auth_id
    FROM profiles p
    WHERE p.id = p_profile_id;

  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'user_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Children first (FKs may or may not cascade — be explicit).
  DELETE FROM expenses           WHERE user_id = p_profile_id;
  DELETE FROM earnings           WHERE user_id = p_profile_id;
  DELETE FROM investments        WHERE user_id = p_profile_id;
  DELETE FROM recurring_expenses WHERE user_id = p_profile_id;

  -- Preserve invite history for invites this auth consumed, but drop unused
  -- invites they personally created.
  UPDATE family_invites SET used_by = NULL WHERE used_by = v_auth_id;
  DELETE FROM family_invites
    WHERE created_by = v_auth_id AND used_at IS NULL;

  DELETE FROM family_members WHERE user_id = v_auth_id;
  DELETE FROM profiles       WHERE id = p_profile_id;

  RETURN QUERY SELECT v_auth_id;
END;
$$;

REVOKE ALL ON FUNCTION admin_delete_user(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_delete_user(UUID) FROM anon;
REVOKE ALL ON FUNCTION admin_delete_user(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_user(UUID) TO service_role;

COMMENT ON FUNCTION admin_delete_user IS
  'Super Admin only. Atomically deletes a profile and all owned rows '
  '(expenses, earnings, investments, recurring_expenses, family_members). '
  'Returns the auth.users id so the caller can also purge Supabase Auth.';


-- =========================================================================
-- admin_delete_family(family_id)
-- =========================================================================
CREATE OR REPLACE FUNCTION admin_delete_family(p_family_id UUID)
RETURNS TABLE(auth_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Collect every (auth_id, profile_id) pair belonging to this family before
  -- we start deleting rows. Temp table is scoped to this transaction.
  CREATE TEMP TABLE _doomed ON COMMIT DROP AS
    SELECT p.auth_id, p.id AS profile_id
      FROM profiles p
      JOIN family_members fm ON fm.user_id = p.auth_id
      WHERE fm.family_id = p_family_id;

  -- Family-scoped rows first.
  DELETE FROM expenses               WHERE family_id = p_family_id;
  DELETE FROM recurring_expenses     WHERE family_id = p_family_id;
  DELETE FROM family_category_hidden WHERE family_id = p_family_id;
  DELETE FROM categories             WHERE family_id = p_family_id;
  DELETE FROM payment_methods        WHERE family_id = p_family_id;
  DELETE FROM family_invites         WHERE family_id = p_family_id;

  -- Per-profile rows for the doomed users (earnings/investments are scoped
  -- by profile id, not family id).
  DELETE FROM earnings    WHERE user_id IN (SELECT profile_id FROM _doomed);
  DELETE FROM investments WHERE user_id IN (SELECT profile_id FROM _doomed);

  -- Membership + profile + family last.
  DELETE FROM family_members WHERE family_id = p_family_id;
  DELETE FROM profiles       WHERE id IN (SELECT profile_id FROM _doomed);
  DELETE FROM families       WHERE id = p_family_id;

  RETURN QUERY SELECT d.auth_id FROM _doomed d;
END;
$$;

REVOKE ALL ON FUNCTION admin_delete_family(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION admin_delete_family(UUID) FROM anon;
REVOKE ALL ON FUNCTION admin_delete_family(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_family(UUID) TO service_role;

COMMENT ON FUNCTION admin_delete_family IS
  'Super Admin only. Atomically deletes a family and every owned row '
  '(members, expenses, earnings, investments, recurring_expenses, '
  'family-scoped categories/payment_methods/invites/hidden, profiles). '
  'Returns each affected auth.users id so the caller can purge Supabase Auth. '
  'closing_day_overrides is intentionally not touched (global table).';
