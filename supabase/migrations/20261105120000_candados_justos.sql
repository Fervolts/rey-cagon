-- Candados y cadena más justos para quien caga poco, y empujones para quien se queda atrás.
--   * Tope de cagadas por día local (flag cagadas_dia_tope, 3 por defecto) para candados y cadena:
--     cagar 10 veces un día no adelanta 10 días de juego.
--   * Pases: cada día de la racha reclamado suma un pase; dos pases cuentan como una cagada para los candados.
--   * Empujón: x2 de producción por 30 min una vez por semana a quien va por debajo del 25% de su grupo
--     (jugadores de antigüedad y ritmo de cagadas parecidos). Lo cobra imperio_progreso() al abrir.
--   * push_poceta_revisar(): avisos nuevos (regalo de vuelta, empujón, candado cerca, cadena lista, cagada fresca).
--     Sigue siendo uno por persona y por día, con el mismo interruptor de la poceta.

alter table public.imperio
  add column if not exists pases integer not null default 0,
  add column if not exists empujon_en timestamptz,
  add column if not exists empujon_cobrado boolean not null default true,
  add column if not exists empujon_revisado date;

-- Cagadas por día que cuentan para candados y cadena.
create or replace function public.imperio_tope_dia()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select least(greatest(round((f.valor #>> '{}')::numeric), 1), 100)::int
    from public.imperio_flags f
    where f.clave = 'cagadas_dia_tope' and f.activo and jsonb_typeof(f.valor) = 'number'
  ), 3);
$$;

-- Cagadas desde p_desde (null = todas) con el tope por día local de esa persona.
create or replace function public.imperio_cagadas_tope(p_uid uuid, p_desde timestamptz)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  with z as (select public.imperio_zona(p_uid) as zona, public.imperio_tope_dia() as tope),
  dias as (
    select count(*) as n
      from public.cagadas c, z
     where c.user_id = p_uid and (p_desde is null or c.created_at > p_desde)
     group by (c.created_at at time zone z.zona)::date
  )
  select coalesce(sum(least(d.n, z.tope)), 0)::bigint from dias d, z;
$$;

create or replace function public.imperio_cadena()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  n bigint;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid;
  if fila.user_id is null then
    return jsonb_build_object('cagadas', 0, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', 0);
  end if;
  n := public.imperio_cagadas_tope(uid, coalesce(fila.jalada_en, fila.creado));
  return jsonb_build_object('cagadas', n, 'necesarias', public.imperio_cadena_necesarias(), 'jaladas', fila.jaladas);
end;
$$;

create or replace function public.imperio_jalar()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  n bigint;
  total int;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if fila.user_id is null then
    raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
  end if;
  n := public.imperio_cagadas_tope(uid, coalesce(fila.jalada_en, fila.creado));
  if n < public.imperio_cadena_necesarias() then
    raise exception 'Todavía te faltan cagadas para jalar la cadena' using errcode = 'P0001';
  end if;
  -- La mejora se compra una vez y la jalada la borra del estado: después de la primera ya no se pide.
  if fila.jaladas = 0 and not (jsonb_typeof(fila.estado -> 'mejoras') = 'array' and (fila.estado -> 'mejoras') ? 'cadena_trono') then
    raise exception 'Todavía no tienes La cadena del trono' using errcode = 'P0001';
  end if;
  update public.imperio set jalada_en = now(), jaladas = jaladas + 1 where user_id = uid
    returning jaladas into total;
  return jsonb_build_object('jaladas', total);
end;
$$;

-- Igual que antes, más un pase por cada día reclamado.
create or replace function public.imperio_reclamar_racha(p_fecha date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  v_dia int;
  v_cir int;
  v_ficha boolean;
  v_falta int;
  v_cong int := 0;
  dio_ficha boolean := false;
  -- índice = día (1..30)
  cir_por_dia int[] := array[0,0,1,0,0,2,3,0,0,3, 0,0,4,5,0,0,5,0,0,6, 8,0,0,8,0,0,10,12,0,25];
  ficha_dias int[] := array[7,14,21,28];
begin
  if uid is null then raise exception 'no autenticado'; end if;
  if p_fecha is null or abs(p_fecha - (now() at time zone 'utc')::date) > 1 then
    raise exception 'fecha fuera de rango';
  end if;
  select * into fila from public.imperio where user_id = uid for update;
  if not found then raise exception 'imperio no existe'; end if;

  if fila.racha_fecha is not null and p_fecha <= fila.racha_fecha then
    return jsonb_build_object('dia', fila.racha_dia, 'ya', true, 'ciruelas_ganadas', 0, 'ficha', false,
                              'ciruelas', fila.ciruelas, 'fichas', fila.fichas, 'congelados', 0,
                              'congeladores', fila.congeladores, 'racha_salvados', to_jsonb(fila.racha_salvados),
                              'pases', fila.pases);
  end if;

  v_falta := case when fila.racha_fecha is null then null else p_fecha - fila.racha_fecha - 1 end;
  if v_falta = 0 then
    v_dia := fila.racha_dia % 30 + 1;
  elsif fila.racha_dia > 0 and v_falta between 1 and fila.congeladores then
    v_cong := v_falta;
    v_dia := fila.racha_dia % 30 + 1;
  else
    v_dia := 1;
  end if;
  v_cir := cir_por_dia[v_dia];
  v_ficha := v_dia = any(ficha_dias);
  if v_ficha then
    if fila.fichas < 5 then dio_ficha := true; else v_cir := v_cir + 2; end if;
  end if;

  update public.imperio
     set racha_dia = v_dia, racha_fecha = p_fecha,
         ciruelas = ciruelas + v_cir,
         fichas = case when dio_ficha then fichas + 1 else fichas end,
         congeladores = congeladores - v_cong,
         racha_salvados = (case when v_dia = 1 then '{}'::int[] else racha_salvados end)
                          || (case when v_cong > 0 then array[v_dia] else '{}'::int[] end),
         pases = pases + 1
   where user_id = uid
   returning * into fila;

  return jsonb_build_object('dia', v_dia, 'ya', false, 'ciruelas_ganadas', v_cir, 'ficha', dio_ficha,
                            'ciruelas', fila.ciruelas, 'fichas', fila.fichas, 'congelados', v_cong,
                            'congeladores', fila.congeladores, 'racha_salvados', to_jsonb(fila.racha_salvados),
                            'pases', fila.pases);
end;
$$;

-- Quién va por debajo del 25% de su grupo. Grupo: antigüedad entre la mitad y 1,5 veces la suya y ritmo de
-- cagadas entre la mitad y el doble. Si ese grupo tiene menos de 3, solo por antigüedad; si tampoco, todos.
-- Solo cuenta a quien lleva 2 días o más y ya produjo algo.
create or replace function public.imperio_quedados()
returns table (user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with s as (
    select i.user_id, i.mj_total::float8 as mj,
           greatest(extract(epoch from now() - i.creado) / 86400.0, 1)::float8 as dias,
           (select count(*) from public.cagadas c where c.user_id = i.user_id and c.created_at > i.creado)::float8 as cag
      from public.imperio i
     where i.mj_total > 0
  ),
  r as (select s.*, s.cag / s.dias as ritmo from s)
  select y.user_id
    from r y
    cross join lateral (
      select count(*) filter (where o.dias between y.dias * 0.5 and y.dias * 1.5
                                and o.ritmo between y.ritmo * 0.5 and greatest(y.ritmo * 2, 0.1)) as n1,
             percentile_cont(0.25) within group (order by o.mj) filter (where o.dias between y.dias * 0.5 and y.dias * 1.5
                                and o.ritmo between y.ritmo * 0.5 and greatest(y.ritmo * 2, 0.1)) as p1,
             count(*) filter (where o.dias between y.dias * 0.5 and y.dias * 1.5) as n2,
             percentile_cont(0.25) within group (order by o.mj) filter (where o.dias between y.dias * 0.5 and y.dias * 1.5) as p2,
             count(*) as n3,
             percentile_cont(0.25) within group (order by o.mj) as p3
        from r o
       where o.user_id <> y.user_id
    ) g
   where y.dias >= 2
     and y.mj < case when g.n1 >= 3 then g.p1 when g.n2 >= 3 then g.p2 when g.n3 >= 3 then g.p3 end;
$$;

-- Lo que la app necesita para candados y empujón. Revisa si toca empujón una vez por día como mucho.
-- empujon = true solo la vez que se cobra (la app pone el x2 por 30 min).
create or replace function public.imperio_progreso()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  hoy date := (now() at time zone 'utc')::date;
  v_cobra boolean := false;
begin
  if uid is null then raise exception 'Sin sesión' using errcode = 'P0001'; end if;
  select * into fila from public.imperio where user_id = uid for update;
  if fila.user_id is null then
    return jsonb_build_object('cagadas_candado', 0, 'pases', 0, 'empujon', false, 'tope_dia', public.imperio_tope_dia());
  end if;

  if (fila.empujon_en is null or fila.empujon_en < now() - interval '7 days')
     and (fila.empujon_revisado is null or fila.empujon_revisado < hoy) then
    update public.imperio set empujon_revisado = hoy where user_id = uid;
    if exists (select 1 from public.imperio_quedados() q where q.user_id = uid) then
      update public.imperio set empujon_en = now(), empujon_cobrado = false where user_id = uid;
      fila.empujon_en := now();
      fila.empujon_cobrado := false;
    end if;
  end if;

  if not fila.empujon_cobrado and fila.empujon_en > now() - interval '7 days' then
    update public.imperio set empujon_cobrado = true where user_id = uid;
    v_cobra := true;
  end if;

  return jsonb_build_object('cagadas_candado', public.imperio_cagadas_tope(uid, null), 'pases', fila.pases,
                            'empujon', v_cobra, 'tope_dia', public.imperio_tope_dia());
end;
$$;

-- Avisos de la poceta: uno por persona y por día, el de más prioridad.
--   1 regalo (48 h o más sin entrar), 2 empujón (va quedado), 3 extrana (24 a 48 h), 4 candado (le faltan 1 o 2
--   cagadas para el próximo edificio), 5 jalar (ya puede jalar la cadena), 6 ganancia, 7 constipado, 8 fresca.
create or replace function public.push_poceta_revisar()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pct numeric;
  v_tope_h numeric;
  v_necesarias int := public.imperio_cadena_necesarias();
  lista jsonb;
  n integer;
begin
  if not coalesce((select poceta_activo from public.push_config), false) then
    return 0;
  end if;

  select coalesce((select (valor #>> '{}')::numeric from public.imperio_flags
                    where clave = 'offline_porcentaje' and activo), 0.25),
         coalesce((select (valor #>> '{}')::numeric from public.imperio_flags
                    where clave = 'offline_tope_h' and activo), 2)
    into v_pct, v_tope_h;

  with zonas as (
    select distinct on (t.user_id) t.user_id,
           case when exists (select 1 from pg_catalog.pg_timezone_names z where z.name = t.zona)
                then t.zona else 'America/Caracas' end as zona
      from public.push_tokens t
     where t.user_id is not null
     order by t.user_id, t.updated_at desc
  ),
  base as (
    select z.user_id, z.zona,
           (date_trunc('day', now() at time zone z.zona) at time zone z.zona) as hoy,
           extract(hour from now() at time zone z.zona) as hora
      from zonas z
      left join public.push_ajustes a on a.user_id = z.user_id
     where coalesce(a.poceta, true)
       and extract(hour from now() at time zone z.zona) between 9 and 20
       and (a.poceta_en is null
            or a.poceta_en < (date_trunc('day', now() at time zone z.zona) at time zone z.zona))
       and (a.abrio is null
            or a.abrio < (date_trunc('day', now() at time zone z.zona) at time zone z.zona))
  ),
  imp as (
    -- mps de edificios (sin el pico de clics) si la app ya lo guarda; si no, el mps total.
    select b.user_id, coalesce((i.estado ->> '_mps_edificios')::float8, i.mps::float8) as mps, i.mj_total, i.guardado,
           extract(epoch from now() - i.guardado) / 3600.0 as ausente_h,
           greatest(case when i.estado -> 'mejoras' ? 'tanque_8' then 8
                         when i.estado -> 'mejoras' ? 'tanque_4' then 4 else 0 end, v_tope_h) as tope,
           greatest(case when i.estado -> 'mejoras' ? 'valvula_75' then 0.75
                         when i.estado -> 'mejoras' ? 'valvula_50' then 0.5 else 0 end, v_pct) as pct,
           i.pases, coalesce((i.estado ->> 'cagadas_pagadas')::int, 0) as pagadas,
           i.jalada_en, i.creado, i.jaladas, i.empujon_en,
           (jsonb_typeof(i.estado -> 'mejoras') = 'array' and (i.estado -> 'mejoras') ? 'cadena_trono') as tiene_cadena
      from base b
      join public.imperio i on i.user_id = b.user_id
     where i.guardado < b.hoy
  ),
  regalo as (
    select user_id, 'regalo'::text as subtipo, 0::numeric as mj, floor(ausente_h)::int as horas, 0 as faltan,
           false as pagable, 1 as prioridad
      from imp
     where mj_total > 0 and ausente_h >= 48 and ausente_h < 24 * 7
  ),
  empujon as (
    select p.user_id, 'empujon'::text, 0::numeric, floor(p.ausente_h)::int, 0, false, 2
      from imp p
      join public.imperio_quedados() q on q.user_id = p.user_id
     where p.empujon_en is null or p.empujon_en < now() - interval '7 days'
  ),
  extrana as (
    select user_id, 'extrana'::text, 0::numeric, floor(ausente_h)::int, 0, false, 3
      from imp
     where mj_total > 0 and ausente_h >= 24 and ausente_h < 48
  ),
  puntos as (
    select p.user_id, p.pagadas,
           public.imperio_cagadas_tope(p.user_id, null) + p.pases / 2 as pts
      from imp p
  ),
  proximo as (
    select pt.user_id, c.pide, c.pide - pt.pts - least(pt.pagadas, c.pide / 2) as faltan,
           c.pide / 2 - least(pt.pagadas, c.pide / 2) as pagables
      from puntos pt
      cross join lateral (
        select x.pide from unnest(array[3, 5, 10, 30, 60, 100, 150]) as x(pide)
         where pt.pts + least(pt.pagadas, x.pide / 2) < x.pide
         order by x.pide limit 1
      ) c
  ),
  candado as (
    select user_id, 'candado'::text, 0::numeric, 0, faltan::int, faltan <= pagables, 4
      from proximo
     where faltan between 1 and 2
  ),
  jalar as (
    select user_id, 'jalar'::text, 0::numeric, 0, 0, false, 5
      from imp
     where (jaladas > 0 or tiene_cadena)
       and public.imperio_cagadas_tope(user_id, coalesce(jalada_en, creado)) >= v_necesarias
  ),
  ganancia as (
    select user_id, 'ganancia'::text, (mps * least(ausente_h, tope) * pct)::numeric,
           floor(ausente_h)::int, 0, false, 6
      from imp
     where mps > 0 and ausente_h >= tope and ausente_h < 24
  ),
  cagadas_de as (
    select b.user_id, b.hoy, b.hora, c.ultima, c.semana
      from base b
      join lateral (
        select max(created_at) as ultima,
               count(*) filter (where created_at > now() - interval '7 days') as semana
          from public.cagadas where user_id = b.user_id
      ) c on true
  ),
  constipado as (
    select user_id, 'constipado'::text, 0::numeric,
           floor(extract(epoch from now() - ultima) / 3600.0)::int, 0, false, 7
      from cagadas_de
     where ultima < now() - interval '10 hours'
       and ultima > now() - interval '72 hours'
       and semana >= 3
  ),
  fresca as (
    select user_id, 'fresca'::text, 0::numeric, 0, 0, false, 8
      from cagadas_de
     where hora >= 17 and semana >= 1 and ultima < hoy
  ),
  todos as (
    select * from regalo union all select * from empujon union all select * from extrana
    union all select * from candado union all select * from jalar union all select * from ganancia
    union all select * from constipado union all select * from fresca
  ),
  elegidos as (
    select distinct on (user_id) user_id, subtipo, mj, horas, faltan, pagable
      from todos
     order by user_id, prioridad
  ),
  marcados as (
    insert into public.push_ajustes (user_id, poceta_en)
    select user_id, now() from elegidos
    on conflict (user_id) do update set poceta_en = excluded.poceta_en
    returning user_id
  ),
  -- El empujón queda ofrecido: lo cobra imperio_progreso() cuando abra.
  ofrecidos as (
    update public.imperio i set empujon_en = now(), empujon_cobrado = false
      from elegidos e
     where e.subtipo = 'empujon' and i.user_id = e.user_id
    returning i.user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', e.user_id, 'subtipo', e.subtipo,
           'mj', round(e.mj, 1), 'horas', e.horas, 'faltan', e.faltan, 'pagable', e.pagable)), '[]'::jsonb),
         count(*)
    into lista, n
    from elegidos e
    join marcados m on m.user_id = e.user_id;

  if n > 0 then
    perform net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
      ),
      body := jsonb_build_object('tipo', 'poceta', 'lista', lista)
    );
  end if;
  return n;
end;
$$;

revoke all on function public.imperio_tope_dia() from public, anon;
revoke all on function public.imperio_cagadas_tope(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.imperio_quedados() from public, anon, authenticated;
revoke all on function public.imperio_progreso() from public, anon;
revoke all on function public.imperio_cadena() from public, anon;
revoke all on function public.imperio_jalar() from public, anon;
revoke all on function public.imperio_reclamar_racha(date) from public, anon;
revoke all on function public.push_poceta_revisar() from public, anon, authenticated;
grant execute on function public.imperio_progreso() to authenticated;
grant execute on function public.imperio_cadena() to authenticated;
grant execute on function public.imperio_jalar() to authenticated;
grant execute on function public.imperio_reclamar_racha(date) to authenticated;

-- Ranking del Imperio entre amigos: yo y la gente que sigo, por MJ ganados en la partida.
create or replace function public.imperio_ranking_amigos()
returns table(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
              lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real,
              mj_total double precision, rollos bigint, yo boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.avatar, p.sombrero, p.lentes, p.mascota, p.cagadas,
         p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala,
         coalesce(i.mj_total, 0), greatest(coalesce((i.estado->>'rollos')::numeric, 0), 0)::bigint, p.id = (select auth.uid())
  from public.imperio i
  join public.profiles p on p.id = i.user_id
  where (select auth.uid()) is not null
    and (p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
    and (p.id = (select auth.uid()) or i.mj_total > 0)
    and not public.hay_bloqueo(p.id)
  order by coalesce(i.mj_total, 0) desc, p.username
  limit 100;
$$;
revoke all on function public.imperio_ranking_amigos() from public, anon;
grant execute on function public.imperio_ranking_amigos() to authenticated;
