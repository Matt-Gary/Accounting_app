-- Migration: Create closing_day_overrides table
-- Purpose: Store per-month closing day overrides for credit card billing cycles
-- Date: 2026-02-14

CREATE TABLE closing_day_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  month INT NOT NULL CHECK (month >= 1 AND month <= 12),
  year INT NOT NULL CHECK (year >= 2000),
  closing_day INT NOT NULL CHECK (closing_day >= 1 AND closing_day <= 31),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(month, year)
);

CREATE INDEX idx_month_year ON closing_day_overrides(month, year);

COMMENT ON TABLE closing_day_overrides IS 'Stores custom closing days for specific months/years';
COMMENT ON COLUMN closing_day_overrides.month IS 'Month (1-12)';
COMMENT ON COLUMN closing_day_overrides.year IS 'Year (e.g., 2026)';
COMMENT ON COLUMN closing_day_overrides.closing_day IS 'Day of month (1-31) when credit card billing cycle closes';
