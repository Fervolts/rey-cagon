-- push_poceta_revisar(): las variables pct/tope_h chocaban con las columnas del mismo nombre
-- en la consulta ("column reference is ambiguous"). Mismo cuerpo, variables renombradas.
create or replace function public.push_poceta_revisar()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pct numeric;
  v_tope_h numeric;
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
                         when i.estado -> 'mejoras' ? 'tanque_4' then 4 else 0 end, v_tope_h) as tope,
           greatest(case when i.estado -> 'mejoras' ? 'valvula_75' then 0.75
                         when i.estado -> 'mejoras' ? 'valvula_50' then 0.5 else 0 end, v_pct) as pct
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
