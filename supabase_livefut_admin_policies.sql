create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  role text not null default 'user',
  created_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists email text,
  add column if not exists display_name text,
  add column if not exists username text,
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists birth_date date,
  add column if not exists favorite_team text,
  add column if not exists city text,
  add column if not exists bio text,
  add column if not exists privacy_accepted boolean default false,
  add column if not exists role text not null default 'user',
  add column if not exists created_at timestamptz not null default now();

create or replace function public.is_livefut_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('admin', 'owner', 'superuser', 'super_admin')
  );
$$;

grant execute on function public.is_livefut_admin() to authenticated;

alter table public.profiles enable row level security;

drop policy if exists "profiles readable by owner or admin" on public.profiles;
create policy "profiles readable by owner or admin"
  on public.profiles for select
  to authenticated
  using (id = auth.uid() or public.is_livefut_admin());

drop policy if exists "profiles insert own profile" on public.profiles;
create policy "profiles insert own profile"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles update owner or admin" on public.profiles;
create policy "profiles update owner or admin"
  on public.profiles for update
  to authenticated
  using (id = auth.uid() or public.is_livefut_admin())
  with check (id = auth.uid() or public.is_livefut_admin());

drop policy if exists "admin reads accreditation requests" on public.accreditation_requests;
create policy "admin reads accreditation requests"
  on public.accreditation_requests for select
  to authenticated
  using (public.is_livefut_admin());

drop policy if exists "admin updates accreditation requests" on public.accreditation_requests;
create policy "admin updates accreditation requests"
  on public.accreditation_requests for update
  to authenticated
  using (public.is_livefut_admin())
  with check (public.is_livefut_admin());

drop policy if exists "admin reads contact requests" on public.contact_requests;
create policy "admin reads contact requests"
  on public.contact_requests for select
  to authenticated
  using (public.is_livefut_admin());

drop policy if exists "admin updates contact requests" on public.contact_requests;
create policy "admin updates contact requests"
  on public.contact_requests for update
  to authenticated
  using (public.is_livefut_admin())
  with check (public.is_livefut_admin());

drop policy if exists "admin reads support requests" on public.support_requests;
create policy "admin reads support requests"
  on public.support_requests for select
  to authenticated
  using (public.is_livefut_admin());

drop policy if exists "admin updates support requests" on public.support_requests;
create policy "admin updates support requests"
  on public.support_requests for update
  to authenticated
  using (public.is_livefut_admin())
  with check (public.is_livefut_admin());

drop policy if exists "admin reads broadcast locks" on public.broadcast_locks;
create policy "admin reads broadcast locks"
  on public.broadcast_locks for select
  to authenticated
  using (public.is_livefut_admin());

drop policy if exists "admin reads all match events" on public.match_events;
create policy "admin reads all match events"
  on public.match_events for select
  to authenticated
  using (public.is_livefut_admin());

drop policy if exists "admin updates matches" on public.matches;
create policy "admin updates matches"
  on public.matches for update
  to authenticated
  using (public.is_livefut_admin())
  with check (public.is_livefut_admin());

notify pgrst, 'reload schema';
