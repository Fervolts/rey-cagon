-- Imperio social (fase 3, carril B):
--   * profiles.movimiento: el movimiento del avatar que se compró en la tienda de estilo (null = quieto).
--     Un trigger solo deja poner un mov_* que esté en imperio_estilos del usuario (o null / 'mov_ninguno').
--   * imperio_ranking(alcance, orden): amigos o global, por MJ de la partida o por Rollos de Oro.
--     imperio_ranking_amigos() se queda igual para las apps viejas.
--   * imperio_perfil(usuario): los números del Imperio para la tarjeta del perfil (null si nunca jugó).
--   * leaderboard() y perfil() devuelven también movimiento (columna nueva al final, las apps viejas la ignoran).
-- Va después de 20261106120000_imperio_estilos.sql (tabla imperio_estilos con las compras).

alter table public.profiles
  add column if not exists movimiento text check (char_length(movimiento) <= 32);
grant update (movimiento) on public.profiles to authenticated;

-- Solo se valida si cambió: si algún día se quita un estilo del catálogo, quien ya lo tiene puesto no pierde el perfil.
create or replace function public.validar_movimiento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.movimiento is null or new.movimiento = 'mov_ninguno' then return new; end if;
  if tg_op = 'UPDATE' and new.movimiento is not distinct from old.movimiento then return new; end if;
  if left(new.movimiento, 4) <> 'mov_'
     or not exists (select 1 from public.imperio_estilos e where e.user_id = new.id and e.id = new.movimiento) then
    raise exception 'Todavía no has comprado ese movimiento' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.validar_movimiento() from public, anon, authenticated;

drop trigger if exists validar_movimiento on public.profiles;
create trigger validar_movimiento before insert or update of movimiento on public.profiles
  for each row execute function public.validar_movimiento();

-- Rollos = los ganados en total (saldo + gastados): comprar en las tiendas no te baja del ranking.
-- Salen del estado que guarda el teléfono; imperio_numero cuenta 0 si no es un número (un estado raro no rompe el ranking).
-- Ranking del Imperio. p_alcance: 'amigos' (yo y la gente que sigo) o 'global'. p_orden: 'mj' o 'rollos'.
-- Los 100 primeros y, si quedo fuera, también mi fila con mi puesto real.
create or replace function public.imperio_ranking(p_alcance text default 'amigos', p_orden text default 'mj')
returns table(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
              lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real,
              mj_total double precision, rollos bigint, yo boolean, movimiento text, jaladas integer, puesto bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select p.id as uid, p.username as nombre, p.avatar as av, p.sombrero as so, p.lentes as le, p.mascota as ma,
           p.cagadas as ca, p.lentes_x as lx, p.lentes_y as ly, p.sombrero_x as sx, p.sombrero_y as sy,
           p.lentes_escala as le_e, p.sombrero_escala as so_e,
           coalesce(i.mj_total, 0) as mj, least(public.imperio_numero(i.estado->>'rollos') + public.imperio_numero(i.estado->>'rollos_gastados'), 1e15)::bigint as rl,
           p.id = (select auth.uid()) as es_yo, p.movimiento as mov, i.jaladas as ja
    from public.imperio i
    join public.profiles p on p.id = i.user_id
    where (select auth.uid()) is not null
      and p_alcance in ('amigos', 'global')
      and p_orden in ('mj', 'rollos')
      and (p_alcance = 'global'
           or p.id = (select auth.uid())
           or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
      and (p.id = (select auth.uid()) or i.mj_total > 0)
      and not public.hay_bloqueo(p.id)
  ),
  orden as (
    select b.*, row_number() over (order by case when p_orden = 'rollos' then b.rl else 0 end desc, b.mj desc, b.nombre) as n
    from base b
  )
  select o.uid, o.nombre, o.av, o.so, o.le, o.ma, o.ca, o.lx, o.ly, o.sx, o.sy, o.le_e, o.so_e,
         o.mj, o.rl, o.es_yo, o.mov, o.ja, o.n
  from orden o
  where o.n <= 100 or o.es_yo
  order by o.n;
$$;
revoke all on function public.imperio_ranking(text, text) from public, anon;
grant execute on function public.imperio_ranking(text, text) to authenticated;

-- Números del Imperio de alguien para su perfil. Null si no tiene Imperio, nunca jugó o hay bloqueo.
create or replace function public.imperio_perfil(p_usuario uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'mj_total', i.mj_total,
           'rollos', least(public.imperio_numero(i.estado->>'rollos') + public.imperio_numero(i.estado->>'rollos_gastados'), 1e15)::bigint,
           'jaladas', i.jaladas,
           'mps', i.mps,
           'movimiento', p.movimiento)
  from public.imperio i
  join public.profiles p on p.id = i.user_id
  where i.user_id = p_usuario
    and (select auth.uid()) is not null
    and (i.mj_total > 0 or i.jaladas > 0)
    and not public.hay_bloqueo(p_usuario);
$$;
revoke all on function public.imperio_perfil(uuid) from public, anon;
grant execute on function public.imperio_perfil(uuid) to authenticated;

-- leaderboard con movimiento al final (mismo cuerpo que 20261020171000_bloqueo_en_dos_sentidos.sql).
drop function public.leaderboard(text, boolean);
create function public.leaderboard(period text, solo_siguiendo boolean default false)
returns table(user_id uuid, username text, avatar text, total bigint, sombrero text, lentes text, mascota text,
              cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real,
              lentes_escala real, sombrero_escala real, movimiento text)
language sql
stable
set search_path = ''
as $$
  select p.id, p.username, p.avatar, count(c.id) as total, p.sombrero, p.lentes, p.mascota,
         p.cagadas, p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala, p.movimiento
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
    and not public.hay_bloqueo(p.id)
  group by p.id
  order by total desc, p.username;
$$;
revoke execute on function public.leaderboard(text, boolean) from public, anon;
grant execute on function public.leaderboard(text, boolean) to authenticated;

-- perfil con movimiento al final (mismo cuerpo que 20261019220000_tamano_accesorios.sql).
drop function public.perfil(uuid);
create function public.perfil(uid uuid)
returns table(
  username text, avatar text, bio text, desde timestamptz,
  hoy bigint, semana bigint, mes bigint, anio bigint, total bigint,
  tipo_favorito smallint, seguidores bigint, siguiendo bigint, lo_sigo boolean,
  sombrero text, lentes text, mascota text, cagadas int,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real,
  lentes_escala real, sombrero_escala real, movimiento text
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
    p.sombrero, p.lentes, p.mascota, p.cagadas,
    p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala, p.movimiento
  from public.profiles p where p.id = uid;
$$;
revoke execute on function public.perfil(uuid) from public, anon;
grant execute on function public.perfil(uuid) to authenticated;
