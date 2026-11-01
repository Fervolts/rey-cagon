-- Ajustes de notificaciones por categoría + avisos de ganadores y de cierre de periodo.
--
-- 1. push_ajustes: un interruptor por categoría (todos prendidos por defecto). Sin fila = todo prendido.
--      cagadas    cagadas de los que sigues (y los chismes del secreto)
--      rachas     RAMPAGE (5ª del día) y HEXAKILL (6ª) de los que sigues
--      ganadores  quién ganó la semana / el mes / el año entre tus amigos
--      cierres    "quedan 6 h de la semana: vas 2º..."
--      chat       menciones y respuestas en hilos
--      retos      el Cagadón
--      seguidores nuevos seguidores
--      imperio    poceta + racha del Imperio (además de las columnas viejas poceta y racha)
--    Anuncios, versión nueva y soporte no se apagan.
-- 2. push_avisos_mios() / push_aviso(clave, activo): la app lee y cambia los suyos.
-- 3. push_ganadores_revisar(): 00:05 hora de Venezuela, el día que cierra una semana, mes o año.
--    Un solo aviso por persona por día: el periodo más grande que cerró (año > mes > semana).
-- 4. push_cierres_revisar(): 18:00 hora de Venezuela, el último día de una semana, mes o año.
--    Un solo aviso por persona por día, del periodo más grande que termina hoy.
-- Círculo de cada quien = los que sigue + él mismo, sin bloqueos en ningún sentido
-- (lo mismo que leaderboard(periodo, solo_siguiendo => true)).
-- Venezuela es UTC-4 fijo: 00:05 VE = 04:05 UTC, 18:00 VE = 22:00 UTC.

-- ---------------------------------------------------------------- columnas
alter table public.push_ajustes
  add column cagadas boolean not null default true,
  add column rachas boolean not null default true,
  add column ganadores boolean not null default true,
  add column cierres boolean not null default true,
  add column chat boolean not null default true,
  add column retos boolean not null default true,
  add column seguidores boolean not null default true,
  add column imperio boolean not null default true,
  add column ganadores_en timestamptz,
  add column cierres_en timestamptz;

-- Interruptores globales (prendidos): para apagar sin desplegar nada.
alter table public.push_config
  add column ganadores_activo boolean not null default true,
  add column cierres_activo boolean not null default true;

-- ---------------------------------------------------------------- RPC de la app
-- Los interruptores del usuario. Sin fila, todos en true.
create function public.push_avisos_mios()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a public.push_ajustes;
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  select * into a from public.push_ajustes where user_id = auth.uid();
  return jsonb_build_object(
    'cagadas', coalesce(a.cagadas, true),
    'rachas', coalesce(a.rachas, true),
    'ganadores', coalesce(a.ganadores, true),
    'cierres', coalesce(a.cierres, true),
    'chat', coalesce(a.chat, true),
    'retos', coalesce(a.retos, true),
    'seguidores', coalesce(a.seguidores, true),
    'imperio', coalesce(a.imperio, true) and coalesce(a.poceta, true) and coalesce(a.racha, true)
  );
end;
$$;
revoke all on function public.push_avisos_mios() from public, anon;
grant execute on function public.push_avisos_mios() to authenticated;

-- Prende o apaga una categoría. 'imperio' arrastra también poceta y racha, para que los crons
-- viejos (que miran esas columnas) lo respeten sin tocarlos.
create function public.push_aviso(p_clave text, p_activo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  if p_activo is null then raise exception 'activo vacío'; end if;
  if p_clave = 'imperio' then
    insert into public.push_ajustes (user_id, imperio, poceta, racha) values (auth.uid(), p_activo, p_activo, p_activo)
      on conflict (user_id) do update set imperio = excluded.imperio, poceta = excluded.poceta, racha = excluded.racha;
    return;
  end if;
  if p_clave not in ('cagadas', 'rachas', 'ganadores', 'cierres', 'chat', 'retos', 'seguidores') then
    raise exception 'clave desconocida: %', p_clave;
  end if;
  execute format(
    'insert into public.push_ajustes (user_id, %1$I) values ($1, $2) on conflict (user_id) do update set %1$I = excluded.%1$I',
    p_clave) using auth.uid(), p_activo;
end;
$$;
revoke all on function public.push_aviso(text, boolean) from public, anon;
grant execute on function public.push_aviso(text, boolean) to authenticated;

-- ---------------------------------------------------------------- ganadores
-- Corre todos los días a las 00:05 VE y solo hace algo si ayer cerró una semana (lunes),
-- un mes (día 1) o un año (1 de enero). p_periodo ('week' | 'month' | 'year') fuerza ese
-- periodo, el último cerrado: sirve para probar a mano.
-- Por persona con teléfono y el aviso prendido: los de su círculo con más cagadas en el periodo.
-- Nada si no tiene amigos o si nadie del círculo cagó.
create function public.push_ganadores_revisar(p_periodo text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  ahora timestamp := now() at time zone 'America/Caracas';
  hoy timestamptz := date_trunc('day', now() at time zone 'America/Caracas') at time zone 'America/Caracas';
  periodo text := p_periodo;
  fin_local timestamp;
  ini timestamptz;
  fin timestamptz;
  lista jsonb;
  n integer;
begin
  if not coalesce((select ganadores_activo from public.push_config), false) then
    return 0;
  end if;
  if periodo is null then
    periodo := case
      when extract(doy from ahora) = 1 then 'year'
      when extract(day from ahora) = 1 then 'month'
      when extract(isodow from ahora) = 1 then 'week'
    end;
  end if;
  if periodo is null then return 0; end if;
  if periodo not in ('week', 'month', 'year') then raise exception 'periodo desconocido: %', periodo; end if;

  fin_local := date_trunc(periodo, ahora);
  ini := date_trunc(periodo, fin_local - interval '1 day') at time zone 'America/Caracas';
  fin := fin_local at time zone 'America/Caracas';

  with destinos as (
    select distinct t.user_id
      from public.push_tokens t
      left join public.push_ajustes a on a.user_id = t.user_id
     where t.user_id is not null
       and coalesce(a.ganadores, true)
       and (a.ganadores_en is null or a.ganadores_en < hoy)
  ),
  circulo as (
    select d.user_id as yo, d.user_id as quien from destinos d
    union
    select d.user_id, f.followed
      from destinos d
      join public.follows f on f.follower = d.user_id
     where not exists (select 1 from public.bloqueos b
                        where (b.bloqueador = d.user_id and b.bloqueado = f.followed)
                           or (b.bloqueador = f.followed and b.bloqueado = d.user_id))
  ),
  con_amigos as (
    select yo from circulo where quien <> yo group by yo
  ),
  conteo as (
    select c.yo, c.quien, count(*)::int as total
      from circulo c
      join con_amigos ca on ca.yo = c.yo
      join public.cagadas x on x.user_id = c.quien and x.created_at >= ini and x.created_at < fin
     group by c.yo, c.quien
  ),
  arriba as (
    select c.*, max(c.total) over (partition by c.yo) as maximo from conteo c
  ),
  elegidos as (
    select g.yo as user_id,
           max(g.total) as total,
           bool_or(g.quien = g.yo) as gane,
           count(*)::int as empatados,
           coalesce(jsonb_agg(p.username order by p.username) filter (where g.quien <> g.yo), '[]'::jsonb) as nombres
      from arriba g
      join public.profiles p on p.id = g.quien
     where g.total = g.maximo
     group by g.yo
  ),
  marcados as (
    insert into public.push_ajustes (user_id, ganadores_en)
    select user_id, now() from elegidos
    on conflict (user_id) do update set ganadores_en = excluded.ganadores_en
    returning user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', e.user_id, 'gane', e.gane, 'n', e.total, 'empatados', e.empatados,
           'nombres', e.nombres, 'reina', coalesce(p.genero = 'mujer', false))), '[]'::jsonb),
         count(*)
    into lista, n
    from elegidos e
    join marcados m on m.user_id = e.user_id
    left join public.profiles p on p.id = e.user_id;

  if n > 0 then
    perform net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
      ),
      body := jsonb_build_object('tipo', 'ganadores', 'periodo', periodo, 'lista', lista)
    );
  end if;
  return n;
end;
$$;
revoke all on function public.push_ganadores_revisar(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- cierres
-- Corre todos los días a las 18:00 VE y solo hace algo el último día de una semana (domingo),
-- de un mes o del año. p_periodo fuerza ese periodo (el que va en curso), para probar a mano.
-- Por persona: su puesto en el círculo (empates comparten puesto, como un podio), cuántas lleva
-- y a quién tiene justo arriba (o justo abajo si va primero). Nada si no tiene amigos o si nadie
-- del círculo cagó en el periodo.
create function public.push_cierres_revisar(p_periodo text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  ahora timestamp := now() at time zone 'America/Caracas';
  hoy timestamptz := date_trunc('day', now() at time zone 'America/Caracas') at time zone 'America/Caracas';
  manana timestamp := date_trunc('day', now() at time zone 'America/Caracas') + interval '1 day';
  periodo text := p_periodo;
  ini timestamptz;
  fin timestamptz;
  lista jsonb;
  n integer;
begin
  if not coalesce((select cierres_activo from public.push_config), false) then
    return 0;
  end if;
  if periodo is null then
    periodo := case
      when extract(doy from manana) = 1 then 'year'
      when extract(day from manana) = 1 then 'month'
      when extract(isodow from ahora) = 7 then 'week'
    end;
  end if;
  if periodo is null then return 0; end if;
  if periodo not in ('week', 'month', 'year') then raise exception 'periodo desconocido: %', periodo; end if;

  ini := date_trunc(periodo, ahora) at time zone 'America/Caracas';
  fin := (date_trunc(periodo, ahora) + ('1 ' || periodo)::interval) at time zone 'America/Caracas';

  with destinos as (
    select distinct t.user_id
      from public.push_tokens t
      left join public.push_ajustes a on a.user_id = t.user_id
     where t.user_id is not null
       and coalesce(a.cierres, true)
       and (a.cierres_en is null or a.cierres_en < hoy)
  ),
  circulo as (
    select d.user_id as yo, d.user_id as quien from destinos d
    union
    select d.user_id, f.followed
      from destinos d
      join public.follows f on f.follower = d.user_id
     where not exists (select 1 from public.bloqueos b
                        where (b.bloqueador = d.user_id and b.bloqueado = f.followed)
                           or (b.bloqueador = f.followed and b.bloqueado = d.user_id))
  ),
  con_amigos as (
    select yo from circulo where quien <> yo group by yo
  ),
  conteo as (
    select c.yo, c.quien, p.username,
           (select count(*)::int from public.cagadas x
             where x.user_id = c.quien and x.created_at >= ini and x.created_at < fin) as total
      from circulo c
      join con_amigos ca on ca.yo = c.yo
      join public.profiles p on p.id = c.quien
  ),
  vivos as (
    select yo from conteo group by yo having max(total) > 0
  ),
  mio as (
    select c.yo, c.total,
           1 + (select count(*) from conteo o where o.yo = c.yo and o.total > c.total)::int as puesto,
           (select count(*) from conteo o where o.yo = c.yo and o.quien <> c.yo and o.total = c.total)::int as empatados
      from conteo c
      join vivos v on v.yo = c.yo
     where c.quien = c.yo
  ),
  elegidos as (
    select m.yo as user_id, m.total, m.puesto, m.empatados,
           -- Va primero: el que le sigue (o con quien empata). Si no: el que tiene justo arriba.
           r.username as rival, r.total as rival_total
      from mio m
      left join lateral (
        select o.username, o.total
          from conteo o
         where o.yo = m.yo and o.quien <> m.yo
           and case when m.puesto = 1 then o.total <= m.total else o.total > m.total end
         order by case when m.puesto = 1 then -o.total else o.total end, o.username
         limit 1
      ) r on true
  ),
  marcados as (
    insert into public.push_ajustes (user_id, cierres_en)
    select user_id, now() from elegidos
    on conflict (user_id) do update set cierres_en = excluded.cierres_en
    returning user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', e.user_id, 'n', e.total, 'puesto', e.puesto, 'empatados', e.empatados,
           'rival', e.rival, 'rival_n', e.rival_total,
           'horas', greatest(1, ceil(extract(epoch from fin - now()) / 3600.0)::int))), '[]'::jsonb),
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
      body := jsonb_build_object('tipo', 'cierre', 'periodo', periodo, 'lista', lista)
    );
  end if;
  return n;
end;
$$;
revoke all on function public.push_cierres_revisar(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- crons (hora UTC)
-- 04:05 UTC = 00:05 VE: ganadores del periodo que acaba de cerrar.
select cron.schedule('push_ganadores', '5 4 * * *', $$select public.push_ganadores_revisar()$$);
-- 22:00 UTC = 18:00 VE: aviso de cierre el último día del periodo.
select cron.schedule('push_cierres', '0 22 * * *', $$select public.push_cierres_revisar()$$);
