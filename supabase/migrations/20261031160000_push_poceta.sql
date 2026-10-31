-- Push de la poceta + registro de todos los push + panel admin.
--
-- 1. push_envios: una fila por push mandado (todos los tipos). La escribe la Edge Function
--    con service_role; la app solo la toca por RPC (push_tocado / push_abri_app).
-- 2. push_config: interruptor global de los avisos de la poceta. APAGADO por defecto.
-- 3. push_ajustes: opt-out por usuario + última apertura de la app + último aviso de poceta.
-- 4. push_tokens.zona: zona horaria del teléfono (la manda la app al guardar el token).
-- 5. push_poceta_revisar(): elige candidatos (ganancia offline / te extraña / constipado)
--    y llama a la función 'notificaciones' con tipo 'poceta'. pg_cron cada hora.
-- 6. panel_admin(): números para la pantalla de panel (solo admin).

-- ---------------------------------------------------------------- envíos
create table public.push_envios (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  tipo text not null,
  subtipo text,
  variante text,
  enviado timestamptz not null default now(),
  ok boolean not null default true,
  tocado timestamptz,
  abrio_app timestamptz
);
create index push_envios_user_idx on public.push_envios (user_id, enviado desc);
create index push_envios_tipo_idx on public.push_envios (tipo, enviado desc);
-- Sin políticas: nadie lee ni escribe directo desde la app.
alter table public.push_envios enable row level security;

-- ---------------------------------------------------------------- interruptor global
create table public.push_config (
  id boolean primary key default true check (id),
  poceta_activo boolean not null default false
);
insert into public.push_config default values;
alter table public.push_config enable row level security;

-- ---------------------------------------------------------------- ajustes por usuario
create table public.push_ajustes (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  poceta boolean not null default true,
  abrio timestamptz,
  poceta_en timestamptz
);
alter table public.push_ajustes enable row level security;
create policy "ver mis ajustes de push" on public.push_ajustes
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- zona horaria
alter table public.push_tokens add column if not exists zona text not null default 'America/Caracas';
grant insert (zona), update (zona) on public.push_tokens to authenticated;

-- ---------------------------------------------------------------- RPC de la app
-- El usuario tocó el push: data['envio'] trae el id.
create function public.push_tocado(p_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.push_envios
     set tocado = coalesce(tocado, now()), abrio_app = null
   where id = p_id and user_id = auth.uid();
$$;
revoke all on function public.push_tocado(bigint) from public, anon;
grant execute on function public.push_tocado(bigint) to authenticated;

-- Abrió la app (arranque o vuelta al frente). Guarda la hora y marca "abrió sin tocar"
-- en su último push no tocado de las últimas 6 h.
create function public.push_abri_app()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  yo uuid := auth.uid();
begin
  if yo is null then return; end if;
  insert into public.push_ajustes (user_id, abrio) values (yo, now())
    on conflict (user_id) do update set abrio = excluded.abrio;
  update public.push_envios
     set abrio_app = now()
   where id = (
     select e.id from public.push_envios e
      where e.user_id = yo and e.ok and e.tocado is null and e.abrio_app is null
        and e.enviado > now() - interval '6 hours'
      order by e.enviado desc
      limit 1
   );
end;
$$;
revoke all on function public.push_abri_app() from public, anon;
grant execute on function public.push_abri_app() to authenticated;

-- Opt-out de los avisos de la poceta.
create function public.push_poceta(p_activo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'sin sesión'; end if;
  insert into public.push_ajustes (user_id, poceta) values (auth.uid(), p_activo)
    on conflict (user_id) do update set poceta = excluded.poceta;
end;
$$;
revoke all on function public.push_poceta(boolean) from public, anon;
grant execute on function public.push_poceta(boolean) to authenticated;
grant execute on function public.push_poceta(boolean) to authenticated;

-- ---------------------------------------------------------------- candidatos de poceta
-- Topes: 1 aviso de poceta por usuario por día local, solo de 9:00 a 20:59 de su zona,
-- nada si ya abrió la app hoy. Prioridad: te extraña > ganancia offline > constipado.
create function public.push_poceta_revisar()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  pct numeric;
  tope_h numeric;
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
    into pct, tope_h;

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
           (date_trunc('day', now() at time zone z.zona) at time zone z.zona) as hoy
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
                         when i.estado -> 'mejoras' ? 'tanque_4' then 4 else 0 end, tope_h) as tope,
           greatest(case when i.estado -> 'mejoras' ? 'valvula_75' then 0.75
                         when i.estado -> 'mejoras' ? 'valvula_50' then 0.5 else 0 end, pct) as pct
      from base b
      join public.imperio i on i.user_id = b.user_id
     where i.guardado < b.hoy
  ),
  extrana as (
    select user_id, 'extrana'::text as subtipo, 0::numeric as mj,
           floor(ausente_h)::int as horas, 1 as prioridad
      from imp
     where mj_total > 0 and ausente_h >= 24 and ausente_h < 24 * 7
  ),
  ganancia as (
    select user_id, 'ganancia'::text, (mps * least(ausente_h, tope) * pct)::numeric,
           floor(ausente_h)::int, 2
      from imp
     where mps > 0 and ausente_h >= tope and ausente_h < 24
  ),
  constipado as (
    select b.user_id, 'constipado'::text, 0::numeric,
           floor(extract(epoch from now() - c.ultima) / 3600.0)::int, 3
      from base b
      join lateral (
        select max(created_at) as ultima,
               count(*) filter (where created_at > now() - interval '7 days') as semana
          from public.cagadas where user_id = b.user_id
      ) c on true
     where c.ultima < now() - interval '10 hours'
       and c.ultima > now() - interval '72 hours'
       and c.semana >= 3
  ),
  todos as (
    select * from extrana union all select * from ganancia union all select * from constipado
  ),
  elegidos as (
    select distinct on (user_id) user_id, subtipo, mj, horas
      from todos
     order by user_id, prioridad
  ),
  marcados as (
    insert into public.push_ajustes (user_id, poceta_en)
    select user_id, now() from elegidos
    on conflict (user_id) do update set poceta_en = excluded.poceta_en
    returning user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', e.user_id, 'subtipo', e.subtipo,
           'mj', round(e.mj, 1), 'horas', e.horas)), '[]'::jsonb),
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
revoke all on function public.push_poceta_revisar() from public, anon, authenticated;

-- Cada hora en punto. Con el interruptor apagado no hace nada.
select cron.schedule('push_poceta', '0 * * * *', $$select public.push_poceta_revisar()$$);

-- ---------------------------------------------------------------- panel admin
create function public.panel_admin(p_n integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
begin
  if not (public.es_admin() or coalesce(auth.role(), '') = 'service_role' or session_user = 'postgres') then
    raise exception 'solo admin';
  end if;

  select jsonb_build_object(
    'ahora', now(),
    'dau_24h', (select count(distinct user_id) from public.imperio_eventos
                 where creado > now() - interval '24 hours'),
    'eventos_24h', (select count(*) from public.imperio_eventos
                     where creado > now() - interval '24 hours'),
    'aperturas_24h', (select count(*) from public.push_ajustes
                       where abrio > now() - interval '24 hours'),
    'cagadas_24h', (select count(*) from public.cagadas
                     where created_at > now() - interval '24 hours'),
    'poceta_activo', coalesce((select poceta_activo from public.push_config), false),
    'por_hora', coalesce((
      select jsonb_agg(jsonb_build_object('hora', h.hora, 'eventos', h.eventos, 'usuarios', h.usuarios)
                       order by h.hora)
        from (select date_trunc('hour', creado) as hora, count(*) as eventos,
                     count(distinct user_id) as usuarios
                from public.imperio_eventos
               where creado > now() - interval '24 hours'
               group by 1) h), '[]'::jsonb),
    'top_eventos', coalesce((
      select jsonb_agg(jsonb_build_object('evento', t.evento, 'n', t.n, 'usuarios', t.usuarios)
                       order by t.n desc)
        from (select evento, count(*) as n, count(distinct user_id) as usuarios
                from public.imperio_eventos
               where creado > now() - interval '24 hours'
               group by 1 order by 2 desc limit 15) t), '[]'::jsonb),
    'push', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', p.tipo, 'subtipo', p.subtipo, 'variante', p.variante,
               'enviados', p.enviados, 'fallidos', p.fallidos,
               'tocados', p.tocados, 'abrio', p.abrio)
             order by p.enviados desc)
        from (select tipo, subtipo, variante,
                     count(*) filter (where ok) as enviados,
                     count(*) filter (where not ok) as fallidos,
                     count(tocado) as tocados,
                     count(abrio_app) as abrio
                from public.push_envios
               where enviado > now() - interval '7 days'
               group by 1, 2, 3) p), '[]'::jsonb),
    'vivo', coalesce((
      select jsonb_agg(jsonb_build_object(
               'creado', v.creado, 'evento', v.evento, 'usuario', v.username, 'datos', v.datos)
             order by v.creado desc)
        from (select e.creado, e.evento, e.datos, pr.username
                from public.imperio_eventos e
                left join public.profiles pr on pr.id = e.user_id
               order by e.creado desc
               limit least(greatest(coalesce(p_n, 50), 1), 200)) v), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;
revoke all on function public.panel_admin(integer) from public, anon;
grant execute on function public.panel_admin(integer) to authenticated;
