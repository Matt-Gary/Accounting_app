-- ============================================================================
-- Portfolio snapshots — Stage 3 (equity curve)
--
-- One row per family per day: the portfolio's value and invested capital at
-- the moment it was last computed that day. Written best-effort by the backend
-- whenever a fresh portfolio summary is produced ("materialize at visit");
-- `source` records how the row came to be, so a future scheduler or a
-- historical backfill can coexist with visit-driven rows.
--
-- Snapshots with an incomplete valuation are never written (the backend
-- refuses them), so a stored row is always a fact, not a partial guess.
--
-- Run manually in the Supabase SQL editor. Idempotent.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id           UUID NOT NULL
                        REFERENCES families(id) ON DELETE CASCADE,
    snapshot_date       DATE NOT NULL,
    total_value_brl     NUMERIC NOT NULL,
    total_invested_brl  NUMERIC NOT NULL,
    allocation_base_brl NUMERIC,
    -- Slim breakdowns for future charts: {name: {value_brl, invested_brl}}.
    by_group            JSONB,
    by_category         JSONB,
    totals_complete     BOOLEAN NOT NULL DEFAULT TRUE,
    -- USD/BRL close observed when the snapshot was taken. Stored so a USD
    -- view of the curve uses each day's own rate — converting history at
    -- today's rate would re-price the past. NULL when the rate was
    -- unavailable that day (the USD view simply skips such points).
    usd_brl_rate        NUMERIC,
    source              TEXT NOT NULL DEFAULT 'visit'
                        CHECK (source IN ('visit', 'scheduler', 'backfill')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- The write path upserts on this pair: a later computation the same day
    -- simply replaces the earlier row (a fresher read is a better read).
    CONSTRAINT portfolio_snapshots_family_date_unique
        UNIQUE (family_id, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_portfolio_snapshots_family_date
    ON portfolio_snapshots (family_id, snapshot_date);

ALTER TABLE portfolio_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS portfolio_snapshots_select ON portfolio_snapshots;
CREATE POLICY portfolio_snapshots_select ON portfolio_snapshots FOR SELECT
    USING (family_id IN (SELECT fm.family_id FROM family_members fm
                          WHERE fm.user_id = auth.uid()));

DROP POLICY IF EXISTS portfolio_snapshots_insert ON portfolio_snapshots;
CREATE POLICY portfolio_snapshots_insert ON portfolio_snapshots FOR INSERT
    WITH CHECK (family_id IN (SELECT fm.family_id FROM family_members fm
                               WHERE fm.user_id = auth.uid()));

DROP POLICY IF EXISTS portfolio_snapshots_update ON portfolio_snapshots;
CREATE POLICY portfolio_snapshots_update ON portfolio_snapshots FOR UPDATE
    USING (family_id IN (SELECT fm.family_id FROM family_members fm
                          WHERE fm.user_id = auth.uid()))
    WITH CHECK (family_id IN (SELECT fm.family_id FROM family_members fm
                               WHERE fm.user_id = auth.uid()));

DROP POLICY IF EXISTS portfolio_snapshots_delete ON portfolio_snapshots;
CREATE POLICY portfolio_snapshots_delete ON portfolio_snapshots FOR DELETE
    USING (family_id IN (SELECT fm.family_id FROM family_members fm
                          WHERE fm.user_id = auth.uid()));

COMMIT;

-- AFTER check: table exists and is empty (fills up from the first visit).
-- SELECT count(*) FROM portfolio_snapshots;
