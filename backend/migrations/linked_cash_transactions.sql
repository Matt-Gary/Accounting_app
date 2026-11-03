-- ============================================================================
-- Linked cash movements: a buy / sell / dividend / coupon can move money in a
-- cash account automatically. The cash row points at the trade that created it.
--
-- ON DELETE CASCADE: deleting the trade removes its cash movement, so the
-- cash balance can never keep a withdrawal for a purchase that no longer
-- exists. The backend refuses direct edits/deletes of a linked row.
--
-- Idempotent and transactional. Run manually in the Supabase SQL editor.
-- ============================================================================

-- BEFORE: column absent (0 rows) on first run.
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'investment_transactions'
  AND column_name = 'linked_transaction_id';

BEGIN;

ALTER TABLE investment_transactions
    ADD COLUMN IF NOT EXISTS linked_transaction_id UUID
        REFERENCES investment_transactions(id) ON DELETE CASCADE;

-- At most one cash movement per trade, and fast lookup from the trade.
CREATE UNIQUE INDEX IF NOT EXISTS investment_transactions_linked_uidx
    ON investment_transactions (linked_transaction_id)
    WHERE linked_transaction_id IS NOT NULL;

COMMIT;

-- AFTER: one row, data_type uuid.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'investment_transactions'
  AND column_name = 'linked_transaction_id';
