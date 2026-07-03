-- Aureo Studio — private JOB HUNT tracker table.
-- Run ONCE in Supabase → SQL Editor. Team-only (RLS): clients can never see it.
-- The Jobs page in the app renders an empty state until this exists, then works immediately.

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  role text not null,
  company text,
  location text,
  status text not null default 'applied',   -- applied / screening / interview / offer / rejected
  link text,
  notes text,
  priority text default 'normal',            -- 'high' = ★ dream role
  applied_at date,
  created_at timestamptz default now()
);

alter table public.jobs enable row level security;

drop policy if exists "jobs team all" on public.jobs;
create policy "jobs team all" on public.jobs
  for all using (public.is_team()) with check (public.is_team());
