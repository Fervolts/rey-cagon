-- Cloacas: grupos de hasta 25 jugadores con liga semanal (lunes a domingo, hora de Caracas), bono de producción por
-- miembro que cagó hoy, chat propio y premio para la Cloaca ganadora (Rollos de Oro, el ícono de la app y una
-- tarjeta en la sala general). Todo lo que da puntos o premios lo cuenta el servidor.
begin;

-- Valores que se pueden ajustar sin publicar la app.
insert into public.imperio_flags (clave, valor, nota) values
  ('cloaca_max_miembros', '25', 'Máximo de miembros por Cloaca (2..100)'),
  ('cloaca_premio_rollos', '2', 'Rollos de Oro para cada miembro de la Cloaca ganadora de la semana (0..1000)'),
  ('cloaca_bono_por_miembro', '0.05', 'Bono de producción por cada miembro de tu Cloaca que cagó hoy (0..1)'),
  ('cloaca_bono_tope', '0.5', 'Tope del bono de producción de la Cloaca (0..1)'),
  ('cloaca_push', 'true', 'Push a los miembros de la Cloaca ganadora al cerrar la semana')
on conflict (clave) do nothing;

-- Tablas. Ninguna se lee directo desde la app: todo pasa por las funciones de abajo.
create table public.cloacas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(nombre) between 3 and 24),
  emoji text not null check (char_length(emoji) between 1 and 8),
  -- Si el dueño borra su cuenta queda null un momento y el trigger de cloaca_miembros pone al sucesor.
  dueno uuid references auth.users (id) on delete set null,
  codigo text not null unique check (codigo ~ '^[A-Z0-9]{6}$'),
  creado timestamptz not null default now()
);
create unique index cloacas_nombre_unico on public.cloacas (lower(nombre));

-- Una fila por jugador: solo se está en una Cloaca a la vez.
create table public.cloaca_miembros (
  user_id uuid primary key references auth.users (id) on delete cascade,
  cloaca_id uuid not null references public.cloacas (id) on delete cascade,
  unido timestamptz not null default now()
);
create index cloaca_miembros_cloaca on public.cloaca_miembros (cloaca_id, unido);

-- Tramos de tiempo en que alguien estuvo en una Cloaca dentro de una semana. Solo cuenta lo hecho dentro de un tramo.
-- mj_inicio/mj_fin: el mj_total del Imperio al empezar y al terminar el tramo (mj_fin null = sigue abierto).
create table public.cloaca_periodos (
  id bigint generated always as identity primary key,
  cloaca_id uuid not null references public.cloacas (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  semana date not null,
  desde timestamptz not null default now(),
  hasta timestamptz,
  mj_inicio double precision not null default 0,
  mj_fin double precision,
  expulsado boolean not null default false
);
create index cloaca_periodos_semana on public.cloaca_periodos (semana, cloaca_id);
create index cloaca_periodos_usuario on public.cloaca_periodos (user_id, semana);

-- Semanas ya cerradas (una vez cada una, aunque el cron corra dos veces).
create table public.cloaca_semanas (
  semana date primary key,
  ganadora uuid,
  cerrada timestamptz not null default now()
);

-- Historial de la liga: cómo quedó cada Cloaca con puntos cada semana. Guarda nombre y emoji por si se borra.
create table public.cloaca_historial (
  semana date not null,
  cloaca_id uuid not null,
  nombre text not null,
  emoji text not null,
  puntos int not null,
  puesto int not null,
  miembros int not null,
  primary key (semana, cloaca_id)
);

-- Rollos de Oro ganados en la liga. Se cobran desde la app (cloaca_premio_cobrar). Lo cobrado sube en lo mismo el
-- tope de Rollos de la casa (imperio_rollos_tope), así el premio no le quita espacio a las jaladas.
create table public.cloaca_premios (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  semana date not null,
  cloaca_id uuid not null,
  rollos int not null check (rollos >= 0),
  cobrados int not null default 0 check (cobrados >= 0),
  creado timestamptz not null default now(),
  unique (user_id, semana)
);

alter table public.cloacas enable row level security;
alter table public.cloaca_miembros enable row level security;
alter table public.cloaca_periodos enable row level security;
alter table public.cloaca_semanas enable row level security;
alter table public.cloaca_historial enable row level security;
alter table public.cloaca_premios enable row level security;
revoke all on public.cloacas, public.cloaca_miembros, public.cloaca_periodos, public.cloaca_semanas,
  public.cloaca_historial, public.cloaca_premios from anon, authenticated;

-- Lunes (fecha de Caracas) de la semana de un momento, y el instante en que empieza esa semana.
create function public.cloaca_semana_de(p_ts timestamptz)
returns date
language sql stable set search_path = '' as $$
  select date_trunc('week', p_ts at time zone 'America/Caracas')::date;
$$;

create function public.cloaca_semana_inicio(p_semana date)
returns timestamptz
language sql stable set search_path = '' as $$
  select p_semana::timestamp at time zone 'America/Caracas';
$$;
revoke all on function public.cloaca_semana_de(timestamptz) from public, anon;
revoke all on function public.cloaca_semana_inicio(date) from public, anon;

-- Puntos de una semana por miembro y Cloaca. 10 por cagada real (las primeras imperio_tope_dia() de cada día de Caracas) y hasta
-- 10 del Imperio: piso(log10(MJ ganados en los tramos + 1)). Si el Imperio se reinició dentro de un tramo (mj_total
-- bajó), cuenta lo que lleva desde el reinicio.
create function public.cloaca_puntos(p_semana date)
returns table (cloaca_id uuid, user_id uuid, cagadas int, pts_cagadas int, mj double precision, pts_imperio int, puntos int)
language sql stable security definer set search_path = '' as $$
  with lim as (
    select public.cloaca_semana_inicio(p_semana) as ini, public.cloaca_semana_inicio(p_semana + 7) as fin,
           public.imperio_tope_dia() as tope
  ), per as (
    select p.* from public.cloaca_periodos p where p.semana = p_semana
  ), cag as (
    -- Las primeras `tope` cagadas de cada jugador por día de Caracas, aunque cambie de Cloaca ese día.
    select c.id, c.user_id, c.created_at,
           row_number() over (partition by c.user_id, (c.created_at at time zone 'America/Caracas')::date
                              order by c.created_at, c.id) as n
    from public.cagadas c cross join lim
    where c.user_id in (select per.user_id from per) and c.created_at >= lim.ini and c.created_at < lim.fin
  ), pc as (
    -- Cada una cuenta para la Cloaca en la que estaba el jugador en ese momento.
    select p.cloaca_id, p.user_id, count(distinct cag.id)::int as n
    from per p cross join lim
    join cag on cag.user_id = p.user_id and cag.n <= lim.tope
     and cag.created_at >= p.desde and cag.created_at < coalesce(p.hasta, lim.fin)
    group by 1, 2
  ), pm as (
    select x.cloaca_id, x.user_id,
           sum(case when x.fin >= x.ini then x.fin - x.ini else x.fin end) as g
    from (
      select p.cloaca_id, p.user_id,
             least(greatest(coalesce(p.mj_inicio, 0), 0), 1e300) as ini,
             least(greatest(coalesce(p.mj_fin, im.mj_total, 0), 0), 1e300) as fin
      from per p left join public.imperio im on im.user_id = p.user_id
    ) x group by 1, 2
  )
  select pm.cloaca_id, pm.user_id,
         coalesce(pc.n, 0),
         coalesce(pc.n, 0) * 10,
         least(pm.g, 1e300),
         least(10, greatest(0, floor(log(least(pm.g, 1e300) + 1))))::int,
         coalesce(pc.n, 0) * 10 + least(10, greatest(0, floor(log(least(pm.g, 1e300) + 1))))::int
  from pm left join pc on pc.cloaca_id = pm.cloaca_id and pc.user_id = pm.user_id;
$$;
revoke all on function public.cloaca_puntos(date) from public, anon, authenticated;

-- Bono de producción de un jugador: cloaca_bono_por_miembro por cada miembro de su Cloaca (incluido él) que cagó hoy
-- (día de Caracas) estando ya en la Cloaca, con tope en cloaca_bono_tope. 0 si no está en ninguna.
create function public.cloaca_bono_de(p_user uuid)
returns double precision
language sql stable security definer set search_path = '' as $$
  select least(
    public.imperio_flag_numero('cloaca_bono_por_miembro', 0.05, 0, 1) * (
      select count(*) from public.cloaca_miembros m
      where m.cloaca_id = (select y.cloaca_id from public.cloaca_miembros y where y.user_id = p_user)
        and exists (select 1 from public.cagadas c where c.user_id = m.user_id
                    and c.created_at >= greatest(public.imperio_inicio_dia(), m.unido))),
    public.imperio_flag_numero('cloaca_bono_tope', 0.5, 0, 1));
$$;
revoke all on function public.cloaca_bono_de(uuid) from public, anon, authenticated;

-- Lo que usa la app para el multiplicador. El tope también lo aplica la app (Imperio.bonoCloaca).
create function public.cloaca_bono()
returns double precision
language sql stable security definer set search_path = '' as $$
  select coalesce(public.cloaca_bono_de(auth.uid()), 0);
$$;
revoke all on function public.cloaca_bono() from public, anon;
grant execute on function public.cloaca_bono() to authenticated;

-- ¿El que pregunta está en la Cloaca de esta sala de chat ('cloaca:<id>')? Para las políticas de mensajes.
create function public.cloaca_es_mia(p_sala text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select p_sala like 'cloaca:%' and exists (
    select 1 from public.cloaca_miembros m
    where m.user_id = (select auth.uid()) and 'cloaca:' || m.cloaca_id::text = p_sala);
$$;
revoke all on function public.cloaca_es_mia(text) from public, anon;
grant execute on function public.cloaca_es_mia(text) to authenticated;

-- Motivo por el que un nombre de Cloaca no sirve, o null. Mismas reglas que el chat: sin links, teléfonos ni correos.
create function public.cloaca_nombre_malo(p_nombre text)
returns text
language plpgsql immutable set search_path = '' as $$
begin
  if p_nombre is null or char_length(p_nombre) < 3 or char_length(p_nombre) > 24 then
    return 'El nombre va de 3 a 24 letras';
  end if;
  if public.link_peligroso(p_nombre) is not null or p_nombre ~* '(https?://|www\.|[a-z]{2,}:/)'
     or p_nombre ~* '[a-z0-9-]+\.(com|net|org|io|me|app|ly|gg|co|xyz|link|ve|info|biz|tv|site|online|store|shop|es|us)(\W|$)' then
    return 'El nombre no puede llevar links';
  end if;
  if p_nombre ~ '\+?\d[\d\s().-]{8,}\d' or p_nombre ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
    return 'El nombre no puede llevar teléfonos ni correos';
  end if;
  if p_nombre ~ '[<>\\]' or p_nombre ~ '[[:cntrl:]]' then
    return 'El nombre lleva caracteres que no se permiten';
  end if;
  return null;
end;
$$;
revoke all on function public.cloaca_nombre_malo(text) from public, anon, authenticated;

-- Abre el tramo de un miembro en la semana de ahora, con su mj_total de este momento.
create function public.cloaca_abrir_periodo(p_user uuid, p_cloaca uuid)
returns void
language sql security definer set search_path = '' as $$
  insert into public.cloaca_periodos (cloaca_id, user_id, semana, desde, mj_inicio)
  values (p_cloaca, p_user, public.cloaca_semana_de(now()), now(),
          coalesce((select least(greatest(im.mj_total, 0), 1e300) from public.imperio im where im.user_id = p_user), 0));
$$;
revoke all on function public.cloaca_abrir_periodo(uuid, uuid) from public, anon, authenticated;

-- Saca a alguien de su Cloaca (salir o expulsado): cierra su tramo, pasa la corona al miembro más viejo si era el
-- dueño y borra la Cloaca (con su chat) si queda vacía.
create function public.cloaca_sacar(p_user uuid, p_expulsado boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  m public.cloaca_miembros;
begin
  select * into m from public.cloaca_miembros x where x.user_id = p_user;
  if m.user_id is null then return; end if;
  perform 1 from public.cloacas c where c.id = m.cloaca_id for update;
  update public.cloaca_periodos p
     set hasta = now(), expulsado = p_expulsado,
         mj_fin = coalesce((select least(greatest(im.mj_total, 0), 1e300) from public.imperio im where im.user_id = p_user), 0)
   where p.user_id = p_user and p.hasta is null;
  delete from public.cloaca_miembros x where x.user_id = p_user;
end;
$$;

-- Al salir alguien (también si borra su cuenta): si era el dueño, pasa al miembro más antiguo; si no queda nadie, se
-- borran la Cloaca y su chat.
create function public.cloaca_tras_salida()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  sucesor uuid;
begin
  select x.user_id into sucesor from public.cloaca_miembros x where x.cloaca_id = old.cloaca_id
   order by x.unido, x.user_id limit 1;
  if sucesor is null then
    delete from public.mensajes x where x.sala = 'cloaca:' || old.cloaca_id::text;
    delete from public.cloacas c where c.id = old.cloaca_id;
  else
    update public.cloacas c set dueno = sucesor
     where c.id = old.cloaca_id and (c.dueno is null or c.dueno = old.user_id);
  end if;
  return null;
end;
$$;
revoke all on function public.cloaca_tras_salida() from public, anon, authenticated;
create trigger cloaca_tras_salida after delete on public.cloaca_miembros
  for each row execute function public.cloaca_tras_salida();
revoke all on function public.cloaca_sacar(uuid, boolean) from public, anon, authenticated;

-- Crear una Cloaca: quien la crea es el dueño y su primer miembro.
create function public.cloaca_crear(p_nombre text, p_emoji text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo uuid := auth.uid();
  v_nombre text := regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g');
  v_emoji text := btrim(coalesce(p_emoji, ''));
  malo text;
  cod text;
  nueva uuid;
  letras constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if yo is null then return jsonb_build_object('ok', false, 'motivo', 'sin_sesion'); end if;
  perform pg_advisory_xact_lock(hashtext('cloaca_yo' || yo::text));
  if exists (select 1 from public.cloaca_miembros x where x.user_id = yo) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_tienes');
  end if;
  malo := public.cloaca_nombre_malo(v_nombre);
  if malo is not null then return jsonb_build_object('ok', false, 'motivo', 'nombre', 'texto', malo); end if;
  if v_emoji = '' then v_emoji := '💩'; end if;
  if char_length(v_emoji) > 8 or v_emoji ~ '[A-Za-z0-9[:space:][:cntrl:]<>"''\\/.,;:]' then
    return jsonb_build_object('ok', false, 'motivo', 'emoji');
  end if;
  if exists (select 1 from public.cloacas c where lower(c.nombre) = lower(v_nombre)) then
    return jsonb_build_object('ok', false, 'motivo', 'nombre_usado');
  end if;
  if (select count(*) from public.cloaca_periodos p where p.user_id = yo and p.semana = public.cloaca_semana_de(now())) >= 20 then
    return jsonb_build_object('ok', false, 'motivo', 'muchos_cambios');
  end if;
  loop
    cod := (select string_agg(substr(letras, 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    exit when not exists (select 1 from public.cloacas c where c.codigo = cod);
  end loop;
  insert into public.cloacas (nombre, emoji, dueno, codigo) values (v_nombre, v_emoji, yo, cod) returning id into nueva;
  insert into public.cloaca_miembros (user_id, cloaca_id) values (yo, nueva);
  perform public.cloaca_abrir_periodo(yo, nueva);
  return jsonb_build_object('ok', true, 'id', nueva, 'codigo', cod);
end;
$$;
revoke all on function public.cloaca_crear(text, text) from public, anon;
grant execute on function public.cloaca_crear(text, text) to authenticated;

-- Unirse con el código (o el link de invitación, que trae el mismo código).
create function public.cloaca_unirse(p_codigo text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo uuid := auth.uid();
  c public.cloacas;
  cuantos int;
begin
  if yo is null then return jsonb_build_object('ok', false, 'motivo', 'sin_sesion'); end if;
  perform pg_advisory_xact_lock(hashtext('cloaca_yo' || yo::text));
  if exists (select 1 from public.cloaca_miembros x where x.user_id = yo) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_tienes');
  end if;
  select * into c from public.cloacas x where x.codigo = upper(btrim(coalesce(p_codigo, ''))) for update;
  if c.id is null then return jsonb_build_object('ok', false, 'motivo', 'codigo'); end if;
  if exists (select 1 from public.cloaca_periodos p where p.user_id = yo and p.cloaca_id = c.id and p.expulsado
             and p.hasta > now() - interval '7 days') then
    return jsonb_build_object('ok', false, 'motivo', 'expulsado');
  end if;
  if (select count(*) from public.cloaca_periodos p where p.user_id = yo and p.semana = public.cloaca_semana_de(now())) >= 20 then
    return jsonb_build_object('ok', false, 'motivo', 'muchos_cambios');
  end if;
  select count(*) into cuantos from public.cloaca_miembros x where x.cloaca_id = c.id;
  if cuantos >= public.imperio_flag_numero('cloaca_max_miembros', 25, 2, 100) then
    return jsonb_build_object('ok', false, 'motivo', 'llena');
  end if;
  insert into public.cloaca_miembros (user_id, cloaca_id) values (yo, c.id);
  perform public.cloaca_abrir_periodo(yo, c.id);
  return jsonb_build_object('ok', true, 'id', c.id);
end;
$$;
revoke all on function public.cloaca_unirse(text) from public, anon;
grant execute on function public.cloaca_unirse(text) to authenticated;

create function public.cloaca_salir()
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo uuid := auth.uid();
begin
  if yo is null then return jsonb_build_object('ok', false, 'motivo', 'sin_sesion'); end if;
  perform pg_advisory_xact_lock(hashtext('cloaca_yo' || yo::text));
  if not exists (select 1 from public.cloaca_miembros x where x.user_id = yo) then
    return jsonb_build_object('ok', false, 'motivo', 'sin_cloaca');
  end if;
  perform public.cloaca_sacar(yo, false);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.cloaca_salir() from public, anon;
grant execute on function public.cloaca_salir() to authenticated;

-- El dueño saca a un miembro. No puede volver a esa Cloaca en 7 días.
create function public.cloaca_expulsar(p_user uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo uuid := auth.uid();
  mia uuid;
begin
  if yo is null then return jsonb_build_object('ok', false, 'motivo', 'sin_sesion'); end if;
  -- El lock del expulsado va primero: si sale y entra a otra Cloaca a la vez, la comprobación de abajo ya lo ve.
  if p_user is not null then perform pg_advisory_xact_lock(hashtext('cloaca_yo' || p_user::text)); end if;
  select c.id into mia from public.cloacas c where c.dueno = yo
     and c.id = (select x.cloaca_id from public.cloaca_miembros x where x.user_id = yo);
  if mia is null then return jsonb_build_object('ok', false, 'motivo', 'no_dueno'); end if;
  if p_user is null or p_user = yo
     or not exists (select 1 from public.cloaca_miembros x where x.user_id = p_user and x.cloaca_id = mia) then
    return jsonb_build_object('ok', false, 'motivo', 'no_miembro');
  end if;
  perform public.cloaca_sacar(p_user, true);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.cloaca_expulsar(uuid) from public, anon;
grant execute on function public.cloaca_expulsar(uuid) to authenticated;

-- Todo lo de mi Cloaca para la pantalla: datos, miembros con sus puntos de la semana, bono de hoy, cuándo cierra la
-- semana y los Rollos de la liga que faltan por cobrar. Sin Cloaca: cloaca = null (los premios pendientes igual salen).
create function public.cloaca_mia()
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  yo uuid := auth.uid();
  sem date := public.cloaca_semana_de(now());
  c public.cloacas;
  pend jsonb;
  total int;
  v_puesto int;
begin
  if yo is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'semana', p.semana, 'rollos', p.rollos - p.cobrados) order by p.creado), '[]'::jsonb)
    into pend from public.cloaca_premios p where p.user_id = yo and p.cobrados < p.rollos;
  select x.* into c from public.cloacas x join public.cloaca_miembros m on m.cloaca_id = x.id where m.user_id = yo;
  if c.id is null then
    return jsonb_build_object('cloaca', null, 'premios', pend, 'semana', sem,
      'cierra', public.cloaca_semana_inicio(sem + 7),
      'max', public.imperio_flag_numero('cloaca_max_miembros', 25, 2, 100)::int,
      'premio', public.imperio_flag_numero('cloaca_premio_rollos', 2, 0, 1000)::int,
      'bono_por', public.imperio_flag_numero('cloaca_bono_por_miembro', 0.05, 0, 1),
      'bono_tope', public.imperio_flag_numero('cloaca_bono_tope', 0.5, 0, 1));
  end if;
  with t as (
    select q.cloaca_id, sum(q.puntos)::int as puntos from public.cloaca_puntos(sem) q
    join public.cloacas y on y.id = q.cloaca_id group by 1
  ), r as (
    -- El mismo orden que cloaca_ranking y el cierre, así un empate no sale #1 aquí y #2 allá.
    select t.cloaca_id, t.puntos, row_number() over (order by t.puntos desc, y.creado, y.id) as puesto
    from t join public.cloacas y on y.id = t.cloaca_id
  )
  select coalesce((select r.puntos from r where r.cloaca_id = c.id), 0),
         (select r.puesto from r where r.cloaca_id = c.id)
    into total, v_puesto;
  return jsonb_build_object(
    'cloaca', jsonb_build_object(
      'id', c.id, 'nombre', c.nombre, 'emoji', c.emoji, 'codigo', c.codigo, 'dueno', c.dueno,
      'soy_dueno', c.dueno = yo, 'sala', 'cloaca:' || c.id::text, 'puntos', total, 'puesto', v_puesto,
      'bono', public.cloaca_bono_de(yo),
      'miembros', coalesce((
        select jsonb_agg(jsonb_build_object(
          'user_id', m.user_id, 'username', coalesce(pr.username, ''), 'avatar', pr.avatar,
          'dueno', m.user_id = c.dueno, 'unido', m.unido,
          'cagadas', coalesce(q.cagadas, 0), 'pts_cagadas', coalesce(q.pts_cagadas, 0),
          'pts_imperio', coalesce(q.pts_imperio, 0), 'puntos', coalesce(q.puntos, 0),
          'cago_hoy', exists (select 1 from public.cagadas k where k.user_id = m.user_id
                              and k.created_at >= greatest(public.imperio_inicio_dia(), m.unido)))
          order by coalesce(q.puntos, 0) desc, m.unido)
        from public.cloaca_miembros m
        left join public.profiles pr on pr.id = m.user_id
        left join public.cloaca_puntos(sem) q on q.cloaca_id = c.id and q.user_id = m.user_id
        where m.cloaca_id = c.id), '[]'::jsonb)),
    'premios', pend, 'semana', sem, 'cierra', public.cloaca_semana_inicio(sem + 7),
    'max', public.imperio_flag_numero('cloaca_max_miembros', 25, 2, 100)::int,
    'premio', public.imperio_flag_numero('cloaca_premio_rollos', 2, 0, 1000)::int,
    'bono_por', public.imperio_flag_numero('cloaca_bono_por_miembro', 0.05, 0, 1),
    'bono_tope', public.imperio_flag_numero('cloaca_bono_tope', 0.5, 0, 1));
end;
$$;
revoke all on function public.cloaca_mia() from public, anon;
grant execute on function public.cloaca_mia() to authenticated;

-- Liga de esta semana en vivo: las Cloacas por puntos (empate: la más vieja primero) y la ganadora de la semana pasada.
create function public.cloaca_ranking(p_limite int default 50)
returns jsonb
language sql stable security definer set search_path = '' as $$
  with sem as (select public.cloaca_semana_de(now()) as s),
  t as (
    select q.cloaca_id, sum(q.puntos)::int as puntos from sem, public.cloaca_puntos(sem.s) q group by 1
  ), r as (
    select c.id, c.nombre, c.emoji, c.creado, coalesce(t.puntos, 0) as puntos,
           (select count(*) from public.cloaca_miembros m where m.cloaca_id = c.id)::int as miembros,
           row_number() over (order by coalesce(t.puntos, 0) desc, c.creado, c.id) as puesto,
           c.id = (select m.cloaca_id from public.cloaca_miembros m where m.user_id = (select auth.uid())) as mia
    from public.cloacas c left join t on t.cloaca_id = c.id
  )
  select jsonb_build_object(
    'semana', (select s from sem),
    'cierra', public.cloaca_semana_inicio((select s from sem) + 7),
    'filas', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre, 'emoji', r.emoji,
                         'puntos', r.puntos, 'miembros', r.miembros, 'puesto', r.puesto, 'mia', r.mia) order by r.puesto)
                       from r where r.puesto <= least(greatest(coalesce(p_limite, 50), 1), 100) or r.mia), '[]'::jsonb),
    'anterior', (select jsonb_build_object('semana', h.semana, 'nombre', h.nombre, 'emoji', h.emoji, 'puntos', h.puntos,
                                           'miembros', h.miembros)
                 from public.cloaca_historial h where h.puesto = 1 order by h.semana desc limit 1));
$$;
revoke all on function public.cloaca_ranking(int) from public, anon;
grant execute on function public.cloaca_ranking(int) to authenticated;

-- Tope de Rollos de la casa (versión en vivo, de 20261109120000_imperio_abdicar.sql) igual, más los Rollos de la liga
-- ya cobrados: el premio sube el tope en lo mismo que da, así no le quita espacio a las jaladas (imperio_jalar) ni se
-- pierde en las lecturas (imperio_rollos_de).
CREATE OR REPLACE FUNCTION public.imperio_rollos_tope(p_fila imperio, p_margen double precision DEFAULT 0)
 RETURNS double precision
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.imperio_rollos_casa(public.imperio_mj_casa(p_fila) * (1 + p_margen)
                                    / case when coalesce(p_fila.abdicaciones, 0) > 0
                                           then public.imperio_flag_numero('abdicar_divisor_rollos', 3.5, 1, 1e12)
                                           else 1 end,
                                    p_fila.mudanzas)
         + coalesce((select sum(x.cobrados) from public.cloaca_premios x where x.user_id = p_fila.user_id), 0);
$function$;

-- Cobra los Rollos de un premio de la liga (todos los pendientes de ese premio). La app los suma a su partida y guarda
-- enseguida; el tope de la casa ya los cuenta (imperio_rollos_tope).
create function public.cloaca_premio_cobrar(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  yo uuid := auth.uid();
  p public.cloaca_premios;
begin
  if yo is null then return jsonb_build_object('ok', false, 'motivo', 'sin_sesion'); end if;
  select * into p from public.cloaca_premios x where x.id = p_id and x.user_id = yo for update;
  if p.id is null or p.cobrados >= p.rollos then return jsonb_build_object('ok', false, 'motivo', 'no_existe'); end if;
  if not exists (select 1 from public.imperio x where x.user_id = yo) then
    return jsonb_build_object('ok', false, 'motivo', 'sin_imperio');
  end if;
  update public.cloaca_premios x set cobrados = x.rollos where x.id = p.id;
  return jsonb_build_object('ok', true, 'rollos', p.rollos - p.cobrados);
end;
$$;
revoke all on function public.cloaca_premio_cobrar(uuid) from public, anon;
grant execute on function public.cloaca_premio_cobrar(uuid) to authenticated;

-- Cierre semanal (pg_cron, lunes 00:05 de Caracas). Corta los tramos de semanas viejas y abre los de esta semana para
-- todos los miembros. Después, una sola vez por semana: guarda el historial de la semana pasada y premia a la
-- Cloaca ganadora (puntos > 0). Premio para cada miembro que sigue en ella y sumó puntos esa semana con ella:
-- cloaca_premio_rollos Rollos de Oro por cobrar y el ícono 'icono_cloaca' en premios (una sola vez aunque gane más).
-- Sale una tarjeta 'cloaca' en la sala general a nombre del dueño y, si cloaca_push está prendido, un push.
create function public.cloaca_cerrar_semana()
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  hoy date := public.cloaca_semana_de(now());
  sem date := public.cloaca_semana_de(now()) - 7;
  ini timestamptz := public.cloaca_semana_inicio(public.cloaca_semana_de(now()));
  gan record;
  v_rollos int := public.imperio_flag_numero('cloaca_premio_rollos', 2, 0, 1000)::int;
  premiados int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('cloaca_cerrar'));

  update public.cloaca_periodos p
     set hasta = ini,
         mj_fin = coalesce((select least(greatest(im.mj_total, 0), 1e300) from public.imperio im where im.user_id = p.user_id), 0)
   where p.semana < hoy and p.hasta is null;
  insert into public.cloaca_periodos (cloaca_id, user_id, semana, desde, mj_inicio)
  select m.cloaca_id, m.user_id, hoy, greatest(ini, m.unido),
         coalesce((select least(greatest(im.mj_total, 0), 1e300) from public.imperio im where im.user_id = m.user_id), 0)
  from public.cloaca_miembros m
  where not exists (select 1 from public.cloaca_periodos p where p.user_id = m.user_id and p.semana = hoy and p.hasta is null);

  if exists (select 1 from public.cloaca_semanas s where s.semana = sem) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_cerrada', 'semana', sem);
  end if;

  insert into public.cloaca_historial (semana, cloaca_id, nombre, emoji, puntos, puesto, miembros)
  select sem, c.id, c.nombre, c.emoji, t.puntos,
         row_number() over (order by t.puntos desc, c.creado, c.id),
         (select count(*) from public.cloaca_miembros m where m.cloaca_id = c.id)
  from (select q.cloaca_id, sum(q.puntos)::int as puntos from public.cloaca_puntos(sem) q group by 1) t
  join public.cloacas c on c.id = t.cloaca_id
  where t.puntos > 0;

  select h.*, c.dueno into gan from public.cloaca_historial h join public.cloacas c on c.id = h.cloaca_id
   where h.semana = sem and h.puesto = 1;

  if gan.cloaca_id is not null then
    with quienes as (
      select m.user_id from public.cloaca_miembros m
      join public.cloaca_puntos(sem) q on q.cloaca_id = m.cloaca_id and q.user_id = m.user_id
      where m.cloaca_id = gan.cloaca_id and q.puntos > 0
    ), ro as (
      insert into public.cloaca_premios (user_id, semana, cloaca_id, rollos)
      select quienes.user_id, sem, gan.cloaca_id, v_rollos from quienes where v_rollos > 0
      on conflict (user_id, semana) do nothing
      returning 1
    ), ic as (
      insert into public.premios (user_id, ranura, emoji, motivo)
      select quienes.user_id, 'icono', 'icono_cloaca', 'cloaca_liga' from quienes
      on conflict do nothing
      returning 1
    )
    select count(*) into premiados from quienes;

    perform public.imperio_tarjeta_chat(gan.dueno, jsonb_build_object('tipo', 'cloaca', 'semana', sem, 'cloaca_id', gan.cloaca_id));

    if public.imperio_regalos_si('cloaca_push') then
      begin
        perform net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
          headers := jsonb_build_object('Content-Type', 'application/json',
            'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')),
          body := jsonb_build_object('tipo', 'cloaca', 'semana', sem));
      exception when others then null;
      end;
    end if;
  end if;

  insert into public.cloaca_semanas (semana, ganadora) values (sem, gan.cloaca_id);
  return jsonb_build_object('ok', true, 'semana', sem, 'ganadora', gan.cloaca_id, 'premiados', premiados);
end;
$$;
revoke all on function public.cloaca_cerrar_semana() from public, anon, authenticated;

select cron.schedule('cloaca_semana', '5 4 * * 1', $$select public.cloaca_cerrar_semana()$$);

-- Chat de la Cloaca: sala 'cloaca:<id>'. Solo sus miembros la leen y escriben (y los admins la leen para moderar).
alter table public.mensajes drop constraint mensajes_sala_check;
alter table public.mensajes add constraint mensajes_sala_check check (
  sala = any (array['global', 'es', 'en', 'soporte'])
  or sala ~ '^cloaca:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

drop policy mensajes_select on public.mensajes;
create policy mensajes_select on public.mensajes for select using (
  (public.sala_publica(sala) and not public.hay_bloqueo(user_id)
   and ((not oculto) or user_id = (select auth.uid()) or public.es_admin()))
  or (sala = 'soporte' and (hilo = (select auth.uid()) or public.es_admin()))
  or (sala like 'cloaca:%' and ((public.cloaca_es_mia(sala) and not public.hay_bloqueo(user_id)
                                 and ((not oculto) or user_id = (select auth.uid())))
                                or public.es_admin())));

drop policy mensajes_insert on public.mensajes;
create policy mensajes_insert on public.mensajes for insert with check (
  user_id = (select auth.uid())
  and (public.sala_publica(sala) or hilo = (select auth.uid()) or public.es_admin() or public.cloaca_es_mia(sala)));

-- validar_mensaje (versión en vivo, última en 20261109120000_imperio_abdicar.sql) igual, más: las salas de Cloaca
-- ('cloaca:<id>') también apagan es_bug y bloquean teléfonos y correos, y la tarjeta 'cloaca' (ganadora de la liga).
CREATE OR REPLACE FUNCTION public.validar_mensaje()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if public.sala_publica(new.sala) or new.sala like 'cloaca:%' then new.es_bug := false; end if;
  if new.texto = '' and new.tarjeta is null then
    raise exception 'Mensaje vacío' using errcode = 'P0001';
  end if;
  malo := public.link_peligroso(new.texto);
  if malo is not null then
    raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
  end if;
  if (public.sala_publica(new.sala) or new.sala like 'cloaca:%') and (new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') then
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
      if rollos > 1e12 or rollos > public.imperio_rollos_tope(im) then
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
        'rollos', least(public.imperio_numero(im.estado ->> 'rollos'),
                        public.imperio_rollos_tope(im)));
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
      new.tarjeta := jsonb_build_object('tipo', 'bano', 'mudanzas', greatest(im.mudanzas, 0),
        'abdicaciones', greatest(coalesce(im.abdicaciones, 0), 0),
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
    elsif t = 'cloaca' then
      -- Ganadora de la liga semanal: solo la pone cloaca_cerrar_semana (servidor) en la sala general. Los datos salen
      -- del historial de esa semana, no de lo que venga en la tarjeta.
      if coalesce(current_setting('imperio.tarjeta_servidor', true), '') <> '1'
         or coalesce(new.tarjeta ->> 'cloaca_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or coalesce(new.tarjeta ->> 'semana', '') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'Esa tarjeta la pone el servidor' using errcode = 'P0001';
      end if;
      select h.* into d from public.cloaca_historial h
       where h.semana = (new.tarjeta ->> 'semana')::date and h.cloaca_id = (new.tarjeta ->> 'cloaca_id')::uuid
         and h.puesto = 1;
      if d.cloaca_id is null then
        raise exception 'Esa Cloaca no ganó esa semana' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'cloaca', 'semana', d.semana, 'cloaca_id', d.cloaca_id,
        'nombre', d.nombre, 'emoji', d.emoji, 'puntos', d.puntos, 'miembros', d.miembros,
        'rollos', public.imperio_flag_numero('cloaca_premio_rollos', 2, 0, 1000)::int);
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;




-- Reportes: solo de mensajes que puedes ver. Sin esto, alguien de fuera podía reportar (y con 3 reportes ocultar)
-- mensajes de una Cloaca adivinando ids. La consulta de adentro pasa por la RLS de mensajes.
drop policy if exists mensaje_reportes_insert on public.mensaje_reportes;
create policy mensaje_reportes_insert on public.mensaje_reportes for insert to authenticated
  with check (reportador = (select auth.uid()) and exists (select 1 from public.mensajes m where m.id = mensaje_reportes.mensaje_id));

commit;

notify pgrst, 'reload schema';
