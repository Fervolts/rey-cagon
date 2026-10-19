-- Accesorios del avatar (sombrero, lentes, mascota) y avatares extra que se desbloquean
-- con el total histórico de cagadas. El catálogo vive aquí y en lib/accesorios.dart.
create table public.desbloqueos (
  emoji text not null,
  ranura text not null check (ranura in ('avatar', 'sombrero', 'lentes', 'mascota')),
  minimo int not null check (minimo > 0),
  primary key (ranura, emoji)
);
alter table public.desbloqueos enable row level security;
create policy desbloqueos_read on public.desbloqueos for select to authenticated using (true);

insert into public.desbloqueos (ranura, emoji, minimo) values
  ('mascota', '🪰', 1), ('sombrero', '🧢', 3), ('lentes', '👓', 5), ('mascota', '🐛', 8),
  ('sombrero', '👒', 12), ('avatar', '👽', 15), ('lentes', '🕶️', 20), ('mascota', '🐀', 25),
  ('sombrero', '🎓', 30), ('avatar', '🤖', 40), ('mascota', '🪳', 50), ('sombrero', '🎩', 60),
  ('lentes', '🥽', 75), ('avatar', '🐲', 100), ('mascota', '🦨', 125), ('sombrero', '🪖', 150),
  ('avatar', '💎', 200), ('mascota', '🦆', 250), ('avatar', '🏆', 365);

alter table public.profiles
  add column sombrero text check (char_length(sombrero) <= 8),
  add column lentes text check (char_length(lentes) <= 8),
  add column mascota text check (char_length(mascota) <= 8);

-- Rechaza lo que el usuario todavía no ha desbloqueado. Los avatares que no están en
-- desbloqueos son gratis.
create function public.validar_desbloqueos() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  total bigint;
  r text;
  v text;
  antes text;
begin
  select count(*) into total from public.cagadas where user_id = new.id;
  foreach r in array array['avatar', 'sombrero', 'lentes', 'mascota'] loop
    v := case r when 'avatar' then new.avatar when 'sombrero' then new.sombrero
                when 'lentes' then new.lentes else new.mascota end;
    antes := case r when 'avatar' then old.avatar when 'sombrero' then old.sombrero
                    when 'lentes' then old.lentes else old.mascota end;
    -- Solo se valida lo que cambió: si deshaces cagadas no pierdes lo que ya tenías puesto.
    if v is null or v is not distinct from antes then continue; end if;
    if r <> 'avatar' and not exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v) then
      raise exception 'Accesorio desconocido' using errcode = '23514';
    end if;
    if exists (select 1 from public.desbloqueos d where d.ranura = r and d.emoji = v and d.minimo > total) then
      raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
    end if;
  end loop;
  return new;
end;
$$;
revoke execute on function public.validar_desbloqueos() from public, anon, authenticated;

create trigger validar_desbloqueos before update of avatar, sombrero, lentes, mascota on public.profiles
  for each row execute function public.validar_desbloqueos();

-- leaderboard y perfil devuelven también los accesorios.
drop function public.leaderboard(text, boolean);
create function public.leaderboard(period text, solo_siguiendo boolean default false)
returns table(user_id uuid, username text, avatar text, total bigint, sombrero text, lentes text, mascota text)
language sql stable set search_path = ''
as $$
  select p.id, p.username, p.avatar, count(c.id) as total, p.sombrero, p.lentes, p.mascota
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
  group by p.id
  order by total desc, p.username;
$$;
revoke execute on function public.leaderboard(text, boolean) from public, anon;
grant execute on function public.leaderboard(text, boolean) to authenticated;

drop function public.perfil(uuid);
create function public.perfil(uid uuid)
returns table(
  username text, avatar text, bio text, desde timestamptz,
  hoy bigint, semana bigint, mes bigint, anio bigint, total bigint,
  tipo_favorito smallint, seguidores bigint, siguiendo bigint, lo_sigo boolean,
  sombrero text, lentes text, mascota text
)
language sql stable set search_path = ''
as $$
  with c as (select created_at, tipo from public.cagadas where user_id = uid),
  t0 as (select now() at time zone 'America/Caracas' as ahora)
  select p.username, p.avatar, p.bio, p.created_at,
    (select count(*) from c, t0 where c.created_at >= date_trunc('day', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c, t0 where c.created_at >= date_trunc('week', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c, t0 where c.created_at >= date_trunc('month', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c, t0 where c.created_at >= date_trunc('year', t0.ahora) at time zone 'America/Caracas'),
    (select count(*) from c),
    (select tipo from c where tipo is not null group by tipo order by count(*) desc, tipo limit 1),
    (select count(*) from public.follows where followed = uid),
    (select count(*) from public.follows where follower = uid),
    exists (select 1 from public.follows where follower = (select auth.uid()) and followed = uid),
    p.sombrero, p.lentes, p.mascota
  from public.profiles p where p.id = uid;
$$;
revoke execute on function public.perfil(uuid) from public, anon;
grant execute on function public.perfil(uuid) to authenticated;

-- El ranking se refresca cuando alguien cambia avatar, accesorios o username.
alter publication supabase_realtime add table public.profiles;
