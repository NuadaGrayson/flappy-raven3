-- Run in Supabase Dashboard → SQL Editor.
-- Stores only the best score for each nickname.
create table if not exists public.flappy_scores (
  id bigint generated always as identity primary key,
  nickname text not null check (char_length(nickname) between 1 and 28),
  score integer not null check (score >= 0),
  created_at timestamptz not null default now()
);

alter table public.flappy_scores enable row level security;

-- Remove historical duplicate rows, keeping the highest score for every nickname.
-- If scores are tied, keep the oldest row.
delete from public.flappy_scores as older
using public.flappy_scores as better
where older.nickname = better.nickname
  and (
    older.score < better.score
    or (older.score = better.score and older.id > better.id)
  );

create unique index if not exists flappy_scores_nickname_key
on public.flappy_scores (nickname);

drop policy if exists "Anyone can add a flight" on public.flappy_scores;

drop policy if exists "Anyone can view all flights" on public.flappy_scores;
create policy "Anyone can view all flights" on public.flappy_scores
for select to anon using (true);

-- The browser calls this function after a flight. A lower score never replaces a higher one.
create or replace function public.submit_flappy_score(
  p_nickname text,
  p_score integer
)
returns integer
language sql
security definer
set search_path = public
as $$
  insert into public.flappy_scores (nickname, score)
  values (btrim(p_nickname), p_score)
  on conflict (nickname) do update
  set
    created_at = case
      when excluded.score > flappy_scores.score then now()
      else flappy_scores.created_at
    end,
    score = greatest(flappy_scores.score, excluded.score)
  returning score;
$$;

revoke all on function public.submit_flappy_score(text, integer) from public;
grant execute on function public.submit_flappy_score(text, integer) to anon, authenticated;

-- Run this section too: it reserves one nickname for one browser/device ID.
-- Existing player registrations remain unchanged.
create table if not exists public.flappy_players (
  nickname text primary key check (char_length(btrim(nickname)) between 1 and 28),
  device_id uuid not null unique,
  created_at timestamptz not null default now()
);

alter table public.flappy_players
add column if not exists house text;

alter table public.flappy_players
drop constraint if exists flappy_players_house_check;

alter table public.flappy_players
add constraint flappy_players_house_check
check (house is null or house in ('Гриффиндор', 'Слизерин', 'Пуффендуй', 'Когтевран'));

alter table public.flappy_players enable row level security;

drop policy if exists "Anyone can look up their device registration" on public.flappy_players;
drop policy if exists "Anyone can reserve an unused nickname" on public.flappy_players;

-- Atomically binds both nickname and house to one device.
-- Existing players with a null house may choose it once; after that it cannot change.
create or replace function public.reserve_flappy_player(
  p_nickname text,
  p_device_id uuid,
  p_house text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(regexp_replace(p_nickname, '\s+', ' ', 'g'));
  v_player public.flappy_players%rowtype;
begin
  if char_length(v_name) not between 1 and 28 then
    raise exception 'Введите имя и фамилию.';
  end if;

  if p_house not in ('Гриффиндор', 'Слизерин', 'Пуффендуй', 'Когтевран') then
    raise exception 'Выберите факультет.';
  end if;

  select * into v_player
  from public.flappy_players
  where device_id = p_device_id;

  if found then
    if v_player.nickname <> v_name then
      raise exception 'На этом устройстве уже закреплён ник «%».', v_player.nickname;
    end if;

    if v_player.house is null then
      update public.flappy_players set house = p_house where device_id = p_device_id;
      v_player.house := p_house;
    elsif v_player.house <> p_house then
      raise exception 'На этом устройстве уже закреплён факультет «%».', v_player.house;
    end if;

    return jsonb_build_object('nickname', v_player.nickname, 'house', v_player.house);
  end if;

  begin
    insert into public.flappy_players (nickname, device_id, house)
    values (v_name, p_device_id, p_house);
  exception when unique_violation then
    raise exception 'Это имя уже занято на другом устройстве.';
  end;

  return jsonb_build_object('nickname', v_name, 'house', p_house);
end;
$$;

revoke all on function public.reserve_flappy_player(text, uuid, text) from public;
grant execute on function public.reserve_flappy_player(text, uuid, text) to anon, authenticated;

-- Public leaderboard profile data without exposing device IDs.
create or replace function public.get_flappy_players()
returns table(player_nickname text, player_house text)
language sql
stable
security definer
set search_path = public
as $$
  select nickname, house from public.flappy_players;
$$;

revoke all on function public.get_flappy_players() from public;
grant execute on function public.get_flappy_players() to anon, authenticated;

create or replace function public.get_my_flappy_player(p_device_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('nickname', nickname, 'house', house)
  from public.flappy_players
  where device_id = p_device_id;
$$;

revoke all on function public.get_my_flappy_player(uuid) from public;
grant execute on function public.get_my_flappy_player(uuid) to anon, authenticated;
