-- Muro v2: cada post trae género (para el título), racha de días seguidos, Cloaca y el último comentario.
-- Pestaña MI CLOACA (p_cloaca), trono del día (muro_trono) y aviso de grafitis nuevos (muro_nuevos).
-- muro_feed (apps viejas) no se toca. muro_feed_tarjetas solo la usa la app sin publicar: se recrea.

-- Días seguidos (hora de Caracas) con al menos una cagada, contando hoy o, si hoy no hay, desde ayer.
-- Una sonda por día sobre cagadas_user_created_idx; tope 366.
create function public.racha_dias(u uuid)
returns int language plpgsql stable set search_path = '' as $$
declare
  dia date := (now() at time zone 'America/Caracas')::date;
  n int := 0;
begin
  if not exists (select 1 from public.cagadas c
                 where c.user_id = u and c.created_at >= dia::timestamp at time zone 'America/Caracas') then
    dia := dia - 1;
  end if;
  while n < 366 and exists (select 1 from public.cagadas c
                            where c.user_id = u
                              and c.created_at >= dia::timestamp at time zone 'America/Caracas'
                              and c.created_at < (dia + 1)::timestamp at time zone 'America/Caracas') loop
    n := n + 1;
    dia := dia - 1;
  end loop;
  return n;
end $$;
revoke execute on function public.racha_dias(uuid) from public, anon, authenticated;

create type public.muro_fila as (
  id bigint, user_id uuid, texto text, dibujo jsonb, tarjeta jsonb, created_at timestamptz,
  likes bigint, yo_like boolean, comentarios bigint,
  username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real,
  genero text, racha int, cloaca_nombre text, cloaca_emoji text, top_nombre text, top_texto text
);

-- Arma las filas de unos posts ya filtrados. Interna: solo la llaman muro_feed_tarjetas y muro_trono.
create function public.muro_filas(p_ids bigint[])
returns setof public.muro_fila language sql stable set search_path = '' as $$
  with r as materialized (
    select a.user_id, public.racha_dias(a.user_id) as racha
    from (select distinct m.user_id from public.muro m where m.id = any(p_ids)) a
  )
  select m.id, m.user_id, m.texto, m.dibujo, m.tarjeta, m.created_at,
         (select count(*) from public.muro_likes l where l.post_id = m.id),
         exists (select 1 from public.muro_likes l where l.post_id = m.id and l.user_id = (select auth.uid())),
         (select count(*) from public.muro_comentarios c where c.post_id = m.id and not public.hay_bloqueo(c.user_id)),
         p.username, p.avatar, p.sombrero, p.lentes, p.mascota, p.cagadas,
         p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala,
         p.genero, r.racha, cl.nombre, cl.emoji, t.username, t.texto
  from public.muro m
  join public.profiles p on p.id = m.user_id
  join r on r.user_id = m.user_id
  left join public.cloaca_miembros cm on cm.user_id = m.user_id
  left join public.cloacas cl on cl.id = cm.cloaca_id
  left join lateral (
    select p2.username, c.texto
    from public.muro_comentarios c
    join public.profiles p2 on p2.id = c.user_id
    where c.post_id = m.id and not public.hay_bloqueo(c.user_id)
    order by c.created_at desc
    limit 1
  ) t on true
  where m.id = any(p_ids);
$$;
revoke execute on function public.muro_filas(bigint[]) from public, anon, authenticated;

drop function public.muro_feed_tarjetas(timestamptz, boolean, int);

create function public.muro_feed_tarjetas(p_antes timestamptz default null, p_amigos boolean default false,
                                          p_limite int default 20, p_cloaca boolean default false)
returns setof public.muro_fila language sql stable security definer set search_path = '' as $$
  select f.* from public.muro_filas(array(
    select m.id
    from public.muro m
    where (select auth.uid()) is not null
      and (p_antes is null or m.created_at < p_antes)
      and (not m.oculto or m.user_id = (select auth.uid()) or public.es_admin())
      and not public.hay_bloqueo(m.user_id)
      and (not p_amigos
           or m.user_id = (select auth.uid())
           or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = m.user_id))
      and (not p_cloaca
           or m.user_id in (select x.user_id from public.cloaca_miembros x
                            where x.cloaca_id = (select y.cloaca_id from public.cloaca_miembros y where y.user_id = (select auth.uid()))))
    order by m.created_at desc, m.id desc
    limit least(greatest(coalesce(p_limite, 20), 1), 50)
  )) f
  order by f.created_at desc, f.id desc;
$$;
revoke execute on function public.muro_feed_tarjetas(timestamptz, boolean, int, boolean) from public, anon;
grant execute on function public.muro_feed_tarjetas(timestamptz, boolean, int, boolean) to authenticated;

-- Trono de hoy: el dibujo de hoy (Caracas) con más 💩; nada si ninguno tiene. Empate: el primero en publicarse.
create function public.muro_trono()
returns setof public.muro_fila language sql stable security definer set search_path = '' as $$
  select f.* from public.muro_filas(array(
    select m.id
    from public.muro m
    join public.muro_likes l on l.post_id = m.id
    where (select auth.uid()) is not null
      and m.created_at >= date_trunc('day', now() at time zone 'America/Caracas') at time zone 'America/Caracas'
      and m.dibujo is not null and m.tarjeta is null and not m.oculto
      and not public.hay_bloqueo(m.user_id)
    group by m.id
    order by count(*) desc, min(m.created_at), m.id
    limit 1
  )) f;
$$;
revoke execute on function public.muro_trono() from public, anon;
grant execute on function public.muro_trono() to authenticated;

-- Cuántos posts de otros hay después de p_desde en la pestaña abierta (tope 100), para "↑ N GRAFITIS NUEVOS".
create function public.muro_nuevos(p_desde timestamptz, p_amigos boolean default false, p_cloaca boolean default false)
returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from (
    select 1
    from public.muro m
    where (select auth.uid()) is not null
      and m.created_at > p_desde
      and m.user_id <> (select auth.uid())
      and not m.oculto
      and not public.hay_bloqueo(m.user_id)
      and (not p_amigos
           or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = m.user_id))
      and (not p_cloaca
           or m.user_id in (select x.user_id from public.cloaca_miembros x
                            where x.cloaca_id = (select y.cloaca_id from public.cloaca_miembros y where y.user_id = (select auth.uid()))))
    limit 100
  ) n;
$$;
revoke execute on function public.muro_nuevos(timestamptz, boolean, boolean) from public, anon;
grant execute on function public.muro_nuevos(timestamptz, boolean, boolean) to authenticated;
