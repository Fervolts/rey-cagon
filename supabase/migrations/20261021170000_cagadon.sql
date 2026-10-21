-- El Cagadón: reto 1 vs 1 entre amigos. Gana el que cague más ese día (hora de Venezuela).
-- Empate: gana el que llegó primero a ese número. Se cierra solo a las 00:05.

create table public.retos (
  id bigint generated always as identity primary key,
  retador uuid not null references public.profiles (id) on delete cascade,
  retado uuid not null references public.profiles (id) on delete cascade,
  dia date not null default (now() at time zone 'America/Caracas')::date,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aceptado', 'rechazado', 'cancelado', 'terminado')),
  ganador uuid references public.profiles (id) on delete set null,
  marcador_retador int,
  marcador_retado int,
  created_at timestamptz not null default now(),
  check (retador <> retado)
);
create index on public.retos (retador, dia);
create index on public.retos (retado, dia);
-- Un solo reto vivo por pareja y día, sin importar quién retó a quién.
create unique index retos_uno_por_dia on public.retos (least(retador, retado), greatest(retador, retado), dia)
  where estado in ('pendiente', 'aceptado', 'terminado');
alter table public.retos enable row level security;

create policy retos_select on public.retos for select to authenticated
  using (retador = (select auth.uid()) or retado = (select auth.uid()));
create policy retos_insert on public.retos for insert to authenticated
  with check (retador = (select auth.uid()));
-- Aceptar, rechazar o cancelar va por responder_reto().

create function public.validar_reto()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.retador := auth.uid();
  new.dia := (now() at time zone 'America/Caracas')::date;
  new.estado := 'pendiente';
  new.ganador := null;
  if not exists (select 1 from public.follows f where f.follower = new.retador and f.followed = new.retado) then
    raise exception 'Solo puedes retar a gente que sigues' using errcode = 'P0001';
  end if;
  if public.hay_bloqueo(new.retado) then
    raise exception 'No puedes retar a esa persona' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.retos r
             where least(r.retador, r.retado) = least(new.retador, new.retado)
               and greatest(r.retador, r.retado) = greatest(new.retador, new.retado)
               and r.dia = new.dia and r.estado in ('pendiente', 'aceptado', 'terminado')) then
    raise exception 'Ya tienen un Cagadón hoy' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger retos_validar before insert on public.retos
  for each row execute function public.validar_reto();

-- Cuántas lleva cada uno ese día y a qué hora llegó a su número (para el desempate).
create function public.marcador_reto(rid bigint)
returns table (retador uuid, retado uuid, dia date, estado text, ganador uuid,
               a int, b int, a_llego timestamptz, b_llego timestamptz)
language sql stable security definer set search_path = '' as $$
  with r as (select * from public.retos where id = rid),
  rango as (select (r.dia::timestamp at time zone 'America/Caracas') as desde,
                   ((r.dia + 1)::timestamp at time zone 'America/Caracas') as hasta from r),
  ca as (select c.created_at from public.cagadas c, r, rango
         where c.user_id = r.retador and c.created_at >= rango.desde and c.created_at < rango.hasta),
  cb as (select c.created_at from public.cagadas c, r, rango
         where c.user_id = r.retado and c.created_at >= rango.desde and c.created_at < rango.hasta)
  select r.retador, r.retado, r.dia, r.estado, r.ganador,
         coalesce(r.marcador_retador, (select count(*) from ca)::int),
         coalesce(r.marcador_retado, (select count(*) from cb)::int),
         (select max(created_at) from ca), (select max(created_at) from cb)
  from r;
$$;

create function public.avisar_reto(rid bigint, evento text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'reto', 'id', rid, 'evento', evento)
  );
end;
$$;

create function public.avisar_reto_nuevo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.avisar_reto(new.id, 'nuevo');
  return new;
end;
$$;
create trigger retos_avisar after insert on public.retos
  for each row execute function public.avisar_reto_nuevo();

-- El retado acepta o rechaza; el retador puede cancelar mientras esté pendiente.
-- Al aceptar sale la tarjeta en el chat global con el marcador en vivo.
create function public.responder_reto(rid bigint, accion text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.retos;
  yo uuid := auth.uid();
begin
  select * into r from public.retos where id = rid for update;
  if r is null or r.estado <> 'pendiente' then
    raise exception 'Ese reto ya no está pendiente' using errcode = 'P0001';
  end if;
  if r.dia <> (now() at time zone 'America/Caracas')::date then
    update public.retos set estado = 'cancelado' where id = rid;
    raise exception 'Ese reto era de otro día' using errcode = 'P0001';
  end if;
  if accion = 'cancelar' and yo = r.retador then
    update public.retos set estado = 'cancelado' where id = rid;
  elsif accion = 'rechazar' and yo = r.retado then
    update public.retos set estado = 'rechazado' where id = rid;
    perform public.avisar_reto(rid, 'rechazado');
  elsif accion = 'aceptar' and yo = r.retado then
    update public.retos set estado = 'aceptado' where id = rid;
    insert into public.mensajes (sala, user_id, tarjeta) values ('global', yo, jsonb_build_object('tipo', 'reto', 'id', rid));
    perform public.avisar_reto(rid, 'aceptado');
  else
    raise exception 'No puedes hacer eso' using errcode = '42501';
  end if;
end;
$$;

-- Cierre del día: congela el marcador, decide ganador, publica el resultado y avisa.
create function public.cerrar_retos()
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
  m record;
  g uuid;
begin
  update public.retos set estado = 'cancelado'
    where estado = 'pendiente' and dia < (now() at time zone 'America/Caracas')::date;
  for r in select * from public.retos
           where estado = 'aceptado' and dia < (now() at time zone 'America/Caracas')::date loop
    select * into m from public.marcador_reto(r.id);
    g := case
      when m.a > m.b then r.retador
      when m.b > m.a then r.retado
      when m.a = 0 then null
      when m.a_llego <= m.b_llego then r.retador
      else r.retado end;
    update public.retos set estado = 'terminado', ganador = g, marcador_retador = m.a, marcador_retado = m.b
      where id = r.id;
    insert into public.mensajes (sala, user_id, tarjeta)
      values ('global', coalesce(g, r.retador), jsonb_build_object('tipo', 'reto_fin', 'id', r.id));
    perform public.avisar_reto(r.id, 'fin');
  end loop;
end;
$$;

-- Victorias de alguien, para su perfil.
create function public.victorias(uid uuid)
returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.retos where ganador = uid and estado = 'terminado';
$$;

-- Las tarjetas de reto las publica el servidor; el chat solo acepta las de retos tuyos.
create or replace function public.validar_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  total bigint;
  malo text;
  t text;
  c record;
  d record;
begin
  -- auth.uid() es null cuando escribe el servidor (cierre de retos): se respeta el user_id.
  new.user_id := coalesce(auth.uid(), new.user_id);
  new.oculto := false;
  new.created_at := now();
  new.texto := btrim(new.texto);
  if new.sala = 'global' then new.es_bug := false; end if;
  if new.texto = '' and new.tarjeta is null then
    raise exception 'Mensaje vacío' using errcode = 'P0001';
  end if;
  malo := public.link_peligroso(new.texto);
  if malo is not null then
    raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
  end if;
  if new.sala = 'global' and (new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') then
    raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
  end if;

  if new.tarjeta is not null then
    t := new.tarjeta ->> 'tipo';
    select count(*) into total from public.cagadas where user_id = new.user_id;
    if t = 'hito' then
      if not ((new.tarjeta ->> 'n')::int = any (public.hitos())) or (new.tarjeta ->> 'n')::int > total then
        raise exception 'Todavía no llegas a ese número' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'hito', 'n', (new.tarjeta ->> 'n')::int);
    elsif t = 'desbloqueo' then
      select * into d from public.desbloqueos x where x.emoji = new.tarjeta ->> 'emoji' limit 1;
      if d is null or d.minimo > total then
        raise exception 'Todavía no has desbloqueado eso' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'desbloqueo', 'emoji', d.emoji, 'ranura', d.ranura, 'minimo', d.minimo);
    elsif t = 'cagada' then
      select x.id, x.tipo, x.created_at into c from public.cagadas x
        where x.id = (new.tarjeta ->> 'id')::bigint and x.user_id = new.user_id;
      if c is null or c.tipo is null then
        raise exception 'Esa cagada no existe o no dijiste qué salió' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', 'cagada', 'mojon', c.tipo,
        'n', (select count(*) from public.cagadas x where x.user_id = new.user_id and x.created_at <= c.created_at));
    elsif t in ('reto', 'reto_fin') then
      if not exists (select 1 from public.retos r where r.id = (new.tarjeta ->> 'id')::bigint
                     and new.user_id in (r.retador, r.retado)
                     and r.estado = case t when 'reto' then 'aceptado' else 'terminado' end) then
        raise exception 'Ese reto no es tuyo' using errcode = 'P0001';
      end if;
      new.tarjeta := jsonb_build_object('tipo', t, 'id', (new.tarjeta ->> 'id')::bigint);
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- Ver el marcador de un reto que salió en el chat, aunque no seas parte de él.
create function public.reto_publico(rid bigint)
returns table (retador uuid, retado uuid, dia date, estado text, ganador uuid, a int, b int)
language sql stable security definer set search_path = '' as $$
  select m.retador, m.retado, m.dia, m.estado, m.ganador, m.a, m.b from public.marcador_reto(rid) m
  where m.estado in ('aceptado', 'terminado');
$$;
revoke execute on function public.marcador_reto(bigint) from public, anon, authenticated;

alter publication supabase_realtime add table public.retos;

create extension if not exists pg_cron;
select cron.schedule('cerrar_retos', '5 4 * * *', 'select public.cerrar_retos()');
