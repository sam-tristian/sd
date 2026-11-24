-- =============================================================================
-- 00_setup_all.sql  -  TEST PROJECT ONLY
-- Paste this whole file into Supabase -> SQL Editor -> Run (once, on a NEW project).
-- It is the repo's migrations in filename order (0001 .. 0090), unchanged.
-- =============================================================================

-- ##### migrations/0001_local_stub_team1_identity.sql #####
-- =============================================================================
-- LOCAL DEV STUB - DO NOT MERGE - OWNED BY TEAM 2 ONLY FOR STANDALONE TESTING
-- =============================================================================
-- Stand-in for Team 1's real migration (0010_team1_identity.sql) so Team 2 can
-- run the complete booking flow alone on a local Supabase.
--
-- Delete this file as soon as the real Team 1 migration is in the repo.
-- It mirrors the frozen contract Team 2 depends on (Module Plan v4, section 12):
--   profiles(id, full_name, phone, role, active)   -> name + role for displays
--   user_role enum                                 -> customer/technician/admin (0024)
--   technicians(id, profile_id, skills, active)    -> booking form picker
--   is_admin(), my_role(), current_user_no()       -> Team 1 RLS helpers
-- =============================================================================

do $$
begin
  create type public.user_role as enum ('customer', 'technician', 'admin');
exception
  when duplicate_object then null;
end
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default 'Unnamed user',
  phone text,
  role public.user_role not null default 'customer',
  active boolean not null default true,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated on public.profiles
  for select to authenticated
  using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Users may edit only these columns; role and active change through the
-- admin-only functions in 0024 (set_user_role, set_user_active).
grant select on public.profiles to authenticated;
grant update (full_name, phone, avatar_url) on public.profiles to authenticated;

-- Auto-create a profile on signup (simplified version of Team 1's trigger).
create or replace function public.t1_stub_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    'customer'
  )
  on conflict (id) do nothing;
  return new;
end
$$;

drop trigger if exists t1_stub_on_auth_user_created on auth.users;
create trigger t1_stub_on_auth_user_created
  after insert on auth.users
  for each row execute function public.t1_stub_handle_new_user();

-- Team 1 RLS helper functions (Team 2 calls these, never edits them).
create or replace function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select p.role from public.profiles p where p.id = auth.uid()),
    'customer'::public.user_role
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select p.role = 'admin' and p.active from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

create or replace function public.current_user_no()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid();
$$;

grant execute on function public.my_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.current_user_no() to authenticated;

create table if not exists public.technicians (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles (id) on delete cascade,
  skills text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.technicians enable row level security;

drop policy if exists technicians_read_authenticated on public.technicians;
create policy technicians_read_authenticated on public.technicians
  for select to authenticated
  using (true);

drop policy if exists technicians_admin_write on public.technicians;
create policy technicians_admin_write on public.technicians
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant select, insert, update, delete on public.technicians to authenticated;

-- ##### migrations/0002_local_stub_team3_services.sql #####
-- =============================================================================
-- LOCAL DEV STUB - DO NOT MERGE - OWNED BY TEAM 2 ONLY FOR STANDALONE TESTING
-- =============================================================================
-- Stand-in for Team 3's real migration (0030_team3_repair_ops.sql) for the
-- services table, so the booking form has a menu + prices to read.
--
-- Delete this file as soon as the real Team 3 migration is in the repo.
-- Team 2 only READS this table (Module Plan v4, section 12).
-- =============================================================================

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  base_price numeric(10, 2) not null default 0 check (base_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.services enable row level security;

drop policy if exists services_read_authenticated on public.services;
create policy services_read_authenticated on public.services
  for select to authenticated
  using (true);

drop policy if exists services_admin_write on public.services;
create policy services_admin_write on public.services
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant select, insert, update, delete on public.services to authenticated;

-- ##### migrations/0020_team2_booking.sql #####
-- =============================================================================
-- KitaFix - migration 0020
-- Team 2 - Booking & Scheduling
-- Owner: Team 2 (rule R2: only Team 2 edits this file)
-- =============================================================================
--
-- WHAT THIS MIGRATION CREATES (Team 2 objects):
--   * public.repairs                          - booking columns + workflow
--                                               columns (frozen contract)
--   * repairs_no_double_booking               - EXCLUSION constraint: one
--                                               booking per location per hour
--   * RLS policies repairs_*_own              - customers only see/edit own
--   * public.repairs_guard_customer_update()  - customers may only cancel or
--                                               reschedule, never touch
--                                               workflow columns
--   * public.get_taken_slots()                - safe taken-hours lookup for the
--                                               booking form (no customer data)
--   * realtime publication for repairs        - live status on customer screen
--
-- FROZEN CONTRACT READ FROM OTHER TEAMS (do not change here):
--   profiles(id), technicians(id)   Team 1   0010_team1_identity.sql
--   services(id)                    Team 3   0030_team3_repair_ops.sql
--   public.is_staff()               Team 1   RLS helper (rule R5)
--   repair_status enum              Team 3   created guarded below so this file
--                                            also runs in the standalone repo
--
-- "Same hour" is modelled as a 1 hour slot starting at booking_time:
--   booking_slot = [date + time, date + time + 1 hour)
-- Two bookings at the same location whose slots overlap are rejected by the
-- database, even if two requests arrive at the same moment. The app only hides
-- taken hours to be friendly; the database is the source of truth
-- (Module Plan v4 trap: "No availability check").
-- =============================================================================

-- btree_gist lets an EXCLUDE constraint combine text equality (location) with a
-- range overlap test (booking_slot).
create extension if not exists btree_gist;

-- -----------------------------------------------------------------------------
-- Shared enum (Team 3 owns it; guarded so local stubs / merge order are safe)
-- -----------------------------------------------------------------------------
do $$
begin
  create type public.repair_status as enum
    ('pending', 'in_progress', 'testing', 'completed', 'cancelled');
exception
  when duplicate_object then null;
end
$$;

-- -----------------------------------------------------------------------------
-- repairs table
-- -----------------------------------------------------------------------------
create table if not exists public.repairs (
  id uuid primary key default gen_random_uuid(),

  -- booking columns (Team 2 writes these)
  customer_id uuid not null references public.profiles (id) on delete cascade,
  service_id uuid not null references public.services (id) on delete restrict,
  device_brand text not null,
  device_model text not null,
  location text not null,
  booking_date date not null,
  booking_time time not null,
  issue_screen boolean not null default false,
  issue_battery boolean not null default false,
  issue_charging boolean not null default false,
  issue_camera boolean not null default false,
  issue_audio boolean not null default false,
  issue_software boolean not null default false,

  -- workflow columns (Team 3 owns the values after creation; frozen contract)
  technician_id uuid references public.technicians (id) on delete set null,
  status public.repair_status not null default 'pending',
  staff_notes text,
  confirmed_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint repairs_device_brand_not_blank check (length(trim(device_brand)) > 0),
  constraint repairs_device_model_not_blank check (length(trim(device_model)) > 0),
  constraint repairs_location_not_blank check (length(trim(location)) > 0),
  constraint repairs_at_least_one_issue check (
    issue_screen
    or issue_battery
    or issue_charging
    or issue_camera
    or issue_audio
    or issue_software
  ),
  constraint repairs_booking_date_not_past check (booking_date >= current_date)
);

-- Merge-order safety: if the table already existed from another team's file,
-- add the missing columns instead of failing.
alter table public.repairs add column if not exists technician_id uuid references public.technicians (id) on delete set null;
alter table public.repairs add column if not exists status public.repair_status not null default 'pending';
alter table public.repairs add column if not exists staff_notes text;
alter table public.repairs add column if not exists confirmed_by uuid references public.profiles (id) on delete set null;
alter table public.repairs add column if not exists confirmed_at timestamptz;
alter table public.repairs add column if not exists created_at timestamptz not null default now();
alter table public.repairs add column if not exists updated_at timestamptz not null default now();

-- -----------------------------------------------------------------------------
-- Availability: the hour slot and the exclusion constraint
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'repairs'
      and column_name = 'booking_slot'
  ) then
    alter table public.repairs
      add column booking_slot tsrange
      generated always as (
        tsrange(
          booking_date + booking_time,
          booking_date + booking_time + interval '1 hour',
          '[)'
        )
      ) stored;
  end if;
end
$$;

-- Same location + overlapping hour + not cancelled = rejected.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'repairs_no_double_booking'
      and conrelid = 'public.repairs'::regclass
  ) then
    alter table public.repairs
      add constraint repairs_no_double_booking
      exclude using gist (location with =, booking_slot with &&)
      where (status <> 'cancelled');
  end if;
end
$$;

create index if not exists repairs_customer_idx on public.repairs (customer_id, booking_date desc);
create index if not exists repairs_location_date_idx on public.repairs (location, booking_date);

-- -----------------------------------------------------------------------------
-- updated_at
-- -----------------------------------------------------------------------------
create or replace function public.t2_repairs_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists t2_repairs_touch_updated_at on public.repairs;
create trigger t2_repairs_touch_updated_at
  before update on public.repairs
  for each row execute function public.t2_repairs_touch_updated_at();

-- -----------------------------------------------------------------------------
-- Customer write guard (required rule: cancel a completed repair must fail)
--
-- Team 3's status machine decides which STATUS changes are legal. This trigger
-- only decides which changes a CUSTOMER may send:
--   allowed: cancel (pending/in_progress), reschedule (pending only)
--   blocked: everything else, including any workflow column
-- Staff/admin (Team 3 portal) and SQL editor / service_role are untouched.
-- -----------------------------------------------------------------------------
create or replace function public.repairs_guard_customer_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- SQL editor, migrations and service_role have no customer session.
  if auth.uid() is null then
    return new;
  end if;

  -- Team 3 staff portal may change workflow columns.
  if public.is_staff() then
    return new;
  end if;

  -- From here on: the caller is a signed-in customer.
  if new.customer_id is distinct from old.customer_id then
    raise exception 'A booking cannot be moved to another customer.'
      using errcode = '42501';
  end if;

  if new.device_brand is distinct from old.device_brand
     or new.device_model is distinct from old.device_model
     or new.location is distinct from old.location
     or new.service_id is distinct from old.service_id
     or new.technician_id is distinct from old.technician_id
     or new.issue_screen is distinct from old.issue_screen
     or new.issue_battery is distinct from old.issue_battery
     or new.issue_charging is distinct from old.issue_charging
     or new.issue_camera is distinct from old.issue_camera
     or new.issue_audio is distinct from old.issue_audio
     or new.issue_software is distinct from old.issue_software
     or new.staff_notes is distinct from old.staff_notes
     or new.confirmed_by is distinct from old.confirmed_by
     or new.confirmed_at is distinct from old.confirmed_at then
    raise exception 'Customers may only change the date, the time, or cancel a booking.'
      using errcode = '42501';
  end if;

  if new.status is distinct from old.status and new.status <> 'cancelled' then
    raise exception 'Customers may only cancel a booking.'
      using errcode = '42501';
  end if;

  if old.status not in ('pending', 'in_progress') then
    raise exception 'This repair can no longer be changed by the customer.'
      using errcode = '42501';
  end if;

  if (new.booking_date is distinct from old.booking_date
      or new.booking_time is distinct from old.booking_time)
     and old.status <> 'pending' then
    raise exception 'Only a pending booking can be rescheduled.'
      using errcode = '42501';
  end if;

  return new;
end
$$;

drop trigger if exists repairs_guard_customer_update on public.repairs;
create trigger repairs_guard_customer_update
  before update on public.repairs
  for each row execute function public.repairs_guard_customer_update();

-- -----------------------------------------------------------------------------
-- RLS: Team 2 customer policies (Team 3 adds staff policies in 0030)
-- -----------------------------------------------------------------------------
alter table public.repairs enable row level security;

drop policy if exists repairs_select_own on public.repairs;
create policy repairs_select_own on public.repairs
  for select to authenticated
  using (customer_id = auth.uid());

drop policy if exists repairs_insert_own on public.repairs;
create policy repairs_insert_own on public.repairs
  for insert to authenticated
  with check (customer_id = auth.uid());

drop policy if exists repairs_update_own on public.repairs;
create policy repairs_update_own on public.repairs
  for update to authenticated
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

grant select, insert, update on public.repairs to authenticated;

-- -----------------------------------------------------------------------------
-- Taken hours for the booking form.
--
-- security definer on purpose: RLS hides other customers' rows from the caller,
-- but the form still needs to know which hours are busy. This function returns
-- ONLY time values - never customer data.
-- -----------------------------------------------------------------------------
create or replace function public.get_taken_slots(
  p_location text,
  p_date date,
  p_exclude_repair uuid default null
)
returns table (booking_time time)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.booking_time
  from public.repairs r
  where r.location = p_location
    and r.booking_date = p_date
    and r.status <> 'cancelled'
    and (p_exclude_repair is null or r.id <> p_exclude_repair)
  order by r.booking_time;
$$;

revoke all on function public.get_taken_slots(text, date, uuid) from public;
grant execute on function public.get_taken_slots(text, date, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Realtime: pushes status changes (Team 3) to the customer screen (Team 2).
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'repairs'
     ) then
    alter publication supabase_realtime add table public.repairs;
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- Ownership comments (handy when other teams inspect the schema)
-- -----------------------------------------------------------------------------
comment on table public.repairs is
  'KitaFix repair bookings. Team 2 owns booking columns and availability; Team 3 owns workflow columns (status, technician, notes, confirmed_*).';
comment on column public.repairs.customer_id is 'Team 2: booking column, the customer who made the booking.';
comment on column public.repairs.location is 'Team 2: booking column, shop branch. Availability is per location + hour.';
comment on column public.repairs.booking_date is 'Team 2: booking column, no past dates allowed.';
comment on column public.repairs.booking_time is 'Team 2: booking column, start of the 1 hour slot.';
comment on column public.repairs.booking_slot is 'Team 2: generated 1 hour tsrange used by repairs_no_double_booking.';
comment on column public.repairs.status is 'Team 3: workflow column. Frozen repair_status enum only.';
comment on column public.repairs.technician_id is 'Team 3: workflow column after creation; customer may request one at insert time.';
comment on column public.repairs.staff_notes is 'Team 3: workflow column, repair notes.';
comment on column public.repairs.confirmed_by is 'Team 3: workflow column, staff member who confirmed the booking.';
comment on column public.repairs.confirmed_at is 'Team 3: workflow column, when the booking was confirmed.';

-- ##### migrations/0021_team2_issue_description.sql #####
-- =============================================================================
-- KitaFix - migration 0021
-- Team 2 - Booking & Scheduling
-- Owner: Team 2 (rule R2: only Team 2 edits this file)
-- =============================================================================
--
-- WHY: the New Booking form replaced the six "What is wrong?" checkboxes with
-- one free-text description. This migration (additive, safe to re-run):
--   1. adds public.repairs.issue_description (nullable text, max 500 chars)
--   2. relaxes repairs_at_least_one_issue so a booking needs EITHER at least
--      one issue flag (old clients, old rows) OR a non-blank description
--   3. makes the customer update guard treat issue_description as a booking
--      column customers cannot edit afterwards (same as the six flags)
--
-- Existing rows and other teams' queries are unaffected: the new column is
-- nullable, and every row that passed the old constraint passes the new one.
-- 0020 is NOT edited (it is already applied on the shared project).
-- =============================================================================

-- 1. Column + length limit
alter table public.repairs add column if not exists issue_description text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'repairs_issue_description_length'
      and conrelid = 'public.repairs'::regclass
  ) then
    alter table public.repairs
      add constraint repairs_issue_description_length
      check (issue_description is null or length(issue_description) <= 500);
  end if;
end
$$;

-- 2. "At least one issue" now also accepts a written description
alter table public.repairs drop constraint if exists repairs_at_least_one_issue;
alter table public.repairs
  add constraint repairs_at_least_one_issue check (
    issue_screen
    or issue_battery
    or issue_charging
    or issue_camera
    or issue_audio
    or issue_software
    or length(trim(coalesce(issue_description, ''))) > 0
  );

-- 3. Customer write guard: identical to 0020 plus issue_description
create or replace function public.repairs_guard_customer_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- SQL editor, migrations and service_role have no customer session.
  if auth.uid() is null then
    return new;
  end if;

  -- Team 3 staff portal may change workflow columns.
  if public.is_staff() then
    return new;
  end if;

  -- From here on: the caller is a signed-in customer.
  if new.customer_id is distinct from old.customer_id then
    raise exception 'A booking cannot be moved to another customer.'
      using errcode = '42501';
  end if;

  if new.device_brand is distinct from old.device_brand
     or new.device_model is distinct from old.device_model
     or new.location is distinct from old.location
     or new.service_id is distinct from old.service_id
     or new.technician_id is distinct from old.technician_id
     or new.issue_screen is distinct from old.issue_screen
     or new.issue_battery is distinct from old.issue_battery
     or new.issue_charging is distinct from old.issue_charging
     or new.issue_camera is distinct from old.issue_camera
     or new.issue_audio is distinct from old.issue_audio
     or new.issue_software is distinct from old.issue_software
     or new.issue_description is distinct from old.issue_description
     or new.staff_notes is distinct from old.staff_notes
     or new.confirmed_by is distinct from old.confirmed_by
     or new.confirmed_at is distinct from old.confirmed_at then
    raise exception 'Customers may only change the date, the time, or cancel a booking.'
      using errcode = '42501';
  end if;

  if new.status is distinct from old.status and new.status <> 'cancelled' then
    raise exception 'Customers may only cancel a booking.'
      using errcode = '42501';
  end if;

  if old.status not in ('pending', 'in_progress') then
    raise exception 'This repair can no longer be changed by the customer.'
      using errcode = '42501';
  end if;

  if (new.booking_date is distinct from old.booking_date
      or new.booking_time is distinct from old.booking_time)
     and old.status <> 'pending' then
    raise exception 'Only a pending booking can be rescheduled.'
      using errcode = '42501';
  end if;

  return new;
end
$$;

comment on column public.repairs.issue_description is
  'Team 2: booking column, the customer''s own words for "what is wrong" (max 500 chars). Replaces the six issue_* checkboxes for new bookings; the flags stay for older rows.';

-- ##### migrations/0022_team2_hardening.sql #####
-- =============================================================================
-- KitaFix - migration 0022
-- Team 2 - Booking & Scheduling
-- Owner: Team 2 (rule R2: only Team 2 edits this file)
-- =============================================================================
--
-- WHY: the Supabase security advisor flagged three Team 2 objects. This
-- migration only tightens privileges and settings; no table, column, policy
-- or behaviour changes for signed-in customers. Safe to re-run.
--
--   1. t2_repairs_touch_updated_at had a role-mutable search_path.
--   2. get_taken_slots() could be called by anon. 0020 revoked it from PUBLIC,
--      but Supabase also grants EXECUTE on new public functions to anon and
--      authenticated directly, so anon kept access. Only signed-in customers
--      (the booking form) need it.
--   3. repairs_guard_customer_update() is a trigger function. Triggers fire
--      regardless of EXECUTE grants, so nobody needs to call it over the API.
--
-- Not changed here (other owners, rules R1/R5): is_staff(), my_role(),
-- current_user_no(), t1_stub_handle_new_user() (Team 1) and the btree_gist
-- extension in public (shared bootstrap).
-- =============================================================================

-- 1. Fixed search_path on the updated_at trigger function
alter function public.t2_repairs_touch_updated_at() set search_path = public, pg_temp;

-- 2. Free-slot lookup: signed-in users only
revoke execute on function public.get_taken_slots(text, date, uuid) from public, anon;
grant execute on function public.get_taken_slots(text, date, uuid) to authenticated;

-- 3. Guard trigger function: not callable over the API
revoke execute on function public.repairs_guard_customer_update() from public, anon, authenticated;

-- ##### migrations/0023_team2_booking_limits.sql #####
-- =============================================================================
-- KitaFix - migration 0023
-- Team 2 - Booking & Scheduling
-- Owner: Team 2 (rule R2: only Team 2 edits this file)
-- =============================================================================
--
-- 1. FIX: "no past dates" was a CHECK constraint (0020). Postgres re-checks a
--    CHECK on EVERY update of the row, so once a booking's date had passed,
--    nobody could update it any more - not the customer cancelling, and not
--    Team 3 moving it from in_progress to testing or completed. (A CHECK that
--    uses current_date also breaks pg_dump / restore.) It is now a trigger that
--    only looks at the date when a booking is made or moved.
--
-- 2. NEW: anti-spam limit. A customer may have at most 3 active repairs
--    (pending, in_progress or testing) at a time. A 4th booking is rejected
--    with SQLSTATE KF001; the app shows a friendly message and blocks the
--    form before that. Staff (Team 3 portal) and the SQL editor are not limited.
--    The app keeps the same number in MAX_ACTIVE_BOOKINGS (repair.model.ts).
--
-- 3. CLEAN-UP of bookings made before the limit existed:
--    a. pending bookings whose date has already passed (no-shows) -> cancelled
--    b. customers still over the limit: their oldest pending bookings ->
--       cancelled until 3 active remain.
--    in_progress / testing repairs are never touched (that is Team 3's work).
--
-- Safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Date rule: trigger instead of CHECK
-- -----------------------------------------------------------------------------
alter table public.repairs drop constraint if exists repairs_booking_date_not_past;

create or replace function public.repairs_booking_date_rule()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT'
     or new.booking_date is distinct from old.booking_date
     or new.booking_time is distinct from old.booking_time then
    if new.booking_date < current_date then
      -- 23514 = check_violation, so the app keeps showing the same message.
      raise exception 'The booking date cannot be in the past.'
        using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists repairs_booking_date_rule on public.repairs;
create trigger repairs_booking_date_rule
  before insert or update on public.repairs
  for each row execute function public.repairs_booking_date_rule();

revoke execute on function public.repairs_booking_date_rule() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. At most 3 active repairs per customer
-- -----------------------------------------------------------------------------
create or replace function public.repairs_limit_active_bookings()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  max_active constant integer := 3;
  active_count integer;
begin
  -- SQL editor, migrations, service_role and the staff portal are not limited.
  if auth.uid() is null or public.is_staff() then
    return new;
  end if;

  -- Two bookings sent at the same moment must not both see "2 active".
  perform pg_advisory_xact_lock(hashtextextended('t2_active_bookings:' || new.customer_id::text, 0));

  select count(*)
    into active_count
    from public.repairs r
   where r.customer_id = new.customer_id
     and r.status in ('pending', 'in_progress', 'testing');

  if active_count >= max_active then
    raise exception 'You already have % active repairs.', active_count
      using errcode = 'KF001',
            hint = 'Wait until one is finished, or cancel one, before booking again.';
  end if;

  return new;
end
$$;

drop trigger if exists repairs_limit_active_bookings on public.repairs;
create trigger repairs_limit_active_bookings
  before insert on public.repairs
  for each row execute function public.repairs_limit_active_bookings();

revoke execute on function public.repairs_limit_active_bookings() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. Clean-up of bookings made before the limit
-- -----------------------------------------------------------------------------
-- a. No-shows: still pending after their day.
update public.repairs
   set status = 'cancelled'
 where status = 'pending'
   and booking_date < current_date;

-- b. Still over the limit: cancel the oldest pending ones first.
with ranked as (
  select r.id,
         r.status,
         row_number() over (
           partition by r.customer_id
           order by (r.status = 'pending'), r.created_at desc
         ) as keep_rank
    from public.repairs r
   where r.status in ('pending', 'in_progress', 'testing')
)
update public.repairs r
   set status = 'cancelled'
  from ranked
 where r.id = ranked.id
   and ranked.status = 'pending'
   and ranked.keep_rank > 3;

comment on column public.repairs.booking_date is
  'Team 2: booking column. Must not be in the past when booked or moved (trigger repairs_booking_date_rule).';

-- ##### migrations/0024_merge_staff_into_admin.sql #####
-- =============================================================================
-- KitaFix - migration 0024
-- Group change (all four team leaders agreed): "staff" and "admin" are ONE role
-- Written by Team 2; Team 1 (profiles, roles), Team 3 (repair ops) and
-- Team 4 (admin portal) copy the same names into their real migrations (R10).
-- =============================================================================
--
-- 1. ROLES: user_role is now customer | technician | admin.
--    Every 'staff' profile becomes 'admin'. Postgres cannot remove an enum
--    value, so the type is rebuilt and the column converted.
--
-- 2. HELPER: is_staff() is replaced by is_admin(). All policies and Team 2
--    triggers now call is_admin(). Policies are renamed *_admin_* and call it
--    as (select public.is_admin()), so Postgres runs it once per query.
--
-- 3. SECURITY FIX: before this, a signed-in user could change their OWN role
--    (profiles_update_own + a table-wide UPDATE grant), so any customer could
--    make themselves admin. Users may now change only full_name, phone and
--    avatar_url. Role and active changes go through two admin-only functions:
--      set_user_role(target uuid, new_role user_role)
--      set_user_active(target uuid, is_active boolean)
--    An admin cannot change their own role or deactivate themselves, so the
--    shop cannot lose its last admin by accident.
--
-- Not changed: the column repairs.staff_notes keeps its name (Team 3 owns it,
-- and it means "notes by the shop", not a role).
--
-- Safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Roles: rebuild user_role without 'staff'
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1
      from pg_enum e
     where e.enumtypid = 'public.user_role'::regtype
       and e.enumlabel = 'staff'
  ) then
    -- my_role() returns the type, so it must go before the type can change.
    drop function if exists public.my_role();

    alter table public.profiles alter column role drop default;
    alter type public.user_role rename to user_role_old;
    create type public.user_role as enum ('customer', 'technician', 'admin');

    alter table public.profiles
      alter column role type public.user_role
      using (case role::text when 'staff' then 'admin' else role::text end)::public.user_role;

    alter table public.profiles alter column role set default 'customer';
    drop type public.user_role_old;
  end if;
end
$$;

create or replace function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select p.role from public.profiles p where p.id = auth.uid()),
    'customer'::public.user_role
  );
$$;

-- -----------------------------------------------------------------------------
-- 2. Helper: is_admin() replaces is_staff()
-- -----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select p.role = 'admin' and p.active from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

revoke execute on function public.my_role() from public, anon;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.my_role() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- technicians
drop policy if exists technicians_staff_write on public.technicians;
drop policy if exists technicians_admin_write on public.technicians;
create policy technicians_admin_write on public.technicians
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- services
drop policy if exists services_staff_write on public.services;
drop policy if exists services_admin_write on public.services;
create policy services_admin_write on public.services
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- repairs
drop policy if exists repairs_staff_select on public.repairs;
drop policy if exists repairs_admin_select on public.repairs;
create policy repairs_admin_select on public.repairs
  for select to authenticated
  using ((select public.is_admin()));

drop policy if exists repairs_staff_update on public.repairs;
drop policy if exists repairs_admin_update on public.repairs;
create policy repairs_admin_update on public.repairs
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Team 2 triggers: same rules as 0021 / 0023, now asking is_admin().
create or replace function public.repairs_guard_customer_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  -- The admin portal (Team 3 / Team 4) may change workflow columns.
  if public.is_admin() then
    return new;
  end if;

  if new.customer_id is distinct from old.customer_id then
    raise exception 'A booking cannot be moved to another customer.'
      using errcode = '42501';
  end if;

  if new.device_brand is distinct from old.device_brand
     or new.device_model is distinct from old.device_model
     or new.location is distinct from old.location
     or new.service_id is distinct from old.service_id
     or new.technician_id is distinct from old.technician_id
     or new.issue_screen is distinct from old.issue_screen
     or new.issue_battery is distinct from old.issue_battery
     or new.issue_charging is distinct from old.issue_charging
     or new.issue_camera is distinct from old.issue_camera
     or new.issue_audio is distinct from old.issue_audio
     or new.issue_software is distinct from old.issue_software
     or new.issue_description is distinct from old.issue_description
     or new.staff_notes is distinct from old.staff_notes
     or new.confirmed_by is distinct from old.confirmed_by
     or new.confirmed_at is distinct from old.confirmed_at then
    raise exception 'Customers may only change the date, the time, or cancel a booking.'
      using errcode = '42501';
  end if;

  if new.status is distinct from old.status and new.status <> 'cancelled' then
    raise exception 'Customers may only cancel a booking.'
      using errcode = '42501';
  end if;

  if old.status not in ('pending', 'in_progress') then
    raise exception 'This repair can no longer be changed by the customer.'
      using errcode = '42501';
  end if;

  if (new.booking_date is distinct from old.booking_date
      or new.booking_time is distinct from old.booking_time)
     and old.status <> 'pending' then
    raise exception 'Only a pending booking can be rescheduled.'
      using errcode = '42501';
  end if;

  return new;
end
$$;

create or replace function public.repairs_limit_active_bookings()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  max_active constant integer := 3;
  active_count integer;
begin
  -- SQL editor, migrations, service_role and the admin portal are not limited.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  -- Two bookings sent at the same moment must not both see "2 active".
  perform pg_advisory_xact_lock(hashtextextended('t2_active_bookings:' || new.customer_id::text, 0));

  select count(*)
    into active_count
    from public.repairs r
   where r.customer_id = new.customer_id
     and r.status in ('pending', 'in_progress', 'testing');

  if active_count >= max_active then
    raise exception 'You already have % active repairs.', active_count
      using errcode = 'KF001',
            hint = 'Wait until one is finished, or cancel one, before booking again.';
  end if;

  return new;
end
$$;

drop function if exists public.is_staff();

-- -----------------------------------------------------------------------------
-- 3. Security: users edit only their own name, phone and avatar
-- -----------------------------------------------------------------------------
revoke insert, update on public.profiles from anon, authenticated;
grant update (full_name, phone, avatar_url) on public.profiles to authenticated;

create or replace function public.set_user_role(target uuid, new_role public.user_role)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can change roles.' using errcode = '42501';
  end if;
  if target = auth.uid() then
    raise exception 'You cannot change your own role.' using errcode = '42501';
  end if;

  update public.profiles set role = new_role, updated_at = now() where id = target;
  if not found then
    raise exception 'No such user.' using errcode = 'P0002';
  end if;

  -- Keep the technicians list in step with the role.
  if new_role = 'technician' then
    insert into public.technicians (profile_id) values (target)
      on conflict (profile_id) do update set active = true, updated_at = now();
  else
    update public.technicians set active = false, updated_at = now()
     where profile_id = target and active;
  end if;
end
$$;

create or replace function public.set_user_active(target uuid, is_active boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can turn accounts on or off.' using errcode = '42501';
  end if;
  if target = auth.uid() then
    raise exception 'You cannot turn off your own account.' using errcode = '42501';
  end if;

  update public.profiles set active = is_active, updated_at = now() where id = target;
  if not found then
    raise exception 'No such user.' using errcode = 'P0002';
  end if;
end
$$;

revoke execute on function public.set_user_role(uuid, public.user_role) from public, anon;
revoke execute on function public.set_user_active(uuid, boolean) from public, anon;
grant execute on function public.set_user_role(uuid, public.user_role) to authenticated;
grant execute on function public.set_user_active(uuid, boolean) to authenticated;

comment on function public.is_admin() is 'Team 1 helper: true when the signed-in user is an active admin. Replaces is_staff() (0024).';
comment on function public.set_user_role(uuid, public.user_role) is 'Admin only. Changes another user''s role and keeps public.technicians in step.';
comment on function public.set_user_active(uuid, boolean) is 'Admin only. Turns another user''s account on or off.';
comment on column public.repairs.confirmed_by is 'Team 3: workflow column, admin who confirmed the booking.';

-- ##### migrations/0040_team4_insights.sql #####
-- =============================================================================
-- 0040_team4_insights.sql  -  Team 4: Feedback & Insights
-- =============================================================================
-- Owns : public.reviews + 3 report views.
-- Uses : public.repairs (Team 2/3), public.profiles + public.technicians
--        (Team 1), is_admin() / my_role() (Team 1 helpers: called, never edited).
--        Roles after migration 0024: customer | technician | admin (staff merged into admin).
-- Rules implemented (FSD v2.0):
--   1.1  Customer reviews only their OWN repair
--   1.3  Only a repair with status 'completed' can be reviewed
--   1.4  One review per repair (UNIQUE repair_id)
--   1.5  Rating 1-5 required, comment optional (max 200 chars)
--   1.6  One staff reply per review (reply_text, replied_by, replied_at)
--   1.7  created_at / updated_at timestamps
--   1.8  Customer may edit rating/comment only within 1 hour of created_at
--   1.9  Customer may delete only within 1 hour; admin may delete any time
--   3.x  v_repair_status_summary, v_technician_performance, v_review_summary
-- Safe to re-run (idempotent).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. reviews table
-- -----------------------------------------------------------------------------
create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  review_no   bigint generated always as identity,
  review_id   text generated always as ('RV-' || lpad(review_no::text, 5, '0')) stored,

  repair_id   uuid not null,
  customer_id uuid not null,

  rating      smallint not null,
  comment     text,

  reply_text  text,
  replied_by  uuid,
  replied_at  timestamptz,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint reviews_repair_id_key       unique (repair_id),
  constraint reviews_review_no_key       unique (review_no),
  constraint reviews_repair_id_fkey      foreign key (repair_id)   references public.repairs (id)  on delete cascade,
  constraint reviews_customer_id_fkey    foreign key (customer_id) references public.profiles (id) on delete cascade,
  constraint reviews_replied_by_fkey     foreign key (replied_by)  references public.profiles (id) on delete set null,
  constraint reviews_rating_range        check (rating between 1 and 5),
  constraint reviews_comment_max_200     check (comment is null or char_length(comment) <= 200),
  constraint reviews_reply_max_500       check (reply_text is null or char_length(reply_text) <= 500)
);

create index if not exists reviews_customer_idx on public.reviews (customer_id, created_at desc);
create index if not exists reviews_created_idx  on public.reviews (created_at desc);

comment on table  public.reviews is 'Team 4. One customer rating/comment per completed repair, plus one optional staff reply.';
comment on column public.reviews.review_id  is 'Display id, e.g. RV-00001 (computed from review_no).';
comment on column public.reviews.repair_id  is 'UNIQUE: a repair can only be reviewed once.';
comment on column public.reviews.replied_by is 'Staff profile that wrote the reply (set by trigger, not by the client).';

-- -----------------------------------------------------------------------------
-- 2. Triggers (business rules)
-- -----------------------------------------------------------------------------

-- 2a. Before INSERT: completed-only + own-repair-only, server-side timestamps.
create or replace function public.t4_reviews_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status public.repair_status;
  v_owner  uuid;
begin
  select r.status, r.customer_id
    into v_status, v_owner
  from public.repairs r
  where r.id = new.repair_id;

  if not found then
    raise exception 'Repair not found.' using errcode = '23503';
  end if;

  if v_status <> 'completed' then
    raise exception 'Only a completed repair can be reviewed.' using errcode = '23514';
  end if;

  if v_owner is distinct from new.customer_id then
    raise exception 'You can only review your own repair.' using errcode = '42501';
  end if;

  -- A signed-in client can never pre-fill the staff reply or backdate a review.
  if auth.uid() is not null then
    new.reply_text := null;
    new.replied_by := null;
    new.replied_at := null;
  end if;

  new.comment    := nullif(btrim(new.comment), '');
  new.created_at := now();
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists t4_reviews_before_insert on public.reviews;
create trigger t4_reviews_before_insert
  before insert on public.reviews
  for each row execute function public.t4_reviews_before_insert();

-- 2b. Before UPDATE: 1-hour edit window (customer) and single reply (staff).
create or replace function public.t4_reviews_before_update()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- SQL editor / migrations / service_role have no customer session: allowed.
  if auth.uid() is null then
    return new;
  end if;

  if new.id          is distinct from old.id
     or new.review_no   is distinct from old.review_no
     or new.repair_id   is distinct from old.repair_id
     or new.customer_id is distinct from old.customer_id
     or new.created_at  is distinct from old.created_at then
    raise exception 'The repair, the author and the creation time of a review cannot be changed.'
      using errcode = '42501';
  end if;

  -- Admin: reply only. They never edit the customer's words.
  if (select public.is_admin()) then
    if new.rating is distinct from old.rating
       or new.comment is distinct from old.comment then
      raise exception 'An administrator cannot edit a customer review. They can reply to it or delete it.'
        using errcode = '42501';
    end if;

    if new.reply_text is distinct from old.reply_text then
      if old.reply_text is not null then
        raise exception 'This review already has a reply.' using errcode = '23505';
      end if;
      if nullif(btrim(new.reply_text), '') is null then
        raise exception 'A reply cannot be empty.' using errcode = '23514';
      end if;
      new.reply_text := btrim(new.reply_text);
      new.replied_by := auth.uid();
      new.replied_at := now();
    else
      new.replied_by := old.replied_by;
      new.replied_at := old.replied_at;
    end if;
    return new;
  end if;

  -- Customer: only the author, only rating/comment, only within 1 hour.
  if old.customer_id is distinct from auth.uid() then
    raise exception 'You can only edit your own review.' using errcode = '42501';
  end if;

  if new.reply_text is distinct from old.reply_text
     or new.replied_by is distinct from old.replied_by
     or new.replied_at is distinct from old.replied_at then
    raise exception 'Customers cannot change the staff reply.' using errcode = '42501';
  end if;

  if now() > old.created_at + interval '1 hour' then
    raise exception 'Editing is only allowed within 1 hour of submitting the review.'
      using errcode = '42501';
  end if;

  new.comment    := nullif(btrim(new.comment), '');
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists t4_reviews_before_update on public.reviews;
create trigger t4_reviews_before_update
  before update on public.reviews
  for each row execute function public.t4_reviews_before_update();

-- 2c. Before DELETE: customer within 1 hour; admin any time (clear message).
create or replace function public.t4_reviews_before_delete()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or public.my_role() = 'admin' then
    return old;
  end if;

  if old.customer_id is distinct from auth.uid() then
    raise exception 'You can only delete your own review.' using errcode = '42501';
  end if;

  if now() > old.created_at + interval '1 hour' then
    raise exception 'This review can no longer be deleted by you. Ask an administrator to delete it.'
      using errcode = '42501';
  end if;

  return old;
end
$$;

drop trigger if exists t4_reviews_before_delete on public.reviews;
create trigger t4_reviews_before_delete
  before delete on public.reviews
  for each row execute function public.t4_reviews_before_delete();

-- -----------------------------------------------------------------------------
-- 3. Row Level Security
--    Postgres ORs policies together, so Team 2/3 policies on repairs and ours on
--    reviews never conflict.
-- -----------------------------------------------------------------------------
alter table public.reviews enable row level security;

-- Read: own reviews, or everything for an admin.
drop policy if exists reviews_select_own on public.reviews;
create policy reviews_select_own on public.reviews
  for select to authenticated
  using (customer_id = auth.uid());

drop policy if exists reviews_select_admin on public.reviews;
create policy reviews_select_admin on public.reviews
  for select to authenticated
  using ((select public.is_admin()));

-- Create: only as yourself (the trigger checks repair owner + completed).
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews
  for insert to authenticated
  with check (customer_id = auth.uid());

-- Update: author (1-hour rule in trigger) or admin (reply only, in trigger).
drop policy if exists reviews_update_own on public.reviews;
create policy reviews_update_own on public.reviews
  for update to authenticated
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

drop policy if exists reviews_update_admin on public.reviews;
create policy reviews_update_admin on public.reviews
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Delete: author (1-hour rule in trigger) or admin (any time).
drop policy if exists reviews_delete_own on public.reviews;
create policy reviews_delete_own on public.reviews
  for delete to authenticated
  using (customer_id = auth.uid());

drop policy if exists reviews_delete_admin on public.reviews;
create policy reviews_delete_admin on public.reviews
  for delete to authenticated
  using (public.my_role() = 'admin');

revoke all on public.reviews from anon;
grant select, insert, update, delete on public.reviews to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Report views (chart-ready). security_invoker = the caller's RLS applies,
--    so staff see everything and a customer only ever sees their own rows.
-- -----------------------------------------------------------------------------

-- 4a. Repairs per status (every status listed, even with 0 repairs).
create or replace view public.v_repair_status_summary
with (security_invoker = true) as
select
  s.status,
  count(r.id)::int as repair_count
from unnest(enum_range(null::public.repair_status)) as s(status)
left join public.repairs r on r.status = s.status
group by s.status
order by array_position(enum_range(null::public.repair_status), s.status);

-- 4b. Per technician: repairs handled, completed, review count, average rating.
--     Technicians with zero reviews still appear (average_rating is NULL).
create or replace view public.v_technician_performance
with (security_invoker = true) as
select
  t.id                                                          as technician_id,
  p.full_name                                                   as technician_name,
  count(distinct r.id)::int                                     as total_repairs,
  (count(distinct r.id) filter (where r.status = 'completed'))::int as completed_repairs,
  count(rv.id)::int                                             as review_count,
  round(avg(rv.rating), 2)                                      as average_rating
from public.technicians t
join public.profiles p        on p.id = t.profile_id
left join public.repairs r    on r.technician_id = t.id
left join public.reviews rv   on rv.repair_id = r.id
group by t.id, p.full_name;

-- 4c. Overall summary + star breakdown (always returns exactly one row).
create or replace view public.v_review_summary
with (security_invoker = true) as
select
  count(*)::int                                  as total_reviews,
  round(avg(rating), 2)                          as average_rating,
  (count(*) filter (where rating = 1))::int      as star_1,
  (count(*) filter (where rating = 2))::int      as star_2,
  (count(*) filter (where rating = 3))::int      as star_3,
  (count(*) filter (where rating = 4))::int      as star_4,
  (count(*) filter (where rating = 5))::int      as star_5
from public.reviews;

revoke all on public.v_repair_status_summary  from anon;
revoke all on public.v_technician_performance from anon;
revoke all on public.v_review_summary         from anon;
grant select on public.v_repair_status_summary  to authenticated;
grant select on public.v_technician_performance to authenticated;
grant select on public.v_review_summary         to authenticated;

comment on view public.v_repair_status_summary  is 'Team 4. Repairs grouped by status, for the status chart.';
comment on view public.v_technician_performance is 'Team 4. Per technician: total/completed repairs, review count, average rating.';
comment on view public.v_review_summary         is 'Team 4. Total reviews, average rating and 1-5 star counts.';

-- ##### migrations/0090_local_stub_team3_repairs_staff.sql #####
-- =============================================================================
-- LOCAL DEV STUB - DO NOT MERGE - OWNED BY TEAM 2 ONLY FOR STANDALONE TESTING
-- =============================================================================
-- Stand-in for the ADMIN policies and status trigger that Team 3 writes in
-- 0030_team3_repair_ops.sql (Admin Portal / Repair Queue).
--
-- Runs after 0020 (filename order) because the repairs table must exist.
-- It exists only so the standalone demo can also use the admin side
-- (e.g. change a status in the SQL editor or via the admin app) and so the
-- realtime test (status change -> customer screen updates) is possible.
--
-- Delete this file as soon as the real Team 3 migration is in the repo.
-- =============================================================================

-- Admins may read every repair (queue + dashboard counts).
drop policy if exists repairs_admin_select on public.repairs;
create policy repairs_admin_select on public.repairs
  for select to authenticated
  using ((select public.is_admin()));

-- Admins may update every repair (status, technician, notes, confirm).
drop policy if exists repairs_admin_update on public.repairs;
create policy repairs_admin_update on public.repairs
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Technicians may read repairs assigned to them.
drop policy if exists repairs_technician_select on public.repairs;
create policy repairs_technician_select on public.repairs
  for select to authenticated
  using (
    exists (
      select 1
      from public.technicians t
      where t.id = repairs.technician_id
        and t.profile_id = auth.uid()
    )
  );

grant select, insert, update on public.repairs to authenticated;
