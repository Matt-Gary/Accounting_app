# SaaS Architecture Plan — Family Accounting App

## Context
Transform the current single-tenant family accounting app into a multi-tenant SaaS product. The app tracks expenses (with credit card billing periods), recurring expenses, earnings, and investments. Currently it has no authentication, no tenant isolation, hardcoded credentials, and a single shared Supabase project. The goal is to onboard multiple families as paying clients while keeping the core logic intact.

---

# PHASE 1: Authentication & User Management

## 1.1 Supabase Auth Integration

**Current state**: No auth. App uses service_role key, fetches first profile, no login screen.

### Database changes
```sql
-- No new tables needed — Supabase Auth provides auth.users
-- But profiles must link to auth.users:
ALTER TABLE profiles ADD COLUMN auth_id UUID REFERENCES auth.users(id) UNIQUE;
```

### Backend changes (`backend/app.py`)
- Add auth middleware that extracts JWT from `Authorization: Bearer <token>` header
- Validate token against Supabase Auth (verify JWT signature using SUPABASE_JWT_SECRET)
- Extract `user_id` from token claims instead of accepting it as query parameter
- All routes become authenticated — remove `user_id` query params

```python
# New middleware: backend/middleware/auth.py
from functools import wraps
from flask import request, jsonify, g
import jwt

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        if not token:
            return jsonify({"error": "Missing auth token"}), 401
        try:
            payload = jwt.decode(token, SUPABASE_JWT_SECRET, algorithms=['HS256'], audience='authenticated')
            g.user_id = payload['sub']  # Supabase auth user ID
            g.family_id = get_family_id_for_user(g.user_id)  # Lookup from DB
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401
        return f(*args, **kwargs)
    return decorated
```

### Flutter changes
- **New screen**: `login_screen.dart` — Email/password login + signup
- **New screen**: `signup_screen.dart` — Registration with family creation
- `main.dart` — Check `Supabase.instance.client.auth.currentSession`, route to login or main
- `backend_service.dart` — Attach auth token to every HTTP request header
- `accounting_repository.dart` — Use authenticated Supabase client (already uses it, but with service_role key — must switch to anon key + user auth)
- `main.dart` — Replace service_role key with actual anon key

### Files to modify
- `mobile/lib/main.dart` — Switch to anon key, add auth check
- `mobile/lib/services/backend_service.dart` — Add auth header to all requests
- `mobile/lib/repositories/accounting_repository.dart` — Use authenticated client
- `mobile/lib/screens/main_screen.dart` — Add auth gate
- `backend/app.py` — Add auth middleware to all routes
- **New**: `backend/middleware/auth.py`
- **New**: `mobile/lib/screens/login_screen.dart`
- **New**: `mobile/lib/screens/signup_screen.dart`

---

# PHASE 2: Multi-Tenant Data Isolation (family_id)

## 2.1 New tables

```sql
-- Families (tenants)
CREATE TABLE families (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,               -- "The Smith Family"
    owner_id UUID REFERENCES auth.users(id) NOT NULL,
    default_currency TEXT NOT NULL DEFAULT 'BRL',
    currency_symbol TEXT NOT NULL DEFAULT 'R$',
    default_closing_day INT NOT NULL DEFAULT 23 CHECK (default_closing_day BETWEEN 1 AND 31),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Family membership (which users belong to which family)
CREATE TABLE family_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID REFERENCES families(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    display_name TEXT NOT NULL,       -- Name shown in the app
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(family_id, user_id)
);
```

## 2.2 Add family_id to ALL existing tables

```sql
-- Add family_id column to every data table
ALTER TABLE profiles ADD COLUMN family_id UUID REFERENCES families(id);
ALTER TABLE expenses ADD COLUMN family_id UUID REFERENCES families(id);
ALTER TABLE earnings ADD COLUMN family_id UUID REFERENCES families(id);
ALTER TABLE categories ADD COLUMN family_id UUID REFERENCES families(id);  -- Per-family categories
ALTER TABLE payment_methods ADD COLUMN family_id UUID REFERENCES families(id);  -- Per-family PMs
ALTER TABLE recurring_expenses ADD COLUMN family_id UUID REFERENCES families(id);
ALTER TABLE investments ADD COLUMN family_id UUID REFERENCES families(id);
ALTER TABLE closing_day_overrides ADD COLUMN family_id UUID REFERENCES families(id);

-- Update unique constraints to be family-scoped
ALTER TABLE closing_day_overrides DROP CONSTRAINT IF EXISTS closing_day_overrides_month_year_key;
ALTER TABLE closing_day_overrides ADD CONSTRAINT unique_family_month_year UNIQUE(family_id, month, year);

-- Create indexes for performance
CREATE INDEX idx_expenses_family ON expenses(family_id);
CREATE INDEX idx_earnings_family ON earnings(family_id);
CREATE INDEX idx_investments_family ON investments(family_id);
CREATE INDEX idx_recurring_family ON recurring_expenses(family_id);
CREATE INDEX idx_categories_family ON categories(family_id);
CREATE INDEX idx_payment_methods_family ON payment_methods(family_id);
```

## 2.3 Row Level Security (RLS) policies

```sql
-- Enable RLS on all tables
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE investments ENABLE ROW LEVEL SECURITY;
ALTER TABLE closing_day_overrides ENABLE ROW LEVEL SECURITY;

-- Helper function: get user's family_id
CREATE OR REPLACE FUNCTION get_user_family_id()
RETURNS UUID AS $$
    SELECT family_id FROM family_members WHERE user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Example policy (apply pattern to ALL tables):
CREATE POLICY "Users see own family data" ON expenses
    FOR ALL USING (family_id = get_user_family_id());

-- Repeat for: earnings, categories, payment_methods, recurring_expenses,
--             investments, closing_day_overrides
```

## 2.4 Backend changes

Every `fetch_expenses_for_period`, `fetch_earnings_for_period`, and all CRUD operations must filter by `family_id`:

```python
# In auth middleware, resolve family_id from JWT user
g.family_id = get_family_id_for_user(g.user_id)

# Every query adds:
.eq("family_id", g.family_id)

# Every insert adds:
new_exp["family_id"] = g.family_id
```

**Routes affected** (ALL routes in app.py):
- GET /dashboard — filter by family_id
- GET /report/monthly — filter by family_id
- DELETE /expenses/<id> — verify family_id ownership
- POST /earnings — set family_id
- GET/POST/PUT/DELETE /investments/* — filter by family_id
- GET/POST/PUT/DELETE /recurring-expenses/* — filter by family_id
- GET/POST/DELETE /closing-day-overrides — filter by family_id

### Files to modify
- `backend/app.py` — Add family_id filter to every route and query
- `backend/service/earnings_service.py` — Add family_id parameter
- `backend/service/closing_day_service.py` — Add family_id parameter
- `backend/service/investment_service.py` — Add family_id parameter
- `backend/service/billing_service.py` — No changes (pure logic, no DB)

---

# PHASE 3: Per-Family Configuration

## 3.1 Configurable settings (stored in `families` table)

| Setting | Column | Default | Purpose |
|---------|--------|---------|---------|
| Currency | `default_currency` | 'BRL' | Primary currency for expenses/earnings |
| Currency symbol | `currency_symbol` | 'R$' | Displayed in UI |
| Default closing day | `default_closing_day` | 23 | Credit card billing cutoff |
| Supported currencies | `supported_currencies` | ['BRL','USD','EUR','PLN'] | For investments |

```sql
ALTER TABLE families ADD COLUMN supported_currencies TEXT[] DEFAULT ARRAY['BRL','USD','EUR','PLN'];
```

## 3.2 Per-family categories and payment methods

Categories and payment methods become family-scoped. On family creation, seed with defaults:

```python
# backend/service/onboarding_service.py
def create_family(owner_id, family_name, currency='BRL', currency_symbol='R$'):
    """Called during signup — creates family + default data."""
    # 1. Create family
    family = insert_family(name=family_name, owner_id=owner_id,
                           default_currency=currency, currency_symbol=currency_symbol)
    # 2. Create owner membership
    insert_family_member(family_id=family['id'], user_id=owner_id,
                         role='owner', display_name=...)
    # 3. Seed default categories
    default_categories = [
        {'key': 'food', 'label': 'Food', 'sort_order': 1},
        {'key': 'transport', 'label': 'Transport', 'sort_order': 2},
        {'key': 'housing', 'label': 'Housing', 'sort_order': 3},
        {'key': 'health', 'label': 'Health', 'sort_order': 4},
        {'key': 'entertainment', 'label': 'Entertainment', 'sort_order': 5},
        {'key': 'other', 'label': 'Other', 'sort_order': 6},
    ]
    for cat in default_categories:
        cat['family_id'] = family['id']
        insert_category(cat)
    # 4. Seed default payment methods
    default_pms = [
        {'name': 'Cash', 'is_credit_card': False, 'closing_day': None},
        {'name': 'Credit Card', 'is_credit_card': True, 'closing_day': 23},
    ]
    for pm in default_pms:
        pm['family_id'] = family['id']
        insert_payment_method(pm)
    return family
```

## 3.3 Flutter changes for configuration

- Replace all hardcoded `'R$'` with family's `currency_symbol` from settings
- Replace default closing day `23` display with family's `default_closing_day`
- Load family settings on app startup, store in a provider/state

### New endpoints needed
```
GET    /family/settings          — Get current family config
PUT    /family/settings          — Update family config (owner/admin only)
POST   /family/members           — Invite member to family
DELETE /family/members/<user_id> — Remove member (owner only)
GET    /family/members           — List family members
POST   /family/categories        — Add custom category
PUT    /family/categories/<id>   — Edit category
DELETE /family/categories/<id>   — Delete category
POST   /family/payment-methods   — Add payment method
PUT    /family/payment-methods/<id> — Edit payment method
DELETE /family/payment-methods/<id> — Delete payment method
```

### Files to modify
- `mobile/lib/screens/home_screen.dart` — Replace `'R$'` with dynamic symbol
- `mobile/lib/screens/add_expense_screen.dart` — Replace `'R$ '` prefix
- `mobile/lib/screens/add_earning_screen.dart` — Replace `'R$ '` prefix
- `mobile/lib/screens/expense_details_screen.dart` — Replace `'R$'`
- `mobile/lib/screens/investments_screen.dart` — Replace currency references
- `mobile/lib/services/backend_service.dart` — Add family settings endpoint calls
- **New**: `mobile/lib/screens/family_settings_screen.dart`
- **New**: `mobile/lib/screens/manage_members_screen.dart`
- **New**: `mobile/lib/screens/manage_categories_screen.dart`
- **New**: `mobile/lib/screens/manage_payment_methods_screen.dart`
- **New**: `backend/service/onboarding_service.py`

---

# PHASE 4: Infrastructure & Deployment

## 4.1 Environment configuration

### Flutter — Flavor/Environment system
```dart
// lib/config/app_config.dart
class AppConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String backendUrl;

  static late AppConfig instance;

  // Load from environment or compile-time constants
  factory AppConfig.fromEnvironment() {
    return AppConfig(
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      backendUrl: const String.fromEnvironment('BACKEND_URL'),
    );
  }
}
```

Build commands:
```bash
# Dev
flutter run --dart-define=SUPABASE_URL=http://localhost:54321 --dart-define=BACKEND_URL=http://localhost:5000
# Prod
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=BACKEND_URL=https://api.yourapp.com
```

### Backend — Environment-based config
```python
# backend/config.py
import os
class Config:
    SUPABASE_URL = os.environ['SUPABASE_URL']
    SUPABASE_KEY = os.environ['SUPABASE_KEY']      # service_role for backend
    SUPABASE_JWT_SECRET = os.environ['SUPABASE_JWT_SECRET']
    CORS_ORIGINS = os.environ.get('CORS_ORIGINS', '*')
    DEBUG = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
```

## 4.2 Backend deployment

- **Current**: Single Flask instance on `72.60.137.97:5005`
- **Target**: Containerized with Docker, deployable to Railway/Fly.io/Render
- Add `Dockerfile`, `docker-compose.yml`
- Add CORS configuration (currently missing — needed for web clients)
- Add rate limiting (Flask-Limiter)
- Add request logging

## 4.3 Database migration strategy

Since existing data is for your family only:
1. Create the `families` and `family_members` tables
2. Create a family record for your current data
3. Backfill `family_id` on all existing rows
4. Add NOT NULL constraint after backfill
5. Create RLS policies
6. Switch Flutter app from service_role to anon key

```sql
-- Migration script
-- Step 1: Create tables (from Phase 2.1)

-- Step 2: Create family for existing data
INSERT INTO families (id, name, owner_id, default_currency, currency_symbol, default_closing_day)
VALUES ('YOUR_FAMILY_UUID', 'Mateusz Family', 'YOUR_AUTH_USER_ID', 'BRL', 'R$', 23);

-- Step 3: Link existing profiles to family
INSERT INTO family_members (family_id, user_id, role, display_name)
SELECT 'YOUR_FAMILY_UUID', auth_id, 'member', name FROM profiles;

-- Step 4: Backfill family_id on all tables
UPDATE expenses SET family_id = 'YOUR_FAMILY_UUID';
UPDATE earnings SET family_id = 'YOUR_FAMILY_UUID';
UPDATE categories SET family_id = 'YOUR_FAMILY_UUID';
UPDATE payment_methods SET family_id = 'YOUR_FAMILY_UUID';
UPDATE recurring_expenses SET family_id = 'YOUR_FAMILY_UUID';
UPDATE investments SET family_id = 'YOUR_FAMILY_UUID';
UPDATE closing_day_overrides SET family_id = 'YOUR_FAMILY_UUID';

-- Step 5: Add NOT NULL constraints
ALTER TABLE expenses ALTER COLUMN family_id SET NOT NULL;
ALTER TABLE earnings ALTER COLUMN family_id SET NOT NULL;
ALTER TABLE categories ALTER COLUMN family_id SET NOT NULL;
ALTER TABLE payment_methods ALTER COLUMN family_id SET NOT NULL;
ALTER TABLE recurring_expenses ALTER COLUMN family_id SET NOT NULL;
ALTER TABLE investments ALTER COLUMN family_id SET NOT NULL;
ALTER TABLE closing_day_overrides ALTER COLUMN family_id SET NOT NULL;

-- Step 6: Enable RLS (from Phase 2.3)
```

---

# PHASE 5: Billing & Subscription (Optional, for paid SaaS)

## 5.1 Stripe integration

```sql
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID REFERENCES families(id) UNIQUE NOT NULL,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'basic', 'premium')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'past_due', 'cancelled', 'trialing')),
    trial_ends_at TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

## 5.2 Plan limits

| Feature | Free | Basic | Premium |
|---------|------|-------|---------|
| Family members | 2 | 5 | Unlimited |
| Payment methods | 2 | 10 | Unlimited |
| Investments tracking | No | Yes | Yes |
| Monthly reports (Excel) | No | Yes | Yes |
| Custom categories | 6 (default) | 20 | Unlimited |

## 5.3 Enforcement

- Backend middleware checks subscription status on each request
- Returns 402 Payment Required if subscription expired
- Frontend shows upgrade prompts when limits reached

---

# PHASE 6: New Flutter Screens Summary

| Screen | Purpose | Phase |
|--------|---------|-------|
| `login_screen.dart` | Email/password login | 1 |
| `signup_screen.dart` | Registration + family creation | 1 |
| `family_settings_screen.dart` | Currency, closing day, family name | 3 |
| `manage_members_screen.dart` | Invite/remove family members | 3 |
| `manage_categories_screen.dart` | Add/edit/delete categories | 3 |
| `manage_payment_methods_screen.dart` | Add/edit/delete payment methods | 3 |
| `subscription_screen.dart` | Plan selection, Stripe checkout | 5 |

---

# IMPLEMENTATION ORDER

| Step | Phase | What | Effort |
|------|-------|------|--------|
| 1 | 4.3 | Database migration (add tables, backfill family_id) | Small |
| 2 | 1 | Supabase Auth + Login/Signup screens | Medium |
| 3 | 2 | Add family_id to all backend queries + RLS | Medium |
| 4 | 1+2 | Switch Flutter from service_role to anon key + auth headers | Small |
| 5 | 3.2 | Onboarding service (family creation + seed data) | Small |
| 6 | 3.1 | Per-family settings (currency, closing day) | Medium |
| 7 | 3.3 | Family management screens (members, categories, PMs) | Medium |
| 8 | 4.1 | Environment config (remove hardcoded values) | Small |
| 9 | 4.2 | Docker + deployment setup | Small |
| 10 | 5 | Stripe billing (optional) | Large |

---

# VERIFICATION CHECKLIST

1. Register new account → family created with default categories/PMs
2. Login with existing account → see only own family's data
3. Add family member → they see same family data
4. Create expense → family_id set correctly, visible to all family members
5. Change currency in settings → UI updates everywhere (no more hardcoded R$)
6. Set closing day → scoped to family, doesn't affect other families
7. Two different families → complete data isolation (no cross-visibility)
8. Switch from service_role to anon key → RLS enforces isolation at DB level
9. Generate report → matches dashboard data, scoped to family
10. (If billing) Subscription expires → access blocked with upgrade prompt
