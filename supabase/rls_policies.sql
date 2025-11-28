-- Supabase Row Level Security (RLS) setup
-- Run this in Supabase SQL Editor (Project → SQL → New query)

-- 1) Profiles table (1:1 with auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  first_name text,
  last_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Always keep RLS enabled for user data
alter table public.profiles enable row level security;

-- Optional: keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- Policies: users can manage only their own profile
drop policy if exists "Select own profile" on public.profiles;
create policy "Select own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Insert own profile" on public.profiles;
create policy "Insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "Update own profile" on public.profiles;
create policy "Update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- 2) Auto-create a profile row when a new user signs up (optional, recommended)
-- Requires privileges to read new.raw_user_meta_data
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, first_name, last_name)
  values (
    new.id,
    new.email,
    coalesce((new.raw_user_meta_data ->> 'first_name'), null),
    coalesce((new.raw_user_meta_data ->> 'last_name'), null)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3) Example: user-owned table with RLS
create table if not exists public.conversation_logs (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb,
  created_at timestamptz default now()
);

alter table public.conversation_logs enable row level security;

drop policy if exists "Select own conversation_logs" on public.conversation_logs;
create policy "Select own conversation_logs"
  on public.conversation_logs for select
  using (auth.uid() = user_id);

drop policy if exists "Insert own conversation_logs" on public.conversation_logs;
create policy "Insert own conversation_logs"
  on public.conversation_logs for insert
  with check (auth.uid() = user_id);

drop policy if exists "Update own conversation_logs" on public.conversation_logs;
create policy "Update own conversation_logs"
  on public.conversation_logs for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- (Optional) Usually we do not allow deletes; add if you need it
-- create policy "Delete own conversation_logs"
--   on public.conversation_logs for delete
--   using (auth.uid() = user_id);

-- Notes:
-- - auth.uid() comes from the JWT in the client request (user's ID)
-- - These policies apply for the anon/service role depending on the API key used.
-- - Use the client session access token (not just anon key) to ensure auth.uid() is present.

-- 4) Session-level observability
create table if not exists public.session_recordings (
  id uuid primary key default gen_random_uuid(),
  session_id text not null unique,
  user_id uuid references auth.users(id) on delete set null,
  user_email text, -- denormalized for easy querying
  events jsonb not null default '[]'::jsonb, -- ordered array of session events
  metadata jsonb not null default '{}'::jsonb, -- device/app/location metadata
  last_known_location jsonb, -- { "latitude": Double, "longitude": Double, "accuracyMeters": Double }
  started_at timestamptz default now(),
  ended_at timestamptz,
  error_summary text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.session_recordings enable row level security;

drop trigger if exists trg_session_recordings_updated_at on public.session_recordings;
create trigger trg_session_recordings_updated_at
before update on public.session_recordings
for each row execute function public.set_updated_at();

create index if not exists idx_session_recordings_user_id on public.session_recordings(user_id);
create index if not exists idx_session_recordings_session_id on public.session_recordings(session_id);

drop policy if exists "Select own session recordings" on public.session_recordings;
create policy "Select own session recordings"
  on public.session_recordings for select
  using (user_id is not distinct from auth.uid());

drop policy if exists "Insert session recordings" on public.session_recordings;
create policy "Insert session recordings"
  on public.session_recordings for insert
  with check (
    user_id is null
    or user_id is not distinct from auth.uid()
  );

drop policy if exists "Update own session recordings" on public.session_recordings;
create policy "Update own session recordings"
  on public.session_recordings for update
  using (user_id is null or user_id is not distinct from auth.uid())
  with check (user_id is null or user_id is not distinct from auth.uid());


