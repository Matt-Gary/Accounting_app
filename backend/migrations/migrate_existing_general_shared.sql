-- Migration: migrate_existing_general_shared
-- Purpose: One-off cleanup. Move all expenses currently attributed to the
-- old auth-user "General Shared" account onto the new per-family virtual
-- profile created by `add_virtual_profile.sql`, then delete the old auth
-- profile + membership row.
--
-- Run AFTER add_virtual_profile.sql and the updated onboard_new_user RPC
-- have been applied successfully.
--
-- IMPORTANT — fill in the three placeholder UUIDs below before running.
-- A lookup-helper block at the top prints the values you need.
--
-- Date: 2026-05-19

-- =============================================================================
-- STEP 1 — Discovery (read-only; copy the UUIDs you'll need into Step 2 below).
-- =============================================================================

-- Replace 'general.shared.email@example.com' with the actual email of the
-- legacy account. Run this first by itself.
SELECT
  id          AS old_profile_id,
  auth_id     AS old_auth_id,
  family_id   AS the_family_id,
  email
FROM profiles
WHERE email = 'general@example.com';   -- <-- EDIT ME

-- Confirm the new virtual profile already exists for that family.
-- Re-use `the_family_id` from the previous query.
SELECT
  id          AS new_virtual_profile_id,
  name,
  is_virtual,
  family_id
FROM profiles
WHERE family_id = '00000000-0000-0000-0000-000000000000'   -- <-- the_family_id
  AND is_virtual = TRUE;

-- Sanity: how many expenses point at the old profile today?
SELECT COUNT(*) AS expenses_to_move
FROM expenses
WHERE user_id = '00000000-0000-0000-0000-000000000000';    -- <-- old_profile_id


-- =============================================================================
-- STEP 2 — Actual migration. Fill the three UUIDs from Step 1, then run.
-- =============================================================================
BEGIN;

-- Re-point all expenses from old profile -> new virtual profile.
UPDATE expenses
   SET user_id = '00000000-0000-0000-0000-000000000000'   -- <-- new_virtual_profile_id
 WHERE user_id = '00000000-0000-0000-0000-000000000000';  -- <-- old_profile_id

-- Verify zero remaining references before destroying the old rows.
DO $$
DECLARE
  v_remaining INT;
BEGIN
  SELECT COUNT(*) INTO v_remaining
    FROM expenses
    WHERE user_id = '00000000-0000-0000-0000-000000000000';  -- <-- old_profile_id
  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'Aborting: % expenses still reference the old profile', v_remaining;
  END IF;
END $$;

-- Drop earnings/investments/recurring authored by the old account.
-- (Adjust if you want to re-point these instead of deleting — but the user
-- decision is that General Shared applies to expenses only.)
DELETE FROM earnings           WHERE user_id = '00000000-0000-0000-0000-000000000000';   -- <-- old_profile_id
DELETE FROM investments        WHERE user_id = '00000000-0000-0000-0000-000000000000';   -- <-- old_profile_id
DELETE FROM recurring_expenses WHERE user_id = '00000000-0000-0000-0000-000000000000';   -- <-- old_profile_id

-- Membership + profile cleanup.
DELETE FROM family_members
  WHERE user_id = '00000000-0000-0000-0000-000000000000';   -- <-- old_auth_id

DELETE FROM profiles
  WHERE id = '00000000-0000-0000-0000-000000000000';        -- <-- old_profile_id

COMMIT;

-- =============================================================================
-- STEP 3 — Manual final step (NOT SQL).
-- =============================================================================
-- In the Supabase dashboard → Authentication → Users:
-- Find the auth user whose UUID matches `old_auth_id` and delete it.
-- This frees the legacy email for re-use if needed.
