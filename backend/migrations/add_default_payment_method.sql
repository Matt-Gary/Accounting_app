ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS default_payment_method_id UUID
    REFERENCES payment_methods(id)
    ON DELETE SET NULL;
