-- LiveFut TV - schema online per calendario ufficiale, live, telecronaca,
-- richieste contatto, blocco trasmissione e accrediti squadra.
-- Esegui tutto in Supabase > SQL Editor > New query > Run.

create extension if not exists pgcrypto;

alter table public.matches
  add column if not exists match_id text,
  add column if not exists competition_id text,
  add column if not exists source text default 'supabase',
  add column if not exists source_url text,
  add column if not exists match_date date,
  add column if not exists group_name text,
  add column if not exists age_group text,
  add column if not exists gender text,
  add column if not exists competition_type text,
  add column if not exists broadcaster_id uuid references auth.users(id),
  add column if not exists broadcast_started_at timestamptz,
  add column if not exists broadcast_ended_at timestamptz,
  add column if not exists updated_at timestamptz default now();

alter table public.matches
  alter column status set default 'soon';

alter table public.matches
  drop constraint if exists matches_status_check;

alter table public.matches
  add constraint matches_status_check
  check (status in ('soon', 'live', 'finished'));

create unique index if not exists matches_match_id_unique
  on public.matches (match_id)
  where match_id is not null;

create index if not exists matches_status_idx on public.matches (status);
create index if not exists matches_match_date_idx on public.matches (match_date);
create index if not exists matches_competition_id_idx on public.matches (competition_id);
create index if not exists matches_broadcaster_id_idx on public.matches (broadcaster_id);

alter table public.matches enable row level security;

drop policy if exists "matches are public readable" on public.matches;
create policy "matches are public readable"
  on public.matches for select
  using (true);

drop policy if exists "authenticated users create matches" on public.matches;
create policy "authenticated users create matches"
  on public.matches for insert
  to authenticated
  with check (
    broadcaster_id is null
    or broadcaster_id = auth.uid()
  );

drop policy if exists "authenticated users update matches" on public.matches;
drop policy if exists "broadcaster updates own matches" on public.matches;
create policy "broadcaster updates own matches"
  on public.matches for update
  to authenticated
  using (
    broadcaster_id is null
    or broadcaster_id = auth.uid()
  )
  with check (
    broadcaster_id is null
    or broadcaster_id = auth.uid()
  );

create table if not exists public.match_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.matches(id) on delete cascade,
  official_match_id text,
  event_type text not null,
  team_side text,
  team_name text,
  player_name text,
  assist_name text,
  card_type text,
  minute integer,
  score text,
  title text not null,
  body text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists match_events_match_id_idx on public.match_events (match_id, created_at desc);
create index if not exists match_events_official_match_id_idx on public.match_events (official_match_id, created_at desc);

create table if not exists public.broadcast_locks (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.matches(id) on delete cascade,
  official_match_id text,
  broadcaster_id uuid references auth.users(id),
  status text not null default 'active',
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists broadcast_locks_official_match_id_idx
  on public.broadcast_locks (official_match_id, status);

create unique index if not exists broadcast_locks_one_active_per_match
  on public.broadcast_locks (match_id)
  where status = 'active' and match_id is not null;

create unique index if not exists broadcast_locks_one_active_per_official_match
  on public.broadcast_locks (official_match_id)
  where status = 'active' and official_match_id is not null;

create table if not exists public.broadcaster_social_accounts (
  id uuid primary key default gen_random_uuid(),
  broadcaster_id uuid references auth.users(id) on delete cascade,
  provider text not null,
  display_name text,
  account_label text,
  status text not null default 'disconnected',
  connected_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (broadcaster_id, provider)
);

alter table public.broadcaster_social_accounts
  drop constraint if exists broadcaster_social_accounts_provider_check;

alter table public.broadcaster_social_accounts
  add constraint broadcaster_social_accounts_provider_check
  check (provider in ('youtube', 'facebook', 'twitch'));

alter table public.broadcaster_social_accounts
  drop constraint if exists broadcaster_social_accounts_status_check;

alter table public.broadcaster_social_accounts
  add constraint broadcaster_social_accounts_status_check
  check (status in ('connected', 'disconnected', 'pending', 'error'));

create index if not exists broadcaster_social_accounts_broadcaster_idx
  on public.broadcaster_social_accounts (broadcaster_id);

create table if not exists public.broadcast_destinations (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.matches(id) on delete cascade,
  official_match_id text,
  broadcaster_id uuid references auth.users(id) on delete cascade,
  provider text not null,
  enabled boolean not null default false,
  status text not null default 'inactive',
  error_message text,
  started_at timestamptz,
  ended_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.broadcast_destinations
  drop constraint if exists broadcast_destinations_provider_check;

alter table public.broadcast_destinations
  add constraint broadcast_destinations_provider_check
  check (provider in ('livefut', 'youtube', 'facebook', 'twitch'));

alter table public.broadcast_destinations
  drop constraint if exists broadcast_destinations_status_check;

alter table public.broadcast_destinations
  add constraint broadcast_destinations_status_check
  check (status in ('active', 'inactive', 'pending', 'error', 'finished'));

create unique index if not exists broadcast_destinations_unique_match_provider
  on public.broadcast_destinations (match_id, provider)
  where match_id is not null;

create index if not exists broadcast_destinations_broadcaster_idx
  on public.broadcast_destinations (broadcaster_id, created_at desc);

create table if not exists public.social_oauth_states (
  id uuid primary key default gen_random_uuid(),
  state text not null unique,
  broadcaster_id uuid references auth.users(id) on delete cascade,
  provider text not null,
  return_url text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.social_oauth_states
  drop constraint if exists social_oauth_states_provider_check;

alter table public.social_oauth_states
  add constraint social_oauth_states_provider_check
  check (provider in ('youtube', 'facebook', 'twitch'));

create index if not exists social_oauth_states_state_idx
  on public.social_oauth_states (state);

create index if not exists social_oauth_states_broadcaster_idx
  on public.social_oauth_states (broadcaster_id, created_at desc);

create table if not exists public.broadcaster_social_tokens (
  id uuid primary key default gen_random_uuid(),
  social_account_id uuid references public.broadcaster_social_accounts(id) on delete cascade,
  broadcaster_id uuid references auth.users(id) on delete cascade,
  provider text not null,
  access_token text,
  refresh_token text,
  token_type text,
  scope text,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (broadcaster_id, provider)
);

alter table public.broadcaster_social_tokens
  drop constraint if exists broadcaster_social_tokens_provider_check;

alter table public.broadcaster_social_tokens
  add constraint broadcaster_social_tokens_provider_check
  check (provider in ('youtube', 'facebook', 'twitch'));

create index if not exists broadcaster_social_tokens_account_idx
  on public.broadcaster_social_tokens (social_account_id);

create table if not exists public.contact_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  subject text not null,
  message text not null,
  page text,
  status text not null default 'new',
  created_at timestamptz not null default now()
);

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.matches(id) on delete set null,
  official_match_id text,
  requester_id uuid references auth.users(id),
  reason text not null,
  status text not null default 'new',
  created_at timestamptz not null default now()
);

create table if not exists public.accreditation_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  team_id text not null,
  team_name text not null,
  role text not null,
  notes text,
  status text not null default 'pending',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now()
);

alter table public.accreditation_requests
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_notes text;

alter table public.accreditation_requests
  drop constraint if exists accreditation_requests_role_check;

alter table public.accreditation_requests
  add constraint accreditation_requests_role_check
  check (role in (
    'presidente',
    'vice_presidente',
    'segretario',
    'amministratore',
    'delegato_dirette'
  ));

alter table public.accreditation_requests
  drop constraint if exists accreditation_requests_status_check;

alter table public.accreditation_requests
  add constraint accreditation_requests_status_check
  check (status in ('pending', 'approved', 'rejected'));

alter table public.match_events enable row level security;
alter table public.broadcast_locks enable row level security;
alter table public.broadcaster_social_accounts enable row level security;
alter table public.broadcast_destinations enable row level security;
alter table public.social_oauth_states enable row level security;
alter table public.broadcaster_social_tokens enable row level security;
alter table public.contact_requests enable row level security;
alter table public.support_requests enable row level security;
alter table public.accreditation_requests enable row level security;

drop policy if exists "match events are public readable" on public.match_events;
create policy "match events are public readable"
  on public.match_events for select
  using (true);

drop policy if exists "authenticated users create match events" on public.match_events;
drop policy if exists "broadcaster creates match events" on public.match_events;
create policy "broadcaster creates match events"
  on public.match_events for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and (
      match_id is null
      or exists (
        select 1
        from public.matches m
        where m.id = match_events.match_id
        and (
          m.broadcaster_id is null
          or m.broadcaster_id = auth.uid()
        )
      )
    )
  );

drop policy if exists "broadcast locks readable" on public.broadcast_locks;
create policy "broadcast locks readable"
  on public.broadcast_locks for select
  using (true);

drop policy if exists "authenticated users create broadcast locks" on public.broadcast_locks;
create policy "authenticated users create broadcast locks"
  on public.broadcast_locks for insert
  to authenticated
  with check (auth.uid() = broadcaster_id);

drop policy if exists "broadcaster updates own locks" on public.broadcast_locks;
create policy "broadcaster updates own locks"
  on public.broadcast_locks for update
  to authenticated
  using (auth.uid() = broadcaster_id)
  with check (auth.uid() = broadcaster_id);

drop policy if exists "broadcasters read own social accounts" on public.broadcaster_social_accounts;
create policy "broadcasters read own social accounts"
  on public.broadcaster_social_accounts for select
  to authenticated
  using (auth.uid() = broadcaster_id);

drop policy if exists "broadcasters create own social accounts" on public.broadcaster_social_accounts;
create policy "broadcasters create own social accounts"
  on public.broadcaster_social_accounts for insert
  to authenticated
  with check (auth.uid() = broadcaster_id);

drop policy if exists "broadcasters update own social accounts" on public.broadcaster_social_accounts;
create policy "broadcasters update own social accounts"
  on public.broadcaster_social_accounts for update
  to authenticated
  using (auth.uid() = broadcaster_id)
  with check (auth.uid() = broadcaster_id);

drop policy if exists "broadcasters read own destinations" on public.broadcast_destinations;
create policy "broadcasters read own destinations"
  on public.broadcast_destinations for select
  to authenticated
  using (auth.uid() = broadcaster_id);

drop policy if exists "broadcast destinations enabled public readable" on public.broadcast_destinations;
create policy "broadcast destinations enabled public readable"
  on public.broadcast_destinations for select
  using (
    enabled = true
    and status in ('active', 'pending', 'finished')
  );

drop policy if exists "broadcasters create own destinations" on public.broadcast_destinations;
create policy "broadcasters create own destinations"
  on public.broadcast_destinations for insert
  to authenticated
  with check (auth.uid() = broadcaster_id);

drop policy if exists "broadcasters update own destinations" on public.broadcast_destinations;
create policy "broadcasters update own destinations"
  on public.broadcast_destinations for update
  to authenticated
  using (auth.uid() = broadcaster_id)
  with check (auth.uid() = broadcaster_id);

drop policy if exists "anyone can create contact requests" on public.contact_requests;
create policy "anyone can create contact requests"
  on public.contact_requests for insert
  with check (true);

drop policy if exists "authenticated users create support requests" on public.support_requests;
create policy "authenticated users create support requests"
  on public.support_requests for insert
  to authenticated
  with check (auth.uid() = requester_id);

drop policy if exists "authenticated users create accreditation requests" on public.accreditation_requests;
create policy "authenticated users create accreditation requests"
  on public.accreditation_requests for insert
  to authenticated
  with check (auth.uid() = user_id);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'match_events'
  ) then
    alter publication supabase_realtime add table public.match_events;
  end if;
end $$;

notify pgrst, 'reload schema';
