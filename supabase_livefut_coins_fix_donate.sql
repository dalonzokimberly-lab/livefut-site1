-- ============================================================
-- LiveFut TV — supabase_livefut_coins_fix_donate.sql
-- 
-- Fix funzione donate_coins
-- 
-- Bug 1 (C5): riferimento ambiguo "public.coin_wallets.lifetime_received"
--   nell'ON CONFLICT DO UPDATE causava errore PostgreSQL a runtime.
--   Fix: rimosso prefisso schema, usato alias implicito "coin_wallets."
--
-- Bug 2: il broadcaster riceveva le monete in lifetime_received
--   ma il suo balance non veniva mai incrementato.
--   Fix: aggiunto "balance" nell'INSERT e nel DO UPDATE.
--
-- Applicata su Supabase Production il: 2026-06-02
-- ============================================================

CREATE OR REPLACE FUNCTION public.donate_coins(
  p_match_id uuid,
  p_official_match_id text,
  p_amount integer
)
RETURNS TABLE(
  donation_id       uuid,
  donor_id          uuid,
  broadcaster_id    uuid,
  match_id          uuid,
  official_match_id text,
  amount            integer,
  wallet_balance    integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_donor_id    uuid := auth.uid();
  v_match       public.matches%rowtype;
  v_wallet      public.coin_wallets%rowtype;
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

  -- Aggiorna eventuale ricarica settimanale pendente
  perform public.claim_weekly_coins();

  -- Leggi wallet donatore con lock di riga
  select *
  into v_wallet
  from public.coin_wallets cw
  where cw.user_id = v_donor_id
  for update;

  if v_wallet.balance < p_amount then
    raise exception 'Monete insufficienti.';
  end if;

  -- Scala monete dal donatore
  update public.coin_wallets
  set
    balance          = balance - p_amount,
    lifetime_donated = lifetime_donated + p_amount,
    updated_at       = now()
  where user_id = v_donor_id
  returning * into v_wallet;

  -- Accredita monete al broadcaster
  -- FIX BUG 1: "coin_wallets." invece di "public.coin_wallets." risolve l'ambiguità
  -- FIX BUG 2: aggiunto balance nell'INSERT e nel DO UPDATE
  insert into public.coin_wallets (user_id, balance, lifetime_received)
  values (v_match.broadcaster_id, p_amount, p_amount)
  on conflict (user_id) do update
    set
      balance           = coin_wallets.balance + excluded.balance,
      lifetime_received = coin_wallets.lifetime_received + excluded.lifetime_received,
      updated_at        = now();

  -- Registra la donazione
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

  -- Transazione lato donatore (monete uscenti)
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

  -- Transazione lato broadcaster (monete ricevute)
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
$function$;
