-- LiveFut TV - patch sicurezza post-QA.
-- Esegui questo file dopo supabase_livefut_admin_policies.sql.
-- Non rende private le partite: matches e match_events restano leggibili dagli spettatori.

drop policy if exists "authenticated users create matches" on public.matches;
create policy "authenticated users create matches"
  on public.matches for insert
  to authenticated
  with check (
    broadcaster_id = auth.uid()
    or public.is_livefut_admin()
  );

drop policy if exists "authenticated users update matches" on public.matches;
drop policy if exists "broadcaster updates own matches" on public.matches;
create policy "broadcaster updates own matches"
  on public.matches for update
  to authenticated
  using (
    broadcaster_id = auth.uid()
    or broadcaster_id is null
    or public.is_livefut_admin()
  )
  with check (
    broadcaster_id = auth.uid()
    or public.is_livefut_admin()
  );

drop policy if exists "authenticated users create match events" on public.match_events;
drop policy if exists "broadcaster creates match events" on public.match_events;
create policy "broadcaster creates match events"
  on public.match_events for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and (
      public.is_livefut_admin()
      or exists (
        select 1
        from public.matches m
        where m.id = match_events.match_id
          and m.broadcaster_id = auth.uid()
      )
      or exists (
        select 1
        from public.matches m
        where m.match_id = match_events.official_match_id
          and m.broadcaster_id = auth.uid()
      )
    )
  );

drop policy if exists "broadcast locks readable" on public.broadcast_locks;
create policy "broadcast locks readable"
  on public.broadcast_locks for select
  to authenticated
  using (auth.uid() = broadcaster_id or public.is_livefut_admin());

drop policy if exists "authenticated users create broadcast locks" on public.broadcast_locks;
create policy "authenticated users create broadcast locks"
  on public.broadcast_locks for insert
  to authenticated
  with check (
    auth.uid() = broadcaster_id
    and (
      public.is_livefut_admin()
      or exists (
        select 1
        from public.matches m
        where m.id = broadcast_locks.match_id
          and m.broadcaster_id = auth.uid()
      )
      or exists (
        select 1
        from public.matches m
        where m.match_id = broadcast_locks.official_match_id
          and m.broadcaster_id = auth.uid()
      )
    )
  );

drop policy if exists "broadcaster updates own locks" on public.broadcast_locks;
create policy "broadcaster updates own locks"
  on public.broadcast_locks for update
  to authenticated
  using (auth.uid() = broadcaster_id or public.is_livefut_admin())
  with check (auth.uid() = broadcaster_id or public.is_livefut_admin());

notify pgrst, 'reload schema';
