-- LiveFut TV - integrazione Livepeer per dirette reali.
-- Esegui in Supabase > SQL Editor > New query > Run.

alter table public.matches
  add column if not exists livepeer_stream_id text,
  add column if not exists livepeer_playback_id text,
  add column if not exists livepeer_status text default 'idle',
  add column if not exists livepeer_started_at timestamptz,
  add column if not exists livepeer_ended_at timestamptz;

create index if not exists matches_livepeer_stream_id_idx
  on public.matches (livepeer_stream_id)
  where livepeer_stream_id is not null;

notify pgrst, 'reload schema';
