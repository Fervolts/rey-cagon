create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 2 and 24),
  created_at timestamptz not null default now()
);

create table public.cagadas (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now()
);
create index cagadas_user_created_idx on public.cagadas (user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.cagadas enable row level security;

create policy "profiles_read" on public.profiles for select to authenticated using (true);
create policy "profiles_update_own" on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "cagadas_read" on public.cagadas for select to authenticated using (true);
create policy "cagadas_insert_own" on public.cagadas for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "cagadas_delete_own" on public.cagadas for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Crea el perfil al registrarse, con el username de user_metadata
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Ranking por periodo: 'week' | 'month' | 'quarter' | 'year'
create function public.leaderboard(period text)
returns table (user_id uuid, username text, total bigint)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.username, count(c.id) as total
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('week', 'month', 'quarter', 'year')
  group by p.id, p.username
  order by total desc, p.username;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.leaderboard(text) from public, anon;
grant execute on function public.leaderboard(text) to authenticated;
