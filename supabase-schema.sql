-- ═══════════════════════════════════════════════════════════════════════
--  AUREO STUDIO — secure database schema  (run ONCE in Supabase SQL Editor)
--  Every privacy rule below is enforced by the DATABASE, not the browser.
--  A client literally cannot read another client's data, even if they try.
-- ═══════════════════════════════════════════════════════════════════════

-- ---------- TABLES ----------
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text,
  city text,
  created_at timestamptz default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'client' check (role in ('team','client')),
  client_id uuid references public.clients(id) on delete set null,
  name text,
  title text,
  created_at timestamptz default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  title text not null,
  type text,
  stage int not null default 0,
  created_at timestamptz default now()
);

create table if not exists public.deliverables (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null,
  emoji text,
  status text not null default 'draft',
  created_at timestamptz default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  sender_id uuid references auth.users(id),
  body text not null,
  created_at timestamptz default now()
);

-- ---------- HELPERS (security definer = safe, no RLS recursion) ----------
create or replace function public.is_team()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'team');
$$;

create or replace function public.my_client_id()
returns uuid language sql stable security definer set search_path = public as $$
  select client_id from public.profiles where id = auth.uid();
$$;

-- ---------- TURN ON ROW-LEVEL SECURITY EVERYWHERE ----------
alter table public.clients      enable row level security;
alter table public.profiles     enable row level security;
alter table public.projects     enable row level security;
alter table public.deliverables enable row level security;
alter table public.messages     enable row level security;

-- ---------- POLICIES ----------
-- PROFILES: you can read your own; team reads/manages all
create policy "profiles self read"  on public.profiles for select using (id = auth.uid() or public.is_team());
create policy "profiles team manage" on public.profiles for all using (public.is_team()) with check (public.is_team());

-- CLIENTS: team all; a client sees only its own brand row
create policy "clients read"  on public.clients for select using (public.is_team() or id = public.my_client_id());
create policy "clients write" on public.clients for all using (public.is_team()) with check (public.is_team());

-- PROJECTS: team all; a client sees only its own brand's projects
create policy "projects read"  on public.projects for select using (public.is_team() or client_id = public.my_client_id());
create policy "projects write" on public.projects for all using (public.is_team()) with check (public.is_team());

-- DELIVERABLES: read if team or belongs to my brand; team full write; client may update status on own only
create policy "deliverables read" on public.deliverables for select using (
  public.is_team() or exists (select 1 from public.projects p where p.id = project_id and p.client_id = public.my_client_id()));
create policy "deliverables write" on public.deliverables for all using (public.is_team()) with check (public.is_team());
create policy "deliverables client update" on public.deliverables for update using (
  exists (select 1 from public.projects p where p.id = project_id and p.client_id = public.my_client_id())
) with check (
  exists (select 1 from public.projects p where p.id = project_id and p.client_id = public.my_client_id()));

-- MESSAGES: read if team or my brand's project; insert only into own project, only as yourself
create policy "messages read" on public.messages for select using (
  public.is_team() or exists (select 1 from public.projects p where p.id = project_id and p.client_id = public.my_client_id()));
create policy "messages insert" on public.messages for insert with check (
  sender_id = auth.uid() and (
    public.is_team() or exists (select 1 from public.projects p where p.id = project_id and p.client_id = public.my_client_id())));

-- ---------- AUTO-PROFILE on signup (default = client, no brand → sees nothing until you assign) ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', new.email));
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Done. New sign-ups default to 'client' with NO brand attached (they see nothing).
-- You'll promote your own account to 'team' and attach each client to its brand
-- with a tiny follow-up snippet Claude gives you after login is wired.
