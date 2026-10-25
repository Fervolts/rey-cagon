-- Género (se cambia una vez al año), peso del mojón y rachas del día en el chat general.

-- Género. La primera elección es libre; cada cambio después de esa cuenta y bloquea un año.
alter table public.profiles
  add column if not exists genero text check (genero in ('hombre', 'mujer', 'otro')),
  add column if not exists genero_cambiado timestamptz;
grant update (genero) on public.profiles to authenticated;

create or replace function public.validar_genero()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.genero is not distinct from old.genero or old.genero is null then
    return new;
  end if;
  -- Borrarlo para elegir de nuevo "gratis" sería saltarse el año.
  if new.genero is null then
    raise exception 'No puedes quitar el género, solo cambiarlo' using errcode = 'P0001';
  end if;
  if old.genero_cambiado is not null and old.genero_cambiado > now() - interval '1 year' then
    raise exception 'Solo puedes cambiar el género una vez al año. Próximo cambio: %',
      to_char((old.genero_cambiado + interval '1 year') at time zone 'America/Caracas', 'DD/MM/YYYY')
      using errcode = 'P0001', hint = 'genero_anual';
  end if;
  new.genero_cambiado := now();
  return new;
end;
$$;

drop trigger if exists validar_genero on public.profiles;
create trigger validar_genero before update of genero on public.profiles
  for each row execute function public.validar_genero();

-- Peso del mojón: 1 pluma … 5 ballena. De chiste, como el tipo.
alter table public.cagadas add column if not exists peso smallint check (peso between 1 and 5);
grant update (peso) on public.cagadas to authenticated;

-- Racha: desde la segunda cagada del día (hora de Caracas) sale una tarjeta en el chat general.
create or replace function public.racha_del_dia(c public.cagadas)
returns int
language sql
stable
set search_path = ''
as $$
  select count(*)::int from public.cagadas x
  where x.user_id = c.user_id
    and x.created_at >= date_trunc('day', c.created_at at time zone 'America/Caracas') at time zone 'America/Caracas'
    and x.created_at <= c.created_at;
$$;

create or replace function public.anunciar_racha()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- Deshacer la cagada se lleva su tarjeta.
    delete from public.mensajes where tarjeta ->> 'tipo' = 'racha' and (tarjeta ->> 'id')::bigint = old.id;
    return null;
  end if;
  if public.racha_del_dia(new) >= 2 then
    begin
      insert into public.mensajes (sala, user_id, tarjeta)
      values ('global', new.user_id, jsonb_build_object('tipo', 'racha', 'id', new.id));
    exception when others then
      -- Que el chat falle no puede tumbar la cagada.
      null;
    end;
  end if;
  return null;
end;
$$;

drop trigger if exists cagadas_racha on public.cagadas;
create trigger cagadas_racha after insert or delete on public.cagadas
  for each row execute function public.anunciar_racha();

-- validar_mensaje: tarjeta 'racha' y el peso en la tarjeta de cagada.
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
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- "Calma, rey" o "Calma, reina" según el género.
create or replace function public.limitar_cagadas()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ultima timestamptz;
begin
  new.created_at := now();
  -- Serializa inserts simultáneos del mismo usuario para que dos taps rápidos no pasen los dos.
  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  select max(created_at) into ultima from public.cagadas where user_id = new.user_id;
  if ultima is not null and ultima > now() - interval '1 hour' then
    raise exception 'Calma, %: solo una por hora. Espera % min más.',
      case when (select genero from public.profiles where id = new.user_id) = 'mujer' then 'reina' else 'rey' end,
      ceil(extract(epoch from (ultima + interval '1 hour' - now())) / 60)::int
      using errcode = 'P0001', hint = 'limite_hora';
  end if;
  return new;
end;
$$;
