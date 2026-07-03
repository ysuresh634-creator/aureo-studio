-- ═══════════════════════════════════════════════════════════════
--  AUREO STUDIO — ONE-TIME SETUP. Paste ALL of this into Supabase
--  → SQL Editor → New query → Run.  Safe to re-run (idempotent).
--  Turns on: Money (invoices/payouts/ledger/budgets/UPI+bank/plan),
--  Fixed bills, Jobs (+ your applications), and the Freelancer role.
-- ═══════════════════════════════════════════════════════════════

-- ========== MONEY + FIXED BILLS ==========
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
  upi_id text,                                -- your UPI VPA (e.g. yedukrishna@okhdfcbank) for pay links + QR
  payee_name text,                            -- name shown in the UPI app when a client pays
  bank_name text,                             -- bank name (fallback for large transfers)
  bank_account text,                          -- account number
  bank_ifsc text,                             -- IFSC code
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

-- Fixed / recurring monthly bills (Bike EMI, rent, subscriptions) — reserved in Safe-to-Spend
create table if not exists public.recurring (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  amount numeric not null,
  category text,
  day_of_month int,          -- optional due day (1-31)
  last_paid date,            -- set when you mark it paid; "due" again next month
  active boolean default true,
  created_at timestamptz default now()
);
alter table public.recurring enable row level security;
drop policy if exists "recurring team" on public.recurring;
create policy "recurring team" on public.recurring for all using (public.is_team()) with check (public.is_team());

-- ========== FREELANCER ROLE + RLS ==========
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

-- ========== JOBS TABLE + YOUR 71 APPLICATIONS ==========
-- Aureo Studio — Jobs page: create table + seed from Gmail (job applications + rejections).
-- Self-contained: run ONCE in Supabase SQL Editor. Creates the table, RLS, and fills it.
-- Team-only (private): clients can never see it.

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
create policy "jobs team all" on public.jobs for all using (public.is_team()) with check (public.is_team());

insert into public.jobs (role, company, location, status, priority, applied_at, notes) values
-- ══ INTERVIEW ══
('Videographer/Photographer + Social Media Strategist','XOXO Social (via Invicta India)','India','interview','high','2026-06-24','HOTTEST LEAD. Christina (christina@invictaindia.in) keen — applied for 2 of 3 roles. First call Jul 2. NEXT ROUND: interview with Darshan, Mon Jul 6, 10:30am IST (Google Meet, darshan@invictaindia.in). Prep!'),
('Video Editor','BNW','Dubai','interview','high','2026-06-26','Interview task received from Tania Andrew — 2 video tasks (editing, storytelling, creative). Submit the assignment.'),
('Marketing Executive','Via Anuj Chhabra (recruiter)',null,'interview','normal','2026-06-17','Interview held Jun 18, 3:30pm IST (Google Meet). They viewed yksproductions.com. Follow up on outcome.'),
-- ══ SCREENING ══
('Videographer & Editor','Samuel Leeds For Real Estate','UK','screening','normal','2026-06-23','TestGorilla assessment invited (Jun 23). Complete the assessment.'),
-- ══ APPLIED (role known) ══
('Influencer Marketing Specialist','Deconstruct','India','applied','normal','2026-06-24','Applied via LinkedIn.'),
('Brand Content Lead','Caliberly (Recruitment Agency)','Dubai','applied','normal','2026-06-24','Applied via LinkedIn (recruiter).'),
('Content Creator','RK Group','Dubai','applied','normal','2026-06-23','Applied via LinkedIn.'),
('Associate Producer (Production, Videographer, Content)','Big Ticket','Dubai','applied','normal','2026-06-26','Applied via LinkedIn.'),
('Videographer','Kristi B Visuals LLC','US','applied','normal','2026-06-23','Applied via LinkedIn. Employer viewed your application.'),
('Content Creator','Moshi Moshi (The Communication Company)','India','applied','normal','2026-06-22','Applied via LinkedIn.'),
('Social Media Manager','FutureLeap Search',null,'applied','normal','2026-06-15','Applied via LinkedIn (recruiter).'),
('Creative Associate','Galleri5 (Collective Artists Network)','India','applied','normal','2026-06-15','Applied via LinkedIn.'),
('Fitness Content Creator','Curefit','India','applied','normal','2026-06-15','Applied via LinkedIn.'),
('Videographer & Video Editor','Campus Sutra','India','applied','normal','2026-06-13','Applied via LinkedIn.'),
('Social Media Content Creator (J00518)','Arada Group','Dubai','applied','normal','2026-06-16','Application received (Darwinbox). Re-surfaced via LinkedIn Jul 2.'),
('Content / video role','PhonePe','India','applied','normal','2026-06-16','Application received confirmation. Under review.'),
('Videographer & Editor','Banana Club','India','applied','normal','2026-06-15','Application received. Under review.'),
-- ══ APPLIED (LinkedIn Easy Apply — role not stated in email; fill when known) ══
('—','Trivto',null,'applied','normal','2026-07-02','Applied via LinkedIn.'),
('—','Weekday AI (YC W21)',null,'applied','normal','2026-06-15','Applied via LinkedIn.'),
('—','Aditya Birla Fashion & Retail','India','applied','normal','2026-06-15','Applied via LinkedIn.'),
('—','Styli','Dubai','applied','normal','2026-06-13','Applied via LinkedIn.'),
('—','Jobgether',null,'applied','normal','2026-06-13','Applied via LinkedIn.'),
('—','Belong','India','applied','normal','2026-06-22','Applied via LinkedIn. Employer viewed.'),
('—','Business Development Incubator',null,'applied','normal','2026-06-19','Applied via LinkedIn. Employer viewed (Jul 3).'),
('—','Elite Globex','Dubai','applied','normal','2026-06-13','Applied via LinkedIn. Employer viewed.'),
('—','We One',null,'applied','normal','2026-06-23','Applied via LinkedIn.'),
('—','Shory','Dubai','applied','normal','2026-06-23','Applied via LinkedIn.'),
('—','Yuri Skinscience','India','applied','normal','2026-06-23','Applied via LinkedIn.'),
('—','HARP',null,'applied','normal','2026-06-22','Applied via LinkedIn.'),
('—','Gargash Enterprises','Dubai','applied','normal','2026-06-22','Applied via LinkedIn.'),
('—','Repair Official',null,'applied','normal','2026-06-17','Applied via LinkedIn.'),
('—','Awasa Real Estate LLC','Dubai','applied','normal','2026-06-23','Applied via LinkedIn. Employer viewed.'),
('—','KENSINGTON Finest Properties Dubai','Dubai','applied','normal','2026-06-13','Applied via LinkedIn.'),
('—','Savoir Prive Properties','Dubai','applied','normal','2026-06-13','Applied via LinkedIn.'),
('—','Net Real Estate Dubai','Dubai','applied','normal','2026-06-22','Applied via LinkedIn. Employer viewed.'),
('—','Faster Luxury Car Rental Dubai','Dubai','applied','normal','2026-06-14','Applied via LinkedIn. Employer viewed.'),
('—','Flow Medical Center & Physiotherapy','Dubai','applied','normal','2026-06-17','Applied via LinkedIn. Employer viewed.'),
('—','BIDllc',null,'applied','normal','2026-06-16','Applied via LinkedIn.'),
('—','Unique Homes Worldwide Properties','Dubai','applied','normal','2026-06-16','Applied via LinkedIn.'),
-- ══ REJECTED / CLOSED (Indeed + ATS, Aug 2025 → Jun 2026) ══
('Content Strategist','INNOVEX AGENCY',null,'rejected','normal','2026-06-11','Not selected (Indeed).'),
('F&B Content Producer','Marriott International','Dubai','rejected','normal','2026-06-11','Not selected (Req 26067107).'),
('Photographer & Content Creator','OGSI Oil & Gas Equipment FZE','Dubai','rejected','normal','2026-05-08','Not selected (Indeed).'),
('Social Media Manager','Fempowerment',null,'rejected','normal','2026-04-12','Not selected (Indeed).'),
('Video & Photographer (Healthcare)','Beijing Well-being Acupuncture Center',null,'rejected','normal','2026-03-28','Not selected (Indeed).'),
('Photographer / Videographer & Editor','MOOEi',null,'rejected','normal','2026-03-13','Not selected (Indeed).'),
('Videographer & Photographer','Storm Auto Mechanical Workshop','Dubai','rejected','normal','2025-11-19','Not selected (Indeed).'),
('Photographer','TROVE',null,'rejected','normal','2025-11-16','Not selected (Indeed).'),
('Digital Content Creator (F&B)','Rise Holding — Noir Cafe / Sasso','Dubai','rejected','normal','2025-10-02','Not selected (Indeed).'),
('Videographer & Editor','Infinite Imperial Ventures Real Estate','Dubai','rejected','normal','2025-09-24','Not selected (Indeed).'),
('Photographer/Videographer','Grand Flora Group','Dubai','rejected','normal','2025-09-19','Not selected (Indeed).'),
('Photography & Social Media Content Creator','Memzbites Sweets LLC','Dubai','rejected','normal','2025-09-19','Not selected (Indeed).'),
('Videographer','Hala Media',null,'rejected','normal','2025-09-16','Not selected (Indeed).'),
('Photographer/Videographer','Premier Estates','Dubai','rejected','normal','2025-09-13','Not selected (Indeed).'),
('Photographer/Videographer','GDS PRESTIGE FZC','Dubai','rejected','normal','2025-09-13','Not selected (Indeed).'),
('Videographer & Content Creator','Franck Provost','Dubai','rejected','normal','2025-09-12','Not selected (Indeed).'),
('Videographer & Editor','BALSAM DENTAL CENTER','Dubai','rejected','normal','2025-09-12','Not selected (Indeed).'),
('Social Media Content Creator (PT)','Experience by Marhaba','Dubai','rejected','normal','2025-09-05','Not selected (Indeed).'),
('Videographer','MS Holiday Homes','Dubai','rejected','normal','2025-09-04','Not selected (Indeed).'),
('Videographer cum Content Creator','Urban A2Z Trading','Dubai','rejected','normal','2025-09-03','Not selected (Indeed).'),
('Photographer/Videographer (Real Estate)','Downtown Brokers','Dubai','rejected','normal','2025-09-02','Not selected (Indeed).'),
('Digital Content Creator','Confidential',null,'rejected','normal','2025-09-02','Not selected (Indeed).'),
('Photographer/Videographer','Huaxia Real Estate Broker','Dubai','rejected','normal','2025-08-22','Not selected (Indeed).'),
('Videographer & Editor','Leon Grill Pvt Ltd','India','rejected','normal','2025-08-21','Not selected (Indeed).'),
('Content Creator / Videographer','Paulista Ladies Salon','Dubai','rejected','normal','2025-08-16','Not selected (Indeed).'),
('Videographer & Editor','AZCO Real Estate','Dubai','rejected','normal','2025-08-15','Not selected (Indeed).'),
('Videographer & Editor','Veer & Sant Real Estate LLC','Dubai','rejected','normal','2025-08-15','Not selected (Indeed).'),
('Content role','Creative Roots',null,'rejected','normal','2025-08-14','Not selected (Indeed).'),
('Photographer/Videographer','Dives Holding','Dubai','rejected','normal','2025-08-14','Not selected (Indeed).'),
('Photographer/Videographer','MOD Design Events LLC','Dubai','rejected','normal','2025-08-12','Not selected (Indeed).'),
('Photographer/Videographer/Editor','Auto Ak7','Dubai','rejected','normal','2025-08-08','Not selected (Indeed).'),
('Content Creator / Social Media Manager','Praana Luxury Leather Bags','India','rejected','normal','2025-08-05','Not selected (Indeed).');
