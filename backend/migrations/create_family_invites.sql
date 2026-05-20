-- Migration: Create family_invites table
-- Purpose: Short-code invitations so additional users can join an existing family.
-- Date: 2026-05-14

CREATE TABLE IF NOT EXISTS family_invites (
  code        TEXT PRIMARY KEY,
  family_id   UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  created_by  UUID NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  used_at     TIMESTAMPTZ,
  used_by     UUID,
  CHECK (char_length(code) BETWEEN 6 AND 16)
);

CREATE INDEX IF NOT EXISTS family_invites_family_active_idx
  ON family_invites(family_id) WHERE used_at IS NULL;

ALTER TABLE family_invites ENABLE ROW LEVEL SECURITY;

-- Members of the family may read and manage invites scoped to their family.
-- The join path runs via SECURITY DEFINER (service_role) in onboard_new_user,
-- so it bypasses these policies; that's intentional — joiners are not yet
-- members so they have no way to satisfy a SELECT policy against family_members.

DROP POLICY IF EXISTS family_invites_select_own ON family_invites;
CREATE POLICY family_invites_select_own ON family_invites FOR SELECT
  USING (
    family_id IN (
      SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS family_invites_insert_own ON family_invites;
CREATE POLICY family_invites_insert_own ON family_invites FOR INSERT
  WITH CHECK (
    family_id IN (
      SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS family_invites_delete_own ON family_invites;
CREATE POLICY family_invites_delete_own ON family_invites FOR DELETE
  USING (
    used_at IS NULL
    AND family_id IN (
      SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    )
  );

COMMENT ON TABLE family_invites IS 'Short-code invitations consumed during onboarding to join an existing family.';
COMMENT ON COLUMN family_invites.code IS '6-16 char alphanumeric code, uppercase by convention.';
COMMENT ON COLUMN family_invites.expires_at IS 'Code is unusable after this timestamp.';
COMMENT ON COLUMN family_invites.used_at IS 'NULL while available; set when a user redeems the code.';
