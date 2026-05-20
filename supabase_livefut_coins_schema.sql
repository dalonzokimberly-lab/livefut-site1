-- LiveFut TV - sistema monete MVP.
-- Monete fittizie per engagement: nessun pagamento reale.
-- Requisito: esegui prima supabase_livefut_admin_policies.sql, che crea public.is_livefut_admin().

create table if not exists public.coin_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance integer not null default 0,
  lifetime_granted integer not null default 0,
  lifetime_donated integer not null default 0,
  lifetime_received integer not null default 0,
  last_weekly_refill_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coin_wallets_balance_check check (balance >= 0 and balance <= 9),
  constraint coin_wallets_lifetime_granted_check check (lifetime_granted >= 0),
  constraint coin_wallets_lifetime_donated_check check (lifetime_donated >= 0),
  constraint coin_wallets_lifetime_received_check check (lifetime_received >= 0)
);

create table if not exists public.coin_donations (
  id uuid primary key default gen_random_uuid(),
  donor_id uuid not null references auth.users(id) on delete cascade,
  broadcaster_id uuid not null references auth.users(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  official_match_id text,
  amount integer not null,
  created_at timestamptz not null default now(),
  constraint coin_donations_amount_check check (amount between 1 and 3),
  constraint coin_donations_not_self_check check (donor_id <> broadcaster_id)
);

create table if not exists public.coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  amount integer not null,
  balance_after integer,
  match_id uuid references public.matches(id) on delete set null,
  official_match_id text,
  broadcaster_id uuid references auth.users(id) on delete set null,
  related_user_id uuid references auth.users(id) on delete set null,
  donation_id uuid references public.coin_donations(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint coin_transactions_amount_check check (amount > 0),
  constraint coin_transactions_type_check check (type in (
    'weekly_grant',
    'donation_sent',
    'donation_received',
    'admin_adjustment'
  ))
);

create index if not exists coin_wallets_updated_at_idx
  on public.coin_wallets (updated_at desc);

create index if not exists coin_donations_donor_idx
  on public.coin_donations (donor_id, created_at desc);

create index if not exists coin_donations_broadcaster_idx
  on public.coin_donations (broadcaster_id, created_at desc);

create index if not exists coin_donations_match_idx
  on public.coin_donations (match_id, created_at desc);

create index if not exists coin_donations_monthly_ranking_idx
  on public.coin_donations (created_at desc, broadcaster_id);

create index if not exists coin_transactions_user_idx
  on public.coin_transactions (user_id, created_at desc);

grant select on public.coin_wallets to authenticated;
grant select on public.coin_donations to authenticated;
grant select on public.coin_transactions to authenticated;

alter table public.coin_wallets enable row level security;
alter table public.coin_donations enable row level security;
alter table public.coin_transactions enable row level security;

drop policy if exists "coin wallets readable by owner or admin" on public.coin_wallets;
create policy "coin wallets readable by owner or admin"
  on public.coin_wallets for select
  to authenticated
  using (user_id = auth.uid() or public.is_livefut_admin());

drop policy if exists "coin donations readable by participants or admin" on public.coin_donations;
create policy "coin donations readable by participants or admin"
  on public.coin_donations for select
  to authenticated
  using (
    donor_id = auth.uid()
    or broadcaster_id = auth.uid()
    or public.is_livefut_admin()
  );

drop policy if exists "coin transactions readable by owner or admin" on public.coin_transactions;
create policy "coin transactions readable by owner or admin"
  on public.coin_transactions for select
  to authenticated
  using (
    user_id = auth.uid()
    or related_user_id = auth.uid()
    or broadcaster_id = auth.uid()
    or public.is_livefut_admin()
  );

create or replace function public.claim_weekly_coins()
returns table (
  user_id uuid,
  balance integer,
  granted integer,
  next_refill_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet public.coin_wallets%rowtype;
  v_week_start timestamptz := date_trunc('week', now());
  v_next_refill_at timestamptz := date_trunc('week', now()) + interval '1 week';
  v_granted integer := 0;
begin
  if v_user_id is null then
    raise exception 'Devi effettuare il login per usare le monete.';
  end if;

  insert into public.coin_wallets (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  select *
  into v_wallet
  from public.coin_wallets cw
  where cw.user_id = v_user_id
  for update;

  if v_wallet.last_weekly_refill_at is null
     or v_wallet.last_weekly_refill_at < v_week_start then
    v_granted := least(3, 9 - v_wallet.balance);

    update public.coin_wallets
    set
      balance = balance + v_granted,
      lifetime_granted = lifetime_granted + v_granted,
      last_weekly_refill_at = now(),
      updated_at = now()
    where coin_wallets.user_id = v_user_id
    returning * into v_wallet;

    if v_granted > 0 then
      insert into public.coin_transactions (
        user_id,
        type,
        amount,
        balance_after,
        metadata
      )
      values (
        v_user_id,
        'weekly_grant',
        v_granted,
        v_wallet.balance,
        jsonb_build_object('weekly_allowance', 3, 'max_balance', 9)
      );
    end if;
  end if;

  return query
  select v_user_id, v_wallet.balance, v_granted, v_next_refill_at;
end;
$$;

create or replace function public.get_my_coin_wallet()
returns table (
  user_id uuid,
  balance integer,
  lifetime_granted integer,
  lifetime_donated integer,
  lifetime_received integer,
  last_weekly_refill_at timestamptz,
  next_refill_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Devi effettuare il login per vedere le monete.';
  end if;

  perform public.claim_weekly_coins();

  return query
  select
    cw.user_id,
    cw.balance,
    cw.lifetime_granted,
    cw.lifetime_donated,
    cw.lifetime_received,
    cw.last_weekly_refill_at,
    date_trunc('week', now()) + interval '1 week'
  from public.coin_wallets cw
  where cw.user_id = v_user_id;
end;
$$;

create or replace function public.donate_coins(
  p_match_id uuid,
  p_official_match_id text,
  p_amount integer
)
returns table (
  donation_id uuid,
  donor_id uuid,
  broadcaster_id uuid,
  match_id uuid,
  official_match_id text,
  amount integer,
  wallet_balance integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_donor_id uuid := auth.uid();
  v_match public.matches%rowtype;
  v_wallet public.coin_wallets%rowtype;
  v_donation_id uuid;
begin
  if v_donor_id is null then
    raise exception 'Devi effettuare il login per donare monete.';
  end if;

  if p_amount is null or p_amount < 1 or p_amount > 3 then
    raise exception 'Puoi donare da 1 a 3 monete per volta.';
  end if;

  if p_match_id is null and nullif(trim(coalesce(p_official_match_id, '')), '') is null then
    raise exception 'Partita non valida.';
  end if;

  select *
  into v_match
  from public.matches m
  where (
    p_match_id is not null
    and m.id = p_match_id
  )
  or (
    p_match_id is null
    and p_official_match_id is not null
    and m.match_id = p_official_match_id
  )
  limit 1;

  if v_match.id is null then
    raise exception 'Partita non trovata.';
  end if;

  if v_match.status <> 'live' then
    raise exception 'Puoi donare monete solo durante una diretta live.';
  end if;

  if v_match.broadcaster_id is null then
    raise exception 'Questa partita non ha ancora un broadcaster assegnato.';
  end if;

  if v_match.broadcaster_id = v_donor_id then
    raise exception 'Non puoi donare monete a te stessa/o.';
  end if;

  perform public.claim_weekly_coins();

  select *
  into v_wallet
  from public.coin_wallets cw
  where cw.user_id = v_donor_id
  for update;

  if v_wallet.balance < p_amount then
    raise exception 'Monete insufficienti.';
  end if;

  update public.coin_wallets
  set
    balance = balance - p_amount,
    lifetime_donated = lifetime_donated + p_amount,
    updated_at = now()
  where coin_wallets.user_id = v_donor_id
  returning * into v_wallet;

  insert into public.coin_wallets (user_id, lifetime_received)
  values (v_match.broadcaster_id, p_amount)
  on conflict (user_id) do update
    set
      lifetime_received = public.coin_wallets.lifetime_received + excluded.lifetime_received,
      updated_at = now();

  insert into public.coin_donations (
    donor_id,
    broadcaster_id,
    match_id,
    official_match_id,
    amount
  )
  values (
    v_donor_id,
    v_match.broadcaster_id,
    v_match.id,
    v_match.match_id,
    p_amount
  )
  returning id into v_donation_id;

  insert into public.coin_transactions (
    user_id,
    type,
    amount,
    balance_after,
    match_id,
    official_match_id,
    broadcaster_id,
    related_user_id,
    donation_id
  )
  values (
    v_donor_id,
    'donation_sent',
    p_amount,
    v_wallet.balance,
    v_match.id,
    v_match.match_id,
    v_match.broadcaster_id,
    v_match.broadcaster_id,
    v_donation_id
  );

  insert into public.coin_transactions (
    user_id,
    type,
    amount,
    balance_after,
    match_id,
    official_match_id,
    broadcaster_id,
    related_user_id,
    donation_id
  )
  values (
    v_match.broadcaster_id,
    'donation_received',
    p_amount,
    null,
    v_match.id,
    v_match.match_id,
    v_match.broadcaster_id,
    v_donor_id,
    v_donation_id
  );

  return query
  select
    v_donation_id,
    v_donor_id,
    v_match.broadcaster_id,
    v_match.id,
    v_match.match_id,
    p_amount,
    v_wallet.balance;
end;
$$;

create or replace function public.get_monthly_broadcaster_ranking(
  p_month date default current_date
)
returns table (
  ranking_position bigint,
  broadcaster_id uuid,
  broadcaster_name text,
  coins_received bigint,
  donations_count bigint,
  live_count bigint
)
language sql
security definer
set search_path = public
as $$
  with bounds as (
    select
      date_trunc('month', coalesce(p_month, current_date)::timestamptz) as month_start,
      date_trunc('month', coalesce(p_month, current_date)::timestamptz) + interval '1 month' as month_end
  ),
  donations as (
    select
      d.broadcaster_id,
      sum(d.amount)::bigint as coins_received,
      count(*)::bigint as donations_count
    from public.coin_donations d
    cross join bounds b
    where d.created_at >= b.month_start
      and d.created_at < b.month_end
    group by d.broadcaster_id
  ),
  lives as (
    select
      m.broadcaster_id,
      count(distinct m.id)::bigint as live_count
    from public.matches m
    cross join bounds b
    where m.broadcaster_id is not null
      and coalesce(m.broadcast_started_at, m.livepeer_started_at, m.broadcast_ended_at, m.livepeer_ended_at, m.updated_at, now()) >= b.month_start
      and coalesce(m.broadcast_started_at, m.livepeer_started_at, m.broadcast_ended_at, m.livepeer_ended_at, m.updated_at, now()) < b.month_end
      and m.status in ('live', 'finished')
    group by m.broadcaster_id
  ),
  rows as (
    select
      d.broadcaster_id,
      coalesce(
        nullif(p.display_name, ''),
        nullif(p.username, ''),
        concat_ws(' ', nullif(p.first_name, ''), nullif(p.last_name, '')),
        'Broadcaster LiveFut'
      ) as broadcaster_name,
      d.coins_received,
      d.donations_count,
      coalesce(l.live_count, 0)::bigint as live_count
    from donations d
    left join lives l on l.broadcaster_id = d.broadcaster_id
    left join public.profiles p on p.id = d.broadcaster_id
  )
  select
    row_number() over (order by rows.coins_received desc, rows.live_count desc, rows.donations_count desc, rows.broadcaster_name asc) as ranking_position,
    rows.broadcaster_id,
    rows.broadcaster_name,
    rows.coins_received,
    rows.donations_count,
    rows.live_count
  from rows
  order by ranking_position;
$$;

grant execute on function public.claim_weekly_coins() to authenticated;
grant execute on function public.get_my_coin_wallet() to authenticated;
grant execute on function public.donate_coins(uuid, text, integer) to authenticated;
grant execute on function public.get_monthly_broadcaster_ranking(date) to authenticated;

notify pgrst, 'reload schema';
