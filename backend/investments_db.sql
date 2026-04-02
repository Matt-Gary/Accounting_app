-- Create a table for Investments
create table if not exists investments (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references profiles(id) not null,
  type text not null, -- 'stock', 'crypto', 'bond', 'cash', 'other'
  symbol text, -- Nullable, for Cash or custom
  name text not null,
  quantity numeric not null default 0,
  cost_basis numeric, -- Total cost basis or average price? Computed as Total Value / Quantity usually. Let's store Total Cost.
  currency text default 'BRL',
  created_at timestamptz default now()
);

-- Enable RLS
alter table investments enable row level security;

-- Policies
create policy "Users can view own investments"
on investments for select
using (auth.uid() = user_id);

create policy "Users can insert own investments"
on investments for insert
with check (auth.uid() = user_id);

create policy "Users can update own investments"
on investments for update
using (auth.uid() = user_id);

create policy "Users can delete own investments"
on investments for delete
using (auth.uid() = user_id);
