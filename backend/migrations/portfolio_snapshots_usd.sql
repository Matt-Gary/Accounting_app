-- ============================================================================
-- Adds the day's USD/BRL rate to portfolio snapshots (USD equity-curve view).
--
-- Run ONLY if you already ran portfolio_snapshots.sql in its original form —
-- the current portfolio_snapshots.sql includes this column, and this ALTER is
-- idempotent either way, so running both is harmless.
-- ============================================================================

ALTER TABLE portfolio_snapshots
    ADD COLUMN IF NOT EXISTS usd_brl_rate NUMERIC;
