-- Run once in Supabase Dashboard → SQL Editor.
-- Stores every completed flight. No account is required: the player supplies a nickname.
create table if not exists public.flappy_scores (
  id bigint generated always as identity primary key,
  nickname text not null check (char_length(nickname) between 1 and 28),
  score integer not null check (score >= 0),
  created_at timestamptz not null default now()
);

alter table public.flappy_scores enable row level security;

create policy "Anyone can add a flight" on public.flappy_scores
for insert to anon with check (true);

create policy "Anyone can view all flights" on public.flappy_scores
for select to anon using (true);
