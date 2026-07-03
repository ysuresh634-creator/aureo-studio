-- Aureo Studio — MONEY layer. Run ONCE in Supabase SQL Editor.
-- Everything here is TEAM-ONLY (private). Clients can never read any of it.

-- Client invoices (money IN)
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  amount numeric not null,
  currency text default 'INR',
  description text,
  kind text default 'full',                  -- full / advance (50% upfront) / balance (50% on delivery)
  status text not null default 'pending',    -- pending / paid / overdue
  issued_at date default now(),
  due_date date,
  paid_at date,
  created_at timestamptz default now()
);

-- Freelancer payouts (money OUT to freelancers)
create table if not exists public.payouts (
  id uuid primary key default gen_random_uuid(),
  freelancer text not null,
  project_id uuid references public.projects(id) on delete set null,
  amount numeric not null,
  currency text default 'INR',
  description text,
  status text not null default 'pending',    -- pending / paid
  due_date date,
  paid_at date,
  created_at timestamptz default now()
);

-- Personal ledger — every rupee in & out
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  txn_date date not null default now(),
  direction text not null default 'out',      -- in / out
  amount numeric not null,
  category text,                              -- Fuel / Food / Bike EMI / Rent / Client payment / Freelancer ...
  method text,                                -- PhonePe / GPay / Bank transfer / Cash / Card / UPI
  deductible boolean default false,           -- true = business expense claimable against ITR income
  note text,
  created_at timestamptz default now()
);

-- Monthly category budgets — drives the overspend alerts
create table if not exists public.budgets (
  category text primary key,
  monthly_limit numeric not null,
  created_at timestamptz default now()
);

-- Financial plan settings (single row) — powers Safe-to-Spend + savings + tax reserve
create table if not exists public.fin_settings (
  id boolean primary key default true,
  opening_balance numeric default 0,          -- your current total balance across accounts (reconcile anytime)
  monthly_savings_target numeric default 0,   -- pay-yourself-first amount per month
  tax_reserve_pct numeric default 0,          -- % of income to hold back for ITR/tax
  updated_at timestamptz default now(),
  constraint fin_singleton check (id)
);

alter table public.invoices     enable row level security;
alter table public.payouts      enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets      enable row level security;
alter table public.fin_settings enable row level security;

drop policy if exists "invoices team"     on public.invoices;
drop policy if exists "payouts team"      on public.payouts;
drop policy if exists "transactions team" on public.transactions;
drop policy if exists "budgets team"      on public.budgets;
drop policy if exists "fin_settings team" on public.fin_settings;

create policy "invoices team"     on public.invoices     for all using (public.is_team()) with check (public.is_team());
create policy "payouts team"      on public.payouts      for all using (public.is_team()) with check (public.is_team());
create policy "transactions team" on public.transactions for all using (public.is_team()) with check (public.is_team());
create policy "budgets team"      on public.budgets      for all using (public.is_team()) with check (public.is_team());
create policy "fin_settings team" on public.fin_settings for all using (public.is_team()) with check (public.is_team());
