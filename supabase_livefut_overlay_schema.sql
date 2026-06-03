-- LiveFut TV - fix schema overlay spettatore e timer studio.
-- Esegui in Supabase > SQL Editor > New query > Run.

alter table public.matches
  add column if not exists timer_running boolean default false,
  add column if not exists elapsed_seconds_at_save integer default 0,
  add column if not exists timer_started_at timestamptz,
  add column if not exists overlay_visible boolean default true,
  add column if not exists overlay_scoreboard_visible boolean default true,
  add column if not exists overlay_primary text default '#ff4422',
  add column if not exists overlay_accent text default '#ff6600',
  add column if not exists overlay_font text default 'Barlow Condensed',
  add column if not exists overlay_scale numeric default 1,
  add column if not exists overlay_position text default 'top',
  add column if not exists overlay_updated_at timestamptz;

alter table public.matches
  drop constraint if exists matches_overlay_position_check;

alter table public.matches
  add constraint matches_overlay_position_check
  check (overlay_position in ('top', 'bottom'));

alter table public.matches
  drop constraint if exists matches_overlay_scale_check;

alter table public.matches
  add constraint matches_overlay_scale_check
  check (overlay_scale >= 0.5 and overlay_scale <= 2);

notify pgrst, 'reload schema';
