-- Migration: onboard_new_user RPC
-- Purpose: Atomic onboarding — profile, family (or invite redemption), and
-- family_members are inserted in a single transaction so partial failures
-- can never leave orphan rows.
-- Date: 2026-05-14

CREATE OR REPLACE FUNCTION onboard_new_user(
  p_auth_id      UUID,
  p_email        TEXT,
  p_display_name TEXT,
  p_family_name  TEXT,
  p_invite_code  TEXT
) RETURNS TABLE(profile_id UUID, family_id UUID, role TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID;
  v_family_id  UUID;
  v_invite     family_invites%ROWTYPE;
  v_role       TEXT;
BEGIN
  -- Exactly one of family_name / invite_code must be provided.
  IF (p_family_name IS NULL) = (p_invite_code IS NULL) THEN
    RAISE EXCEPTION 'Provide exactly one of family_name or invite_code'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO profiles(auth_id, email, name)
    VALUES (p_auth_id, p_email, p_display_name)
    RETURNING id INTO v_profile_id;

  IF p_invite_code IS NOT NULL THEN
    SELECT * INTO v_invite
      FROM family_invites
      WHERE code = upper(p_invite_code)
      FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_invite.used_at IS NOT NULL THEN
      RAISE EXCEPTION 'invite_used' USING ERRCODE = 'P0001';
    END IF;
    IF v_invite.expires_at < now() THEN
      RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0001';
    END IF;

    v_family_id := v_invite.family_id;
    v_role := 'member';

    UPDATE family_invites
       SET used_at = now(), used_by = p_auth_id
     WHERE code = v_invite.code;
  ELSE
    INSERT INTO families(name, owner_id)
      VALUES (p_family_name, p_auth_id)
      RETURNING id INTO v_family_id;
    v_role := 'owner';

    -- Every newly created family gets its own "General Shared" virtual profile.
    -- It has no auth account (auth_id IS NULL) and no family_members row;
    -- it surfaces in /family/data only via the family_id-based query.
    INSERT INTO profiles(auth_id, email, name, family_id, is_virtual)
      VALUES (NULL, NULL, 'General Shared', v_family_id, TRUE);
  END IF;

  INSERT INTO family_members(family_id, user_id, role, display_name)
    VALUES (v_family_id, p_auth_id, v_role, p_display_name);

  -- Keep profiles.family_id in sync (used by recurring-expense materialization).
  UPDATE profiles SET family_id = v_family_id WHERE id = v_profile_id;

  RETURN QUERY SELECT v_profile_id, v_family_id, v_role;
END;
$$;

REVOKE ALL ON FUNCTION onboard_new_user(UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION onboard_new_user(UUID, TEXT, TEXT, TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION onboard_new_user(UUID, TEXT, TEXT, TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION onboard_new_user(UUID, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION onboard_new_user IS
  'Single-transaction onboarding. Called by the backend via RPC with the service_role key. '
  'Either p_family_name (create new family) or p_invite_code (join existing) must be provided.';
