-- Create a table for Earnings (Gainings)
create table if not exists earnings (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references profiles(id) not null,
  amount numeric not null,
  description text,
  earned_at timestamptz not null,
  created_at timestamptz default now()
);

-- Enable Row Level Security (RLS)
alter table earnings enable row level security;

-- Policy: Users can view their own earnings
create policy "Users can view own earnings"
on earnings for select
using (auth.uid() = user_id);

-- Policy: Users can insert their own earnings
create policy "Users can insert own earnings"
on earnings for insert
with check (auth.uid() = user_id);

-- Policy: Users can update their own earnings
create policy "Users can update own earnings"
on earnings for update
using (auth.uid() = user_id);

-- Policy: Users can delete their own earnings
create policy "Users can delete own earnings"
on earnings for delete
using (auth.uid() = user_id);
