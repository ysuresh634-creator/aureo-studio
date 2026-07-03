-- Aureo Studio — HIDDEN FREELANCER pipeline. Run ONCE in Supabase SQL Editor.
-- Freelancers upload work to ONLY the projects they're assigned. They can NEVER
-- see the client's name, the client↔team thread, or any other project.
-- Clients never see that a freelancer exists — the work just appears as Aureo's.

-- 1) allow a third role
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('team','client','freelancer'));

-- 2) assign one freelancer to a project (internal only — never shown to the client)
alter table public.projects add column if not exists freelancer_id uuid references public.profiles(id) on delete set null;

-- 3) a change note the freelancer CAN see (passes client feedback without exposing the thread)
alter table public.deliverables add column if not exists change_note text;

-- 4) RLS — freelancers see ONLY their assigned projects' files & deliverables. No clients, no messages.
drop policy if exists "projects freelancer read"     on public.projects;
drop policy if exists "files freelancer read"        on public.files;
drop policy if exists "files freelancer write"       on public.files;
drop policy if exists "deliverables freelancer read"   on public.deliverables;
drop policy if exists "deliverables freelancer write"  on public.deliverables;
drop policy if exists "deliverables freelancer update" on public.deliverables;

create policy "projects freelancer read" on public.projects
  for select using (freelancer_id = auth.uid());

create policy "files freelancer read" on public.files for select using (
  exists (select 1 from public.projects p where p.id = project_id and p.freelancer_id = auth.uid()));
create policy "files freelancer write" on public.files for insert with check (
  exists (select 1 from public.projects p where p.id = project_id and p.freelancer_id = auth.uid()));

create policy "deliverables freelancer read" on public.deliverables for select using (
  exists (select 1 from public.projects p where p.id = project_id and p.freelancer_id = auth.uid()));
create policy "deliverables freelancer write" on public.deliverables for insert with check (
  exists (select 1 from public.projects p where p.id = project_id and p.freelancer_id = auth.uid()));
create policy "deliverables freelancer update" on public.deliverables for update using (
  exists (select 1 from public.projects p where p.id = project_id and p.freelancer_id = auth.uid())
) with check (
  exists (select 1 from public.projects p where p.id = project_id and p.freelancer_id = auth.uid()));

-- Note: clients + messages have NO freelancer policy → freelancers get nothing there.
-- That is what keeps the client identity and the client↔team thread invisible to them.
