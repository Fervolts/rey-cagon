-- Imperio fase 4: Regalos 🎁. Un Rollo de papel 🧻 de regalo por amigo y por día (día de Caracas).
--   * Amigo = se siguen los dos (follows en los dos sentidos) y sin bloqueo.
--   * Topes por día: regalos_envios_dia (lo que mandas) y regalos_recibidos_dia (lo que te llega y lo que abres).
--   * Abrirlo da regalos_minutos de la producción propia de quien lo abre (la app lo suma como la Lluvia).
--     Topes duros aquí: minutos 1..60 y 1..10 por día, así el margen de imperio_guardar
--     (20261107130000_imperio_antitrampa.sql: +216000 s de ritmo por guardado) lo cubre sin tocarlo.
--   * Un regalo sin abrir vence a los regalos_vence_dias días.
--   * El primer regalo del día de cada quien sale como tarjeta 'regalo' en la sala general (flag regalos_chat).
--     No hay mensajes directos: la tarjeta es pública y no lleva @ (sin push de mención duplicado).
--   * Push 'regalo' al que lo recibe (categoría imperio de push_ajustes, interruptor push_config.regalos_activo).
--   * validar_mensaje (última versión: 20261101160000_imperio_tarjeta_bano.sql) igual más dos ramas que solo
--     acepta cuando escribe el servidor (GUC imperio.tarjeta_servidor = '1'): 'regalo' e 'imperio' (genérica).
-- Las apps viejas no llaman nada de esto; las tarjetas nuevas les salen como la caja de 💩 de tarjeta desconocida.

-- ---------------------------------------------------------------- flags
insert into public.imperio_flags (clave, valor, nota) values
  ('regalos_activo', 'true', 'Regalos del Imperio prendidos'),
  ('regalos_minutos', '30', 'Minutos de producción propia que da abrir un regalo (1..60)'),
  ('regalos_envios_dia', '5', 'Regalos que puedes mandar por día de Caracas (1..10)'),
  ('regalos_recibidos_dia', '5', 'Regalos que te pueden llegar, y que puedes abrir, por día de Caracas (1..10)'),
  ('regalos_vence_dias', '7', 'Días que dura un regalo sin abrir'),
  ('regalos_chat', 'true', 'El primer regalo del día de cada quien sale como tarjeta en la sala general')
on conflict (clave) do nothing;

alter table public.push_config add column if not exists regalos_activo boolean not null default true;

-- ---------------------------------------------------------------- tabla
create table public.imperio_regalos (
  id uuid primary key default gen_random_uuid(),
  de uuid not null references public.profiles (id) on delete cascade,
  para uuid not null references public.profiles (id) on delete cascade,
  dia date not null default (now() at time zone 'America/Caracas')::date,
  creado timestamptz not null default now(),
  abierto timestamptz,
  minutos int check (minutos between 1 and 60),
  en_chat boolean not null default false,
  unique (de, para, dia),
  check (de <> para)
);
create index imperio_regalos_pendientes_idx on public.imperio_regalos (para, creado) where abierto is null;
create index imperio_regalos_de_dia_idx on public.imperio_regalos (de, dia);
create index imperio_regalos_para_dia_idx on public.imperio_regalos (para, dia);
create index imperio_regalos_abiertos_idx on public.imperio_regalos (para, abierto) where abierto is not null;
alter table public.imperio_regalos enable row level security;
-- Cada quien ve los que dio y los que le dieron (la tarjeta del chat mira si sigue sin abrir). Nadie escribe directo.
create policy imperio_regalos_ver on public.imperio_regalos for select to authenticated
  using ((select auth.uid()) in (de, para));
revoke insert, update, delete, truncate on public.imperio_regalos from anon, authenticated;

-- ---------------------------------------------------------------- ayudas internas
create function public.imperio_regalos_flag(p_clave text, p_defecto numeric, p_min numeric, p_max numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select least(greatest(coalesce((select (f.valor #>> '{}')::numeric from public.imperio_flags f
                                  where f.clave = p_clave and f.activo and jsonb_typeof(f.valor) = 'number'), p_defecto),
                        p_min), p_max)
$$;
revoke all on function public.imperio_regalos_flag(text, numeric, numeric, numeric) from public, anon, authenticated;

create function public.imperio_regalos_si(p_clave text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select f.valor = 'true'::jsonb from public.imperio_flags f where f.clave = p_clave and f.activo), true)
$$;
revoke all on function public.imperio_regalos_si(text) from public, anon, authenticated;

-- Inicio del día de Caracas como instante.
create function public.imperio_inicio_dia()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (date_trunc('day', now() at time zone 'America/Caracas')) at time zone 'America/Caracas'
$$;
revoke all on function public.imperio_inicio_dia() from public, anon, authenticated;

-- Tarjeta del Imperio en la sala general, puesta por el servidor a nombre de p_user. Para otras fases
-- (Mudanza, etc.): perform public.imperio_tarjeta_chat(auth.uid(), jsonb_build_object('tipo', 'imperio',
-- 'emoji', '🚚', 'titulo', '...', 'linea', '...')). Si el chat la rechaza, no rompe a quien la llama.
create function public.imperio_tarjeta_chat(p_user uuid, p_tarjeta jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  nuevo bigint;
begin
  if p_user is null or p_tarjeta is null then return null; end if;
  perform set_config('imperio.tarjeta_servidor', '1', true);
  begin
    insert into public.mensajes (sala, user_id, texto, tarjeta) values ('global', p_user, '', p_tarjeta) returning id into nuevo;
  exception when others then
    nuevo := null;
  end;
  perform set_config('imperio.tarjeta_servidor', '', true);
  return nuevo;
end;
$$;
revoke all on function public.imperio_tarjeta_chat(uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- RPC de la app
-- Manda un regalo. {ok, motivo?, id?, dados?, enviados_hoy?, tope_envios?}.
-- motivo: apagado, no_amigos, ya_hoy, tope_envios, tope_recibidos.
create function public.imperio_regalar(p_para uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  yo uuid := auth.uid();
  hoy date := (now() at time zone 'America/Caracas')::date;
  tope_e int := public.imperio_regalos_flag('regalos_envios_dia', 5, 1, 10)::int;
  tope_r int := public.imperio_regalos_flag('regalos_recibidos_dia', 5, 1, 10)::int;
  enviados int;
  nuevo uuid;
  en_chat boolean := false;
begin
  if yo is null then raise exception 'sin sesión' using errcode = '28000'; end if;
  if not public.imperio_regalos_si('regalos_activo') then
    return jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;
  if p_para is null or p_para = yo or public.hay_bloqueo(p_para)
     or not exists (select 1 from public.follows f where f.follower = yo and f.followed = p_para)
     or not exists (select 1 from public.follows f where f.follower = p_para and f.followed = yo) then
    return jsonb_build_object('ok', false, 'motivo', 'no_amigos');
  end if;
  -- Candados en orden fijo: dos que se regalan a la vez no se trancan.
  perform pg_advisory_xact_lock(hashtext('imperio_regalos:' || least(yo, p_para)::text));
  perform pg_advisory_xact_lock(hashtext('imperio_regalos:' || greatest(yo, p_para)::text));
  if exists (select 1 from public.imperio_regalos r where r.de = yo and r.para = p_para and r.dia = hoy) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_hoy');
  end if;
  select count(*) into enviados from public.imperio_regalos r where r.de = yo and r.dia = hoy;
  if enviados >= tope_e then
    return jsonb_build_object('ok', false, 'motivo', 'tope_envios', 'enviados_hoy', enviados, 'tope_envios', tope_e);
  end if;
  if (select count(*) from public.imperio_regalos r where r.para = p_para and r.dia = hoy) >= tope_r then
    return jsonb_build_object('ok', false, 'motivo', 'tope_recibidos');
  end if;

  insert into public.imperio_regalos (de, para, dia) values (yo, p_para, hoy) returning id into nuevo;

  -- Tarjeta en el chat: solo el primer regalo del día de cada quien.
  if public.imperio_regalos_si('regalos_chat')
     and not exists (select 1 from public.imperio_regalos r where r.de = yo and r.dia = hoy and r.en_chat) then
    en_chat := public.imperio_tarjeta_chat(yo, jsonb_build_object('tipo', 'regalo', 'id', nuevo)) is not null;
    if en_chat then update public.imperio_regalos set en_chat = true where id = nuevo; end if;
  end if;

  -- Push al que lo recibe. Si falla, el regalo igual queda.
  if coalesce((select c.regalos_activo from public.push_config c), true) then
    begin
      perform net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
        ),
        body := jsonb_build_object('tipo', 'regalo', 'id', nuevo)
      );
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'id', nuevo, 'en_chat', en_chat,
    'dados', (select count(*) from public.imperio_regalos r where r.de = yo),
    'enviados_hoy', enviados + 1, 'tope_envios', tope_e);
end;
$$;

-- Lo que tengo por abrir y cómo van los topes de hoy.
-- {regalos: [{id, de, de_nombre, de_avatar, creado}], minutos, abiertos_hoy, tope_abrir, enviados_hoy, tope_envios,
--  regalados_hoy: [uuid a quienes ya les regalé hoy], dados: total que he regalado (logros), activo}
create function public.imperio_regalos_pendientes()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  yo uuid := auth.uid();
  hoy date := (now() at time zone 'America/Caracas')::date;
  vence int := public.imperio_regalos_flag('regalos_vence_dias', 7, 1, 30)::int;
begin
  if yo is null then raise exception 'sin sesión' using errcode = '28000'; end if;
  return jsonb_build_object(
    'activo', public.imperio_regalos_si('regalos_activo'),
    'minutos', public.imperio_regalos_flag('regalos_minutos', 30, 1, 60)::int,
    'tope_abrir', public.imperio_regalos_flag('regalos_recibidos_dia', 5, 1, 10)::int,
    'tope_envios', public.imperio_regalos_flag('regalos_envios_dia', 5, 1, 10)::int,
    'abiertos_hoy', (select count(*) from public.imperio_regalos r where r.para = yo and r.abierto >= public.imperio_inicio_dia()),
    'enviados_hoy', (select count(*) from public.imperio_regalos r where r.de = yo and r.dia = hoy),
    'regalados_hoy', coalesce((select jsonb_agg(r.para) from public.imperio_regalos r where r.de = yo and r.dia = hoy), '[]'::jsonb),
    'dados', (select count(*) from public.imperio_regalos r where r.de = yo),
    'regalos', coalesce((
      select jsonb_agg(jsonb_build_object('id', q.id, 'de', q.de, 'de_nombre', q.username, 'de_avatar', q.avatar, 'creado', q.creado)
                       order by q.creado)
      from (select r.id, r.de, r.creado, p.username, p.avatar
            from public.imperio_regalos r
            join public.profiles p on p.id = r.de
            where r.para = yo and r.abierto is null and r.creado > now() - make_interval(days => vence)
              and not public.hay_bloqueo(r.de)
            order by r.creado
            limit 50) q), '[]'::jsonb));
end;
$$;

-- Abre un regalo. {ok, motivo?, minutos?, mutuo?, abiertos?}. motivo: no_existe, ya_abierto, vencido, tope_abrir, apagado.
-- mutuo = ese día tú también le regalaste a quien te lo dio (logro oculto). abiertos = cuántos has abierto en total.
create function public.imperio_regalo_abrir(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  yo uuid := auth.uid();
  g public.imperio_regalos;
  tope int := public.imperio_regalos_flag('regalos_recibidos_dia', 5, 1, 10)::int;
  vence int := public.imperio_regalos_flag('regalos_vence_dias', 7, 1, 30)::int;
  m int := public.imperio_regalos_flag('regalos_minutos', 30, 1, 60)::int;
begin
  if yo is null then raise exception 'sin sesión' using errcode = '28000'; end if;
  if not public.imperio_regalos_si('regalos_activo') then
    return jsonb_build_object('ok', false, 'motivo', 'apagado');
  end if;
  perform pg_advisory_xact_lock(hashtext('imperio_regalos_abrir:' || yo::text));
  select * into g from public.imperio_regalos r where r.id = p_id and r.para = yo for update;
  if g.id is null then return jsonb_build_object('ok', false, 'motivo', 'no_existe'); end if;
  if g.abierto is not null then return jsonb_build_object('ok', false, 'motivo', 'ya_abierto'); end if;
  if g.creado <= now() - make_interval(days => vence) then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  if (select count(*) from public.imperio_regalos r where r.para = yo and r.abierto >= public.imperio_inicio_dia()) >= tope then
    return jsonb_build_object('ok', false, 'motivo', 'tope_abrir');
  end if;
  update public.imperio_regalos set abierto = now(), minutos = m where id = g.id;
  return jsonb_build_object('ok', true, 'id', g.id, 'minutos', m,
    'mutuo', exists (select 1 from public.imperio_regalos r where r.de = yo and r.para = g.de and r.dia = g.dia),
    'abiertos', (select count(*) from public.imperio_regalos r where r.para = yo and r.abierto is not null));
end;
$$;

revoke all on function public.imperio_regalar(uuid) from public, anon;
revoke all on function public.imperio_regalos_pendientes() from public, anon;
revoke all on function public.imperio_regalo_abrir(uuid) from public, anon;
grant execute on function public.imperio_regalar(uuid) to authenticated;
grant execute on function public.imperio_regalos_pendientes() to authenticated;
grant execute on function public.imperio_regalo_abrir(uuid) to authenticated;

-- ---------------------------------------------------------------- chat
create or replace function public.validar_mensaje()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  total bigint;
  malo text;
  t text;
  c record;
  d record;
  r public.cagadas;
  im public.imperio;
  rollos numeric;
  e jsonb;
  v jsonb;
  g public.imperio_regalos;
begin
  -- auth.uid() es null cuando escribe el servidor (cierre de retos): se respeta el user_id.
  new.user_id := coalesce(auth.uid(), new.user_id);
  new.oculto := false;
  new.created_at := now();
  new.texto := btrim(new.texto);
  if public.sala_publica(new.sala) then new.es_bug := false; end if;
  if new.texto = '' and new.tarjeta is null then
    raise exception 'Mensaje vacío' using errcode = 'P0001';
  end if;
  malo := public.link_peligroso(new.texto);
  if malo is not null then
    raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
  end if;
  if public.sala_publica(new.sala) and (new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') then
    raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
  end if;

  if new.tarjeta is not null then
    t := new.tarjeta ->> 'tipo';
    select count(*) into total from public.cagadas where user_id = new.user_id;
    if t = 'hito' then
      if not ((new.tarjeta ->> 'n')::int = any (public.hitos())) or (new.tarjeta ->> 'n')::int > total then
        raise exception 'Todavía no llegas a ese número' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'hito', 'n', (new.tarjeta ->> 'n')::int,
        'reina', coalesce((select genero = 'mujer' from public.profiles where id = new.user_id), false));
    elsif t = 'desbloqueo' then
      select * into d from public.desbloqueos x where x.emoji = new.tarjeta ->> 'emoji' limit 1;
      if d is null or d.minimo > total then
        raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'desbloqueo', 'emoji', d.emoji, 'ranura', d.ranura, 'minimo', d.minimo);
    elsif t = 'cagada' then
      select x.id, x.tipo, x.peso, x.created_at into c from public.cagadas x
        where x.id = (new.tarjeta ->> 'id')::bigint and x.user_id = new.user_id;
      if c is null or c.tipo is null then
        raise exception 'Esa cagada no existe o no dijiste qué salió' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'cagada', 'mojon', c.tipo, 'peso', c.peso,
        'n', (select count(*) from public.cagadas x where x.user_id = new.user_id and x.created_at <= c.created_at));
    elsif t = 'racha' then
      select * into r from public.cagadas x
        where x.id = (new.tarjeta ->> 'id')::bigint and x.user_id = new.user_id;
      if r.id is null or public.racha_del_dia(r) < 2 then
        raise exception 'Esa cagada no es racha' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.tarjeta ->> 'tipo' = 'racha' and (x.tarjeta ->> 'id')::bigint = r.id) then
        raise exception 'Esa racha ya salió en el chat' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'racha', 'id', r.id, 'n', public.racha_del_dia(r));
    elsif t in ('reto', 'reto_fin') then
      if not exists (select 1 from public.retos x where x.id = (new.tarjeta ->> 'id')::bigint
                     and new.user_id in (x.retador, x.retado)
                     and x.estado = case t when 'reto' then 'aceptado' else 'terminado' end) then
        raise exception 'Ese reto no es tuyo' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', t, 'id', (new.tarjeta ->> 'id')::bigint);
    elsif t = 'logro_imperio' then
      if coalesce(new.tarjeta ->> 'id', '') !~ '^[a-z0-9_]{1,40}$'
         or not exists (select 1 from public.imperio x where x.user_id = new.user_id
                        and jsonb_typeof(x.estado -> 'logros') = 'array'
                        and (x.estado -> 'logros') ? (new.tarjeta ->> 'id')) then
        raise exception 'Todavía no tienes ese logro del Imperio' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'logro_imperio', 'id', new.tarjeta ->> 'id');
    elsif t = 'jalada' then
      select * into im from public.imperio x where x.user_id = new.user_id;
      if im.user_id is null or coalesce(new.tarjeta ->> 'n', '') !~ '^[0-9]{1,9}$'
         or (new.tarjeta ->> 'n')::int <> im.jaladas or im.jaladas < 1
         or im.jalada_en is null or im.jalada_en < now() - interval '1 day' then
        raise exception 'Esa jalada no existe o ya pasó' using errcode = 'P0001';
      end if;
      if coalesce(new.tarjeta ->> 'rollos', '') !~ '^[0-9]{1,13}$' then
        raise exception 'Rollos fuera de rango' using errcode = 'P0001';
      end if;
      rollos := (new.tarjeta ->> 'rollos')::numeric;
      if rollos > 1e12 or rollos > public.imperio_rollos_max(im.mj_total) then
        raise exception 'Rollos fuera de rango' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.user_id = new.user_id and x.tarjeta ->> 'tipo' = 'jalada'
                 and x.tarjeta ->> 'n' = im.jaladas::text) then
        raise exception 'Esa jalada ya salió en el chat' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'jalada', 'n', im.jaladas, 'rollos', rollos::bigint);
    elsif t = 'cartera' then
      select * into im from public.imperio x where x.user_id = new.user_id;
      if im.user_id is null then
        raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.user_id = new.user_id and x.tarjeta ->> 'tipo' = 'cartera'
                 and x.created_at > now() - interval '10 minutes') then
        raise exception 'Espera un rato para volver a presumir tu cartera' using errcode = 'P0001';
      end if;
      -- Los números salen de la fila del usuario (lo último que guardó), nunca de lo que manda el cliente.
      new.tarjeta := jsonb_build_object('tipo', 'cartera',
        'saldo', public.imperio_numero(im.estado ->> 'saldo'),
        'mps', public.imperio_numero(coalesce(im.estado ->> '_mps_edificios', im.mps::text)),
        'pujo', public.imperio_numero(im.estado ->> '_pujo'),
        'mj_total', greatest(coalesce(im.mj_total, 0), 0),
        'jaladas', greatest(im.jaladas, 0),
        'rollos', least(public.imperio_numero(im.estado ->> 'rollos'), public.imperio_rollos_max(im.mj_total)));
    elsif t = 'bano' then
      select * into im from public.imperio x where x.user_id = new.user_id;
      if im.user_id is null then
        raise exception 'Todavía no tienes Imperio' using errcode = 'P0001';
      end if;
      if exists (select 1 from public.mensajes x where x.user_id = new.user_id and x.tarjeta ->> 'tipo' = 'bano'
                 and x.created_at > now() - interval '10 minutes') then
        raise exception 'Espera un rato para volver a presumir tu baño' using errcode = 'P0001';
      end if;
      -- Solo lo que dibuja el baño, sacado de la fila (nunca del cliente). Lo que venga mal se vuelve vacío.
      e := case when jsonb_typeof(im.estado) = 'object' then im.estado else '{}'::jsonb end;
      v := case when jsonb_typeof(e -> 'vista') = 'object' then e -> 'vista' else '{}'::jsonb end;
      new.tarjeta := jsonb_build_object('tipo', 'bano',
        'edificios', coalesce((select jsonb_object_agg(x.k, least(floor(case when jsonb_typeof(x.n) = 'number' then (x.n)::numeric end), 1000000)::int)
          from jsonb_each(case when jsonb_typeof(e -> 'edificios') = 'object' then e -> 'edificios' else '{}'::jsonb end) x(k, n)
          where x.k = any (array['dedo', 'ciruela', 'cafe', 'arepa', 'inodoro', 'bano', 'camion', 'planta', 'cloaca', 'granja',
                                 'mina', 'templo', 'volcan', 'laxante_tiempo', 'agujero'])
            and case when jsonb_typeof(x.n) = 'number' then (x.n)::numeric >= 1 else false end), '{}'::jsonb),
        'mejoras', coalesce((select jsonb_agg(q.m order by q.m) from (
          select distinct m from jsonb_array_elements_text(
            case when jsonb_typeof(e -> 'mejoras') = 'array' then e -> 'mejoras' else '[]'::jsonb end) m
          where m ~ '^((adorno|tanque|valvula|dedo|ciruela|cafe|arepa|inodoro|bano|camion|planta)_[a-z0-9]{1,20}|iman|brillo|lavanda|guantes|faja)$'
          order by m limit 200) q), '[]'::jsonb),
        'esteticas', coalesce((select jsonb_agg(q.s order by q.s) from (
          select distinct s from unnest(im.esteticas) s where s ~ '^est_[a-z0-9_]{1,40}$' order by s limit 100) q), '[]'::jsonb),
        'vista', jsonb_strip_nulls(jsonb_build_object(
          'ocultos', (select jsonb_agg(q.o order by q.o) from (
            select distinct o from jsonb_array_elements_text(
              case when jsonb_typeof(v -> 'ocultos') = 'array' then v -> 'ocultos' else '[]'::jsonb end) o
            where o ~ '^[a-z0-9_]{1,40}$' order by o limit 100) q),
          'dedos', case when jsonb_typeof(v -> 'dedos') = 'number'
                        then least(greatest(floor((v -> 'dedos')::numeric), 0), 24)::int end,
          'ambiente', case when jsonb_typeof(v -> 'ambiente') = 'string' and v ->> 'ambiente' ~ '^[a-z]{1,20}$'
                           then v ->> 'ambiente' end)));
    elsif t = 'regalo' then
      -- Solo la pone imperio_regalar (servidor). Lleva quién da (el autor del mensaje) y a quién va.
      if coalesce(current_setting('imperio.tarjeta_servidor', true), '') <> '1'
         or coalesce(new.tarjeta ->> 'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
      end if;
      select * into g from public.imperio_regalos x where x.id = (new.tarjeta ->> 'id')::uuid and x.de = new.user_id;
      if g.id is null then
        raise exception 'Ese regalo no existe' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'regalo', 'id', g.id, 'de', g.de, 'para', g.para,
        'de_nombre', coalesce((select p.username from public.profiles p where p.id = g.de), ''),
        'para_nombre', coalesce((select p.username from public.profiles p where p.id = g.para), ''));
    elsif t = 'imperio' then
      -- Tarjeta genérica del Imperio {emoji, titulo, linea}: solo desde el servidor (imperio_tarjeta_chat).
      if coalesce(current_setting('imperio.tarjeta_servidor', true), '') <> '1' then
        raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'imperio',
        'emoji', left(coalesce(nullif(btrim(new.tarjeta ->> 'emoji'), ''), '💩'), 8),
        'titulo', left(coalesce(btrim(new.tarjeta ->> 'titulo'), ''), 60),
        'linea', left(coalesce(btrim(new.tarjeta ->> 'linea'), ''), 140));
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
