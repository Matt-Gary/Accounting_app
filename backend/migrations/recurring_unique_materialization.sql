-- ============================================================================
-- Recurring expenses: one materialized row per definition per date.
--
-- materialize_recurring_expenses() checks "does this month already have the
-- row?" and then inserts. Two dashboard/report requests for the same month can
-- both pass the check and both insert, so the bill shows up twice. A unique
-- index makes the database refuse the second insert; app.py treats that
-- refusal (SQLSTATE 23505) as "already materialized".
--
-- Both racers compute the same target date, so (recurring_id, spent_at) is
-- enough to catch the race. The index is deliberately NOT partial: NULLs are
-- distinct in a unique index, so ordinary expenses (recurring_id IS NULL) are
-- not constrained at all, and a plain index keeps ON CONFLICT usable later.
--
-- Step 1 DELETES rows: exact duplicates of a generated expense (same
-- definition, same date), keeping one. Look at the BEFORE result first - if it
-- returns 0 rows, step 1 removes nothing.
--
-- Idempotent and transactional. Run manually in the Supabase SQL editor.
-- ============================================================================

-- BEFORE: generated expenses that exist more than once (0 rows = nothing to clean).
SELECT recurring_id, spent_at, COUNT(*) AS copies, SUM(amount) AS total_amount
FROM expenses
WHERE recurring_id IS NOT NULL
GROUP BY recurring_id, spent_at
HAVING COUNT(*) > 1
ORDER BY spent_at;

BEGIN;

-- 1. Remove existing duplicates, keeping one row of each. Without this the
--    index below cannot be created. ctid is used so the choice does not depend
--    on any column the table may or may not have.
DELETE FROM expenses a
USING expenses b
WHERE a.recurring_id IS NOT NULL
  AND a.recurring_id = b.recurring_id
  AND a.spent_at = b.spent_at
  AND a.ctid > b.ctid;

-- 2. Refuse a second row for the same definition on the same date.
CREATE UNIQUE INDEX IF NOT EXISTS expenses_recurring_spent_at_uidx
    ON expenses (recurring_id, spent_at);

COMMIT;

-- AFTER: 0 rows of duplicates, and the index is listed.
SELECT recurring_id, spent_at, COUNT(*) AS copies
FROM expenses
WHERE recurring_id IS NOT NULL
GROUP BY recurring_id, spent_at
HAVING COUNT(*) > 1;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'expenses'
  AND indexname = 'expenses_recurring_spent_at_uidx';
