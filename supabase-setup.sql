-- Run once in Supabase Dashboard → SQL Editor.
-- Stores every completed flight. No account is required: the player supplies a nickname.
create table if not exists public.flappy_scores (
  id bigint generated always as identity primary key,
  nickname text not null check (char_length(nickname) between 1 and 28),
  score integer not null check (score >= 0),
  created_at timestamptz not null default now()
);

alter table public.flappy_scores enable row level security;

drop policy if exists "Anyone can add a flight" on public.flappy_scores;
create policy "Anyone can add a flight" on public.flappy_scores
for insert to anon with check (true);

drop policy if exists "Anyone can view all flights" on public.flappy_scores;
create policy "Anyone can view all flights" on public.flappy_scores
for select to anon using (true);

-- Run this section too: it reserves one nickname for one browser/device ID.
-- Existing score history remains unchanged.
create table if not exists public.flappy_players (
  nickname text primary key check (char_length(btrim(nickname)) between 1 and 28),
  device_id uuid not null unique,
  created_at timestamptz not null default now()
);

alter table public.flappy_players enable row level security;

drop policy if exists "Anyone can look up their device registration" on public.flappy_players;
create policy "Anyone can look up their device registration" on public.flappy_players
for select to anon using (true);

drop policy if exists "Anyone can reserve an unused nickname" on public.flappy_players;
create policy "Anyone can reserve an unused nickname" on public.flappy_players
for insert to anon with check (true);
