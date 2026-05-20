-- Migration: add_virtual_profile
-- Purpose: Introduce per-family "virtual" profiles (no Supabase auth account)
-- so each family can have its own isolated "General Shared" payer without the
-- global email-uniqueness conflict that blocks SaaS rollout.
--
-- A virtual profile is a row in `profiles` where:
--   - auth_id IS NULL (no Supabase auth user)
--   - email   IS NULL (no email — there is no human behind it)
--   - is_virtual = TRUE
--   - family_id points directly to the owning family
-- It has NO row in family_members (the auth-middleware lookup never matches it).
--
-- Date: 2026-05-19

BEGIN;

-- 1. Schema: new flag column + relax email NOT NULL for virtual rows
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_virtual BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE profiles
  ALTER COLUMN email DROP NOT NULL;
-- auth_id is already nullable (verified via \d profiles)

-- 2. Backfill: ensure every existing family has exactly one virtual profile
INSERT INTO profiles (auth_id, email, name, family_id, is_virtual)
SELECT NULL, NULL, 'General Shared', f.id, TRUE
FROM families f
WHERE NOT EXISTS (
  SELECT 1
    FROM profiles p
    WHERE p.family_id = f.id
      AND p.is_virtual = TRUE
);

-- 3. Integrity: virtual <=> no auth_id (XOR with real profiles)
ALTER TABLE profiles
  ADD CONSTRAINT virtual_xor_auth
  CHECK (
    (is_virtual = TRUE  AND auth_id IS NULL)
    OR (is_virtual = FALSE AND auth_id IS NOT NULL)
  );

-- 4. At most one virtual profile per family
CREATE UNIQUE INDEX IF NOT EXISTS one_virtual_per_family
  ON profiles (family_id)
  WHERE is_virtual = TRUE;

COMMIT;
