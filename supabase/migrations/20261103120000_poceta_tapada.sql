-- 2.12.1: "poceta tapada" contra el truco de cagar y deshacer para estirar la cagada fresca (x2 del Imperio),
-- registro de sospechas de exploits y avisos nuevos de la racha del Imperio.
--
-- 1. cagadas_borradas: cada cagada borrada (deshacer o calendario). "rapida" = se borró antes de 2 h de creada.
-- 2. limitar_cagadas: el primer deshacer rápido de 24 h es gratis (el truquito del día). Desde el segundo, la hora
--    de la cagada borrada sigue contando para el límite de una por hora.
-- 3. Al tercer deshacer rápido en 24 h, o dos en una hora, se tapa la poceta 3 h: no entra ninguna cagada
--    (hint 'poceta_tapada'). Borrar siempre se puede.
-- 4. imperio_cargar: las Fichas que dio una cagada que después se borró se descuentan.
-- 5. avisar_cagada: la cagada que reemplaza a una recién borrada no vuelve a avisar a los seguidores.
-- 6. sospechas + marcar_sospecha + detectar_exploits (cron diario) + panel_sospechas para el panel.
-- 7. Logro secreto 'poceta_tapada'.
-- 8. push_racha_revisar: 20:00 aviso (con hitos 7/15/30 en la Edge Function), 23:00 última llamada y
--    10:00 del día después de fallar: racha perdida o congelador aguantando.

-- ---------------------------------------------------------------- tablas
create table if not exists public.cagadas_borradas (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  cagada_id bigint not null,
  creada timestamptz not null,
  borrada_en timestamptz not null default now(),
  rapida boolean not null
);
create index if not exists cagadas_borradas_usuario on public.cagadas_borradas (user_id, borrada_en desc);
alter table public.cagadas_borradas enable row level security;
revoke all on public.cagadas_borradas from anon, authenticated;

create table if not exists public.pocetas_tapadas (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  hasta timestamptz not null,
  veces int not null default 1
);
alter table public.pocetas_tapadas enable row level security;
revoke all on public.pocetas_tapadas from anon, authenticated;

-- Lo raro que vale la pena mirar. La escriben triggers y crons; se lee en el panel y en
-- supabase/consultas/exploits.sql.
create table if not exists public.sospechas (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  tipo text not null,
  datos jsonb not null default '{}'::jsonb,
  creado timestamptz not null default now()
);
create index if not exists sospechas_creado on public.sospechas (creado desc);
create index if not exists sospechas_usuario on public.sospechas (user_id, tipo, creado desc);
alter table public.sospechas enable row level security;
revoke all on public.sospechas from anon, authenticated;

-- Una por usuario y tipo cada hora, para no llenar la tabla.
create or replace function public.marcar_sospecha(p_uid uuid, p_tipo text, p_datos jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.sospechas (user_id, tipo, datos)
  select p_uid, p_tipo, coalesce(p_datos, '{}'::jsonb)
   where exists (select 1 from public.profiles p where p.id = p_uid)
     and not exists (select 1 from public.sospechas s
                      where s.user_id = p_uid and s.tipo = p_tipo and s.creado > now() - interval '1 hour');
$$;
revoke all on function public.marcar_sospecha(uuid, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- al borrar una cagada
create or replace function public.cagadas_anotar_borrada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  n24 int;
  n1h int;
begin
  -- Nada de esto puede impedir que alguien borre lo suyo (ni que se borre una cuenta).
  begin
    if not exists (select 1 from public.profiles where id = old.user_id) then
      return old;
    end if;
    delete from public.cagadas_borradas where user_id = old.user_id and borrada_en < now() - interval '7 days';
    insert into public.cagadas_borradas (user_id, cagada_id, creada, rapida)
    values (old.user_id, old.id, old.created_at, old.created_at > now() - interval '2 hours');
    if old.created_at <= now() - interval '2 hours' then
      return old;
    end if;
    select count(*) filter (where borrada_en > now() - interval '24 hours'),
           count(*) filter (where borrada_en > now() - interval '1 hour')
      into n24, n1h
      from public.cagadas_borradas
     where user_id = old.user_id and rapida;
    if n24 >= 3 or n1h >= 2 then
      insert into public.pocetas_tapadas as t (user_id, hasta)
      values (old.user_id, now() + interval '3 hours')
      on conflict (user_id) do update
        set hasta = greatest(t.hasta, excluded.hasta),
            veces = t.veces + case when t.hasta > now() then 0 else 1 end;
      perform public.marcar_sospecha(old.user_id, 'poceta_tapada', jsonb_build_object('deshechas_24h', n24, 'deshechas_1h', n1h));
    elsif n24 >= 2 then
      perform public.marcar_sospecha(old.user_id, 'deshacer_repetido', jsonb_build_object('deshechas_24h', n24));
    end if;
  exception when others then
    null;
  end;
  return old;
end;
$$;

drop trigger if exists cagadas_borrada on public.cagadas;
create trigger cagadas_borrada after delete on public.cagadas
  for each row execute function public.cagadas_anotar_borrada();

-- ---------------------------------------------------------------- límite al cagar
create or replace function public.limitar_cagadas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ultima timestamptz;
  borrada timestamptz;
  tapa timestamptz;
  quien text;
begin
  new.created_at := now();
  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  quien := case when (select genero from public.profiles where id = new.user_id) = 'mujer' then 'reina' else 'rey' end;

  select hasta into tapa from public.pocetas_tapadas where user_id = new.user_id;
  if tapa is not null and tapa > now() then
    raise exception 'Se tapó la poceta, %: de tanto cagar y deshacer ya no baja nada. Vuelve en % min.',
      quien, ceil(extract(epoch from (tapa - now())) / 60)::int
      using errcode = 'P0001', hint = 'poceta_tapada';
  end if;

  select max(created_at) into ultima from public.cagadas where user_id = new.user_id;
  -- Deshaceres rápidos de las últimas 24 h menos el primero: su hora sigue contando.
  select max(b.creada) into borrada
    from (select creada from public.cagadas_borradas
           where user_id = new.user_id and rapida and borrada_en > now() - interval '24 hours'
           order by borrada_en asc offset 1) b;
  ultima := greatest(ultima, borrada);

  if ultima is not null and ultima > now() - interval '1 hour' then
    raise exception 'Calma, %: solo una por hora. Espera % min más.',
      quien, ceil(extract(epoch from (ultima + interval '1 hour' - now())) / 60)::int
      using errcode = 'P0001', hint = 'limite_hora';
  end if;
  return new;
end;
$$;

-- Lo que la app muestra al deshacer: cuántos deshaceres rápidos lleva en 24 h y hasta cuándo está tapada.
create or replace function public.poceta_estado()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'deshechas_24h', (select count(*) from public.cagadas_borradas b
                       where b.user_id = auth.uid() and b.rapida and b.borrada_en > now() - interval '24 hours'),
    'tapada_hasta', (select t.hasta from public.pocetas_tapadas t where t.user_id = auth.uid() and t.hasta > now()));
$$;
revoke all on function public.poceta_estado() from public, anon;
grant execute on function public.poceta_estado() to authenticated;

-- ---------------------------------------------------------------- push a seguidores
-- Igual que 20261019132559 + no avisa la cagada que reemplaza a una recién deshecha.
create or replace function public.avisar_cagada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.cagadas_borradas b
              where b.user_id = new.user_id and b.rapida and b.borrada_en > now() - interval '1 hour') then
    return new;
  end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('user_id', new.user_id, 'id', new.id)
  );
  return new;
end;
$$;

-- ---------------------------------------------------------------- carga del Imperio
-- Igual que 20261102120000 + descuenta las Fichas de cagadas que ya se cobraron y después se borraron rápido.
create or replace function public.imperio_cargar() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  fila public.imperio;
  total int;
  guardado_previo timestamptz;
  nuevas jsonb := '[]'::jsonb;
  cuenta int := 0;
  quitar int := 0;
  es_nuevo boolean := false;
  prob double precision;
  ganadas int := 0;
begin
  if uid is null then raise exception 'no autenticado'; end if;
  select coalesce(cagadas, 0) into total from public.profiles where id = uid;
  total := coalesce(total, 0);

  select * into fila from public.imperio where user_id = uid for update;
  if not found then
    -- Herencia del Trono: 1 ficha por cada 5 cagadas, tope 5
    insert into public.imperio (user_id, fundador, fichas, cagadas_hasta)
    values (
      uid,
      exists (select 1 from public.cagadas where user_id = uid and created_at < public.imperio_lanzamiento()),
      least(5, total / 5),
      now()
    )
    on conflict (user_id) do nothing;
    select * into fila from public.imperio where user_id = uid for update;
    es_nuevo := true;
    guardado_previo := fila.guardado;
  else
    guardado_previo := fila.guardado;
    select coalesce(jsonb_agg(jsonb_build_object('tipo', t.tipo, 'peso', t.peso, 'creada', t.created_at) order by t.created_at), '[]'::jsonb),
           count(*)
      into nuevas, cuenta
      from (
        select tipo, peso, created_at from public.cagadas
        where user_id = uid and created_at > fila.cagadas_hasta
        order by created_at asc limit 20
      ) t;
    -- Cagadas que ya dieron Ficha en una carga anterior y se deshicieron después: esa Ficha se devuelve.
    select count(*) into quitar
      from public.cagadas_borradas b
     where b.user_id = uid and b.rapida and b.creada <= fila.cagadas_hasta and b.borrada_en > fila.cagadas_hasta;
    -- Cada cagada real nueva tira ~5% de Ciruela; las estéticas suben la probabilidad.
    if cuenta > 0 then
      prob := 0.05 * (1 + public.imperio_bono_suerte(fila.esteticas));
      select count(*) into ganadas from generate_series(1, cuenta) where random() < prob;
    end if;
    update public.imperio
      set fichas = greatest(0, least(5, fichas + cuenta - quitar)), ciruelas = ciruelas + ganadas, cagadas_hasta = now()
      where user_id = uid
      returning * into fila;
  end if;

  return jsonb_build_object(
    'estado', fila.estado,
    'mj_total', fila.mj_total,
    'mps', fila.mps,
    'fichas', fila.fichas,
    'fundador', fila.fundador,
    'nuevo', es_nuevo,
    'nuevas', nuevas,
    'cagadas_total', total,
    'guardado', guardado_previo,
    'ahora', now(),
    'ciruelas', fila.ciruelas,
    'ciruelas_cagadas', ganadas,
    'esteticas', to_jsonb(fila.esteticas),
    'racha_dia', fila.racha_dia,
    'racha_fecha', fila.racha_fecha,
    'congeladores', fila.congeladores,
    'tanque_extra', fila.tanque_extra,
    'racha_salvados', to_jsonb(fila.racha_salvados)
  );
end $$;

-- ---------------------------------------------------------------- detector diario
-- Marca lo que no cuadra en las últimas 24 h. Para agregar otro chequeo: otro bloque insert ... select aquí,
-- con un tipo nuevo, y su consulta en supabase/consultas/exploits.sql.
create or replace function public.detectar_exploits()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n int := 0;
  m int;
begin
  -- Descargas del Imperio por más cagadas de las que existen (cagar, cobrar, deshacer, repetir).
  with descargas as (
    select e.user_id, sum(coalesce((e.datos ->> 'cagadas')::int, 0)) as cobradas
      from public.imperio_eventos e
     where e.evento = 'descarga' and e.creado > now() - interval '24 hours'
       and coalesce(e.datos ->> 'cagadas', '') ~ '^[0-9]{1,4}$'
     group by e.user_id
  ),
  reales as (
    select c.user_id, count(*) as hechas from public.cagadas c
     where c.created_at > now() - interval '24 hours' group by c.user_id
  ),
  raros as (
    select d.user_id, d.cobradas, coalesce(r.hechas, 0) as hechas
      from descargas d left join reales r on r.user_id = d.user_id
     where d.cobradas > coalesce(r.hechas, 0) + 1
  )
  select count(*) into m from raros x, lateral (
    select public.marcar_sospecha(x.user_id, 'descargas_de_mas', jsonb_build_object('cobradas', x.cobradas, 'reales', x.hechas))
  ) s;
  n := n + m;

  -- Muchos deshaceres en 24 h aunque no hayan tapado la poceta (por ejemplo, borrando desde el calendario).
  select count(*) into m from (
    select b.user_id, count(*) as k from public.cagadas_borradas b
     where b.borrada_en > now() - interval '24 hours' group by b.user_id having count(*) >= 5
  ) x, lateral (select public.marcar_sospecha(x.user_id, 'muchos_borrados', jsonb_build_object('borradas_24h', x.k))) s;
  n := n + m;

  delete from public.sospechas where creado < now() - interval '90 days';
  return n;
end;
$$;
revoke all on function public.detectar_exploits() from public, anon, authenticated;

select cron.unschedule('detectar_exploits') where exists (select 1 from cron.job where jobname = 'detectar_exploits');
select cron.schedule('detectar_exploits', '45 4 * * *', 'select public.detectar_exploits()');

-- Para el panel (solo admins): las últimas sospechas con su usuario.
create or replace function public.panel_sospechas(p_n int default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.es_admin() then raise exception 'solo admins'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('creado', s.creado, 'usuario', p.username, 'tipo', s.tipo, 'datos', s.datos) order by s.creado desc)
      from (select * from public.sospechas order by creado desc limit least(greatest(p_n, 1), 200)) s
      left join public.profiles p on p.id = s.user_id), '[]'::jsonb);
end;
$$;
revoke all on function public.panel_sospechas(int) from public, anon;
grant execute on function public.panel_sospechas(int) to authenticated;

-- ---------------------------------------------------------------- logro secreto
alter table public.logros drop constraint if exists logros_clave_valida;
alter table public.logros add constraint logros_clave_valida check (clave in (
  'psst_meon', 'psst_pulcro', 'psst_todas', 'corona', 'placer_lado',
  'trono_mosca', 'trono_pujo', 'trono_golpe', 'trono_desvelo', 'trono_filosofo',
  'poceta_tapada'
));

-- ---------------------------------------------------------------- avisos de racha
alter table public.push_ajustes
  add column if not exists racha_ultima_en timestamptz,
  add column if not exists racha_manana_en timestamptz;

-- Igual que 20261102120000 más dos momentos. Cada lista lleva 'momento':
--   aviso (20:00, reclamó ayer y no hoy), ultima (23:00, igual), perdida / congelador (10:00 del día siguiente
--   al que no entró: sin congelador perdió la racha; con congelador todavía la salva si entra hoy).
create or replace function public.push_racha_revisar()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  lista jsonb;
  n integer;
begin
  if not coalesce((select racha_activo from public.push_config), false) then
    return 0;
  end if;

  with zonas as (
    select distinct on (t.user_id) t.user_id,
           case when exists (select 1 from pg_catalog.pg_timezone_names z where z.name = t.zona)
                then t.zona else 'America/Caracas' end as zona
      from public.push_tokens t
     where t.user_id is not null
     order by t.user_id, t.updated_at desc
  ),
  base as (
    select z.user_id,
           (now() at time zone z.zona)::date as hoy_local,
           extract(hour from now() at time zone z.zona)::int as hora,
           (date_trunc('day', now() at time zone z.zona) at time zone z.zona) as inicio_dia,
           a.racha_en, a.racha_ultima_en, a.racha_manana_en
      from zonas z
      left join public.push_ajustes a on a.user_id = z.user_id
     where coalesce(a.racha, true)
       and extract(hour from now() at time zone z.zona) in (10, 20, 23)
  ),
  elegidos as (
    select b.user_id,
           case b.hora when 20 then 'aviso' when 23 then 'ultima'
                else case when i.congeladores > 0 then 'congelador' else 'perdida' end end as momento,
           i.racha_dia as llevas, i.racha_dia % 30 + 1 as dia, i.congeladores
      from base b
      join public.imperio i on i.user_id = b.user_id
     where i.racha_dia > 0
       and ((b.hora = 20 and i.racha_fecha = b.hoy_local - 1 and (b.racha_en is null or b.racha_en < b.inicio_dia))
         or (b.hora = 23 and i.racha_fecha = b.hoy_local - 1 and (b.racha_ultima_en is null or b.racha_ultima_en < b.inicio_dia))
         or (b.hora = 10 and i.racha_fecha = b.hoy_local - 2 and i.racha_dia >= 2
             and (b.racha_manana_en is null or b.racha_manana_en < b.inicio_dia)))
  ),
  marcados as (
    insert into public.push_ajustes as a (user_id, racha_en, racha_ultima_en, racha_manana_en)
    select user_id,
           case when momento = 'aviso' then now() end,
           case when momento = 'ultima' then now() end,
           case when momento in ('perdida', 'congelador') then now() end
      from elegidos
    on conflict (user_id) do update
      set racha_en = coalesce(excluded.racha_en, a.racha_en),
          racha_ultima_en = coalesce(excluded.racha_ultima_en, a.racha_ultima_en),
          racha_manana_en = coalesce(excluded.racha_manana_en, a.racha_manana_en)
    returning user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('user_id', e.user_id, 'momento', e.momento, 'llevas', e.llevas, 'dia', e.dia,
                                               'congeladores', e.congeladores)), '[]'::jsonb),
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
      body := jsonb_build_object('tipo', 'racha', 'lista', lista)
    );
  end if;
  return n;
end;
$$;
revoke all on function public.push_racha_revisar() from public, anon, authenticated;
