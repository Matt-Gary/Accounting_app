-- Migration: Professional Investment Ledger
-- Purpose: Replace the aggregate investments table with a proper transaction ledger.
--          Supports preço médio cost basis, realized gain/loss calculation, and
--          yearly tax reports (Receita Federal / PIT-38) in BRL.
-- Date: 2026-06-18

-- ─── Step 1: Archive old table (no data loss) ────────────────────────────────
-- User will re-enter all historical transactions in the new system.
-- Drop after 30 days once the new system is confirmed working:
--   DROP TABLE investments_legacy;

ALTER TABLE IF EXISTS investments RENAME TO investments_legacy;

-- ─── Step 2: investment_assets ───────────────────────────────────────────────
-- The "what you own" master record. One row per holding/account.

CREATE TABLE investment_assets (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id   UUID        NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    category    TEXT        NOT NULL
                            CHECK (category IN (
                                'stock', 'bond', 'crypto',
                                'cash_broker', 'cash_home', 'cash_bank'
                            )),
    symbol      TEXT,       -- ticker/code; required for stock/crypto, NULL for bond/cash
    name        TEXT        NOT NULL,
    currency    TEXT        NOT NULL DEFAULT 'BRL',  -- native currency of the asset (USD/EUR/PLN/BRL)
    account     TEXT,       -- grouping label, e.g. "Interactive Brokers", "Nubank"
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_investment_assets_family
    ON investment_assets(family_id);

CREATE OR REPLACE FUNCTION _update_investment_assets_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_investment_assets_updated_at
    BEFORE UPDATE ON investment_assets
    FOR EACH ROW EXECUTE FUNCTION _update_investment_assets_updated_at();

ALTER TABLE investment_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS investment_assets_select ON investment_assets;
CREATE POLICY investment_assets_select ON investment_assets FOR SELECT
    USING (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS investment_assets_insert ON investment_assets;
CREATE POLICY investment_assets_insert ON investment_assets FOR INSERT
    WITH CHECK (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS investment_assets_update ON investment_assets;
CREATE POLICY investment_assets_update ON investment_assets FOR UPDATE
    USING (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS investment_assets_delete ON investment_assets;
CREATE POLICY investment_assets_delete ON investment_assets FOR DELETE
    USING (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

COMMENT ON TABLE investment_assets IS 'Master record per investment holding/account. One row per distinct asset.';
COMMENT ON COLUMN investment_assets.category IS 'stock | bond | crypto | cash_broker | cash_home | cash_bank';
COMMENT ON COLUMN investment_assets.currency IS 'Native currency of the asset (USD, EUR, PLN, BRL).';


-- ─── Step 3: investment_transactions ─────────────────────────────────────────
-- The "what happened" ledger. Every buy/sell/dividend/deposit/withdrawal.

CREATE TABLE investment_transactions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id                UUID        NOT NULL REFERENCES investment_assets(id) ON DELETE CASCADE,
    family_id               UUID        NOT NULL,
    -- family_id is denormalized from asset for efficient RLS checks without a join.
    -- Must always equal the investment_assets.family_id for this asset.
    transaction_type        TEXT        NOT NULL
                            CHECK (transaction_type IN (
                                'buy', 'sell', 'dividend', 'deposit', 'withdrawal'
                            )),
    transaction_date        DATE        NOT NULL,
    quantity                NUMERIC     NOT NULL DEFAULT 0,
    -- Units bought/sold. For cash deposit/withdrawal: currency units (e.g. 1000 for R$1,000).
    price_per_unit_original NUMERIC,    -- price per unit in original_currency; optional, display only
    original_currency       TEXT        NOT NULL DEFAULT 'BRL',
    original_amount         NUMERIC     NOT NULL,   -- total in original_currency
    exchange_rate           NUMERIC,    -- rate at transaction time (original → BRL); NULL when currency = BRL
    brl_amount              NUMERIC     NOT NULL,
    -- Authoritative BRL cost for tax purposes.
    -- Computed as original_amount × exchange_rate; stored explicitly for immutable tax records.
    fees_brl                NUMERIC     NOT NULL DEFAULT 0,
    -- Brokerage/exchange fees in BRL. Included in brl_amount.
    -- Brazilian Receita Federal treats fees as part of cost basis (raises basis, lowers taxable gain).
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_investment_transactions_asset
    ON investment_transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_investment_transactions_family
    ON investment_transactions(family_id);
CREATE INDEX IF NOT EXISTS idx_investment_transactions_date
    ON investment_transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_investment_transactions_family_date
    ON investment_transactions(family_id, transaction_date);

ALTER TABLE investment_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS investment_transactions_select ON investment_transactions;
CREATE POLICY investment_transactions_select ON investment_transactions FOR SELECT
    USING (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS investment_transactions_insert ON investment_transactions;
CREATE POLICY investment_transactions_insert ON investment_transactions FOR INSERT
    WITH CHECK (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS investment_transactions_update ON investment_transactions;
CREATE POLICY investment_transactions_update ON investment_transactions FOR UPDATE
    USING (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS investment_transactions_delete ON investment_transactions;
CREATE POLICY investment_transactions_delete ON investment_transactions FOR DELETE
    USING (family_id IN (
        SELECT fm.family_id FROM family_members fm WHERE fm.user_id = auth.uid()
    ));

COMMENT ON TABLE investment_transactions IS 'Full transaction ledger — every buy/sell/dividend/deposit/withdrawal per asset.';
COMMENT ON COLUMN investment_transactions.family_id IS 'Denormalized from investment_assets for RLS performance.';
COMMENT ON COLUMN investment_transactions.brl_amount IS 'Total BRL value at transaction date. Authoritative for tax purposes.';
COMMENT ON COLUMN investment_transactions.exchange_rate IS 'Rate used to convert original_currency → BRL at time of transaction.';
COMMENT ON COLUMN investment_transactions.fees_brl IS 'Included in brl_amount. Part of cost basis per Brazilian tax rules.';
