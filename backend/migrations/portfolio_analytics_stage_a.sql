-- ============================================================================
-- Stage A — Portfolio Analytics & Tax Module
--
-- Adds classification + earnings-calendar fields, dividend/cost fields, the
-- concentration-threshold table, and backfills the fee-sign change.
--
-- RUN THE "BEFORE" QUERY FIRST and keep the output. The backfill is the only
-- destructive step in here and its effect must be checkable afterwards.
-- Safe to run as one transaction; nothing here drops data.
-- ============================================================================

BEGIN;

-- ── 0. BEFORE snapshot ──────────────────────────────────────────────────────
-- Record what the fee backfill is about to touch. Expect: only buy/deposit
-- rows that actually carry a fee.
SELECT
    'BEFORE' AS phase,
    transaction_type,
    COUNT(*)                    AS rows_affected,
    SUM(fees_brl)               AS total_fees_brl,
    SUM(brl_amount)             AS total_brl_before,
    SUM(brl_amount) + 2 * SUM(fees_brl) AS total_brl_expected_after
FROM investment_transactions
WHERE transaction_type IN ('buy', 'deposit')
  AND fees_brl <> 0
GROUP BY transaction_type;


-- ── 1. investment_transactions: inputs become authoritative ────────────────

ALTER TABLE investment_transactions
    DROP CONSTRAINT IF EXISTS investment_transactions_transaction_type_check;

ALTER TABLE investment_transactions
    ADD CONSTRAINT investment_transactions_transaction_type_check
    CHECK (transaction_type IN
           ('buy', 'sell', 'dividend', 'coupon', 'deposit', 'withdrawal'));

-- The fee is entered in the transaction currency but was only ever stored
-- converted. Recovering it as fees_brl/exchange_rate loses the number actually
-- typed, which is not acceptable in output that goes to an accountant.
ALTER TABLE investment_transactions
    ADD COLUMN IF NOT EXISTS fees_original            NUMERIC NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS withholding_tax_original NUMERIC NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS fx_spread_original       NUMERIC NOT NULL DEFAULT 0;

COMMENT ON COLUMN investment_transactions.original_amount IS
    'Trade amount in original_currency, EXCLUDING fees. For dividends/coupons '
    'this is the GROSS amount; net = original_amount - withholding_tax_original.';
COMMENT ON COLUMN investment_transactions.fees_original IS
    'Fee as entered, in original_currency, before conversion. RFB: added to '
    'acquisition cost on buys, deducted from proceeds on sells.';
COMMENT ON COLUMN investment_transactions.brl_amount IS
    'Derived by the backend from (original_amount, fees_original, '
    'exchange_rate). Never written by the client. Reproducible from the ledger.';


-- ── 2. Fee-sign backfill ───────────────────────────────────────────────────
-- Buys were stored net of fees: (amount - fee) * rate.
-- RFB requires gross of fees: (amount + fee) * rate.
-- Difference is exactly 2 * fees_brl. Fee-free rows are untouched.
UPDATE investment_transactions
   SET brl_amount = brl_amount + 2 * fees_brl
 WHERE transaction_type IN ('buy', 'deposit')
   AND fees_brl <> 0;

-- Recover the pre-conversion fee. BRL rows have no rate, so the fee is already
-- in the right units.
UPDATE investment_transactions
   SET fees_original = CASE
           WHEN COALESCE(exchange_rate, 0) > 0 THEN fees_brl / exchange_rate
           ELSE fees_brl
       END
 WHERE fees_brl <> 0;

-- Cash deposits and withdrawals were recorded with no quantity, because the
-- form does not show a quantity field for them. A cash balance is N units of
-- its currency priced at 1.0, so the amount is the quantity. Without this the
-- position evaluates to zero and disappears from the app entirely.
-- The engine derives this at read time as well, so this is about making the
-- stored row honest rather than about correctness.
UPDATE investment_transactions
   SET quantity = ABS(original_amount)
 WHERE transaction_type IN ('deposit', 'withdrawal')
   AND COALESCE(quantity, 0) = 0
   AND COALESCE(original_amount, 0) <> 0;


-- ── 3. investment_assets: classification + earnings calendar ────────────────

ALTER TABLE investment_assets
    DROP CONSTRAINT IF EXISTS investment_assets_category_check;

-- cash_equivalent: a short-duration treasury ETF (TFLO and friends) held as
-- dry powder. It has a ticker and a market price like any ETF, but its role is
-- liquidity, so it counts as active broker capital rather than a risk position.
ALTER TABLE investment_assets
    ADD CONSTRAINT investment_assets_category_check
    CHECK (category IN ('stock', 'etf', 'bond', 'crypto', 'cash_equivalent',
                        'cash_broker', 'cash_home', 'cash_bank'));

-- Free text, not an enum: a CHECK here means a migration every time reality
-- produces a sector or country the enum did not anticipate. The UI offers a
-- suggested-values dropdown instead.
ALTER TABLE investment_assets
    ADD COLUMN IF NOT EXISTS sector  TEXT,
    ADD COLUMN IF NOT EXISTS country TEXT;

-- P1.4 earnings calendar. All entered by hand; companies confirm dates late,
-- so a date is worthless without knowing whether it is confirmed.
ALTER TABLE investment_assets
    ADD COLUMN IF NOT EXISTS next_report_date       DATE,
    ADD COLUMN IF NOT EXISTS next_report_status     TEXT,
    ADD COLUMN IF NOT EXISTS next_report_source     TEXT,
    ADD COLUMN IF NOT EXISTS next_report_updated_at TIMESTAMPTZ;

ALTER TABLE investment_assets
    DROP CONSTRAINT IF EXISTS investment_assets_next_report_status_check;
ALTER TABLE investment_assets
    ADD CONSTRAINT investment_assets_next_report_status_check
    CHECK (next_report_status IS NULL
           OR next_report_status IN ('confirmed', 'estimated'));

CREATE INDEX IF NOT EXISTS idx_investment_assets_next_report
    ON investment_assets (family_id, next_report_date)
    WHERE next_report_date IS NOT NULL;


-- ── 4. investment_settings: concentration thresholds ───────────────────────

CREATE TABLE IF NOT EXISTS investment_settings (
    family_id            UUID PRIMARY KEY
                         REFERENCES families(id) ON DELETE CASCADE,
    max_position_pct     NUMERIC NOT NULL DEFAULT 20,
    max_sector_pct       NUMERIC NOT NULL DEFAULT 25,
    max_currency_pct     NUMERIC NOT NULL DEFAULT 60,
    max_country_pct      NUMERIC NOT NULL DEFAULT 60,
    report_reminder_days INT     NOT NULL DEFAULT 7,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE investment_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS investment_settings_select ON investment_settings;
CREATE POLICY investment_settings_select ON investment_settings FOR SELECT
    USING (family_id IN (SELECT fm.family_id FROM family_members fm
                          WHERE fm.user_id = auth.uid()));

DROP POLICY IF EXISTS investment_settings_insert ON investment_settings;
CREATE POLICY investment_settings_insert ON investment_settings FOR INSERT
    WITH CHECK (family_id IN (SELECT fm.family_id FROM family_members fm
                               WHERE fm.user_id = auth.uid()));

DROP POLICY IF EXISTS investment_settings_update ON investment_settings;
CREATE POLICY investment_settings_update ON investment_settings FOR UPDATE
    USING (family_id IN (SELECT fm.family_id FROM family_members fm
                          WHERE fm.user_id = auth.uid()))
    WITH CHECK (family_id IN (SELECT fm.family_id FROM family_members fm
                               WHERE fm.user_id = auth.uid()));

DROP POLICY IF EXISTS investment_settings_delete ON investment_settings;
CREATE POLICY investment_settings_delete ON investment_settings FOR DELETE
    USING (family_id IN (SELECT fm.family_id FROM family_members fm
                          WHERE fm.user_id = auth.uid()));

COMMIT;


-- ============================================================================
-- AFTER verification — run separately and compare with the BEFORE output.
-- ============================================================================

-- (a) Fee rows: brl_amount must now equal (original_amount + fee) * rate for
--     buys. Any row listed here is a mismatch and needs investigating.
SELECT 'MISMATCHED BUYS' AS check_name, id, transaction_date, transaction_type,
       original_amount, fees_original, exchange_rate, brl_amount,
       (original_amount + fees_original) * COALESCE(exchange_rate, 1) AS expected
FROM investment_transactions
WHERE transaction_type IN ('buy', 'deposit')
  AND ABS(brl_amount - (original_amount + fees_original)
                       * COALESCE(exchange_rate, 1)) > 0.01;

-- (b) Same check for sells: (original_amount - fee) * rate.
SELECT 'MISMATCHED SELLS' AS check_name, id, transaction_date, transaction_type,
       original_amount, fees_original, exchange_rate, brl_amount,
       (original_amount - fees_original) * COALESCE(exchange_rate, 1) AS expected
FROM investment_transactions
WHERE transaction_type IN ('sell', 'withdrawal')
  AND ABS(brl_amount - (original_amount - fees_original)
                       * COALESCE(exchange_rate, 1)) > 0.01;

-- (c) Fee-free rows must be completely unchanged by this migration.
SELECT 'FEE-FREE ROW COUNT' AS check_name, COUNT(*) AS rows
FROM investment_transactions
WHERE COALESCE(fees_brl, 0) = 0;

-- (d) Non-BRL transactions with no exchange rate. These now RAISE in the
--     engine instead of being silently valued at a guessed rate, so any row
--     here must be corrected before the portfolio will load.
SELECT 'MISSING FX RATE' AS check_name, id, transaction_date, original_currency,
       original_amount
FROM investment_transactions
WHERE original_currency <> 'BRL'
  AND (exchange_rate IS NULL OR exchange_rate <= 0);

-- (e) Cash movements must all carry a quantity now. Expect zero rows.
SELECT 'CASH WITHOUT QUANTITY' AS check_name, id, transaction_date,
       transaction_type, original_amount, quantity
FROM investment_transactions
WHERE transaction_type IN ('deposit', 'withdrawal')
  AND COALESCE(quantity, 0) = 0
  AND COALESCE(original_amount, 0) <> 0;
