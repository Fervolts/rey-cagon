-- Chat: sala global (en la app con un nombre al azar: El Trono, La Poceta, El Váter…) y soporte (un hilo por usuario con los admins).
-- Solo texto y tarjetas para presumir; sin imágenes. Los links pasan por un filtro.

create table public.admins (
  user_id uuid primary key references public.profiles (id) on delete cascade
);
alter table public.admins enable row level security;
-- Sin políticas: solo se consulta con es_admin().

create function public.es_admin(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins a where a.user_id = uid);
$$;

create table public.mensajes (
  id bigint generated always as identity primary key,
  sala text not null check (sala in ('global', 'soporte')),
  -- Soporte: el usuario dueño del hilo (los admins le responden en el mismo hilo).
  hilo uuid references public.profiles (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  texto text not null default '' check (char_length(texto) <= 1000),
  tarjeta jsonb,
  es_bug boolean not null default false,
  oculto boolean not null default false,
  created_at timestamptz not null default now(),
  check ((sala = 'soporte') = (hilo is not null))
);
create index on public.mensajes (sala, created_at desc);
create index on public.mensajes (hilo, created_at desc);
alter table public.mensajes enable row level security;

create policy mensajes_select on public.mensajes for select to authenticated using (
  (sala = 'global' and not public.hay_bloqueo(user_id)
     and (not oculto or user_id = (select auth.uid()) or public.es_admin()))
  or (sala = 'soporte' and (hilo = (select auth.uid()) or public.es_admin()))
);
create policy mensajes_insert on public.mensajes for insert to authenticated with check (
  user_id = (select auth.uid())
  and (sala = 'global' or hilo = (select auth.uid()) or public.es_admin())
);
create policy mensajes_delete on public.mensajes for delete to authenticated using (
  user_id = (select auth.uid()) or public.es_admin()
);
-- Ocultar o mostrar un mensaje: solo admins.
create policy mensajes_update on public.mensajes for update to authenticated
  using (public.es_admin()) with check (public.es_admin());
revoke update on public.mensajes from authenticated;
grant update (oculto) on public.mensajes to authenticated;

create table public.mensaje_reportes (
  mensaje_id bigint not null references public.mensajes (id) on delete cascade,
  reportador uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  motivo text not null check (char_length(motivo) <= 200),
  created_at timestamptz not null default now(),
  primary key (mensaje_id, reportador)
);
alter table public.mensaje_reportes enable row level security;
create policy mensaje_reportes_insert on public.mensaje_reportes for insert to authenticated
  with check (reportador = (select auth.uid()));
create policy mensaje_reportes_select on public.mensaje_reportes for select to authenticated
  using (reportador = (select auth.uid()) or public.es_admin());

-- Links: solo http(s) a dominios normales. Se bloquea lo que suele ser estafa o malware:
-- IPs, punycode, usuario@host, acortadores, TLDs de spam y archivos ejecutables.
create function public.link_peligroso(texto text)
returns text language plpgsql immutable set search_path = '' as $$
declare
  m text[];
  url text;
  host text;
begin
  if texto ~* '(javascript|data|intent|file|vbscript):' then return 'ese tipo de link'; end if;
  for m in select regexp_matches(texto, '((https?://|www\.)[^\s<>"]+)', 'gi') loop
    url := lower(m[1]);
    host := regexp_replace(url, '^(https?://)?', '');
    if host ~ '^[^/?#]*@' then return 'links con usuario@'; end if;
    host := regexp_replace(host, '[/?#:].*$', '');
    if host ~ '^\d{1,3}(\.\d{1,3}){3}$' or host ~ '^\[' then return 'links a una IP'; end if;
    if host ~ '(^|\.)xn--' then return 'dominios con letras raras'; end if;
    if host ~ '^(www\.)?(bit\.ly|tinyurl\.com|t\.co|goo\.gl|is\.gd|cutt\.ly|rb\.gy|ow\.ly|shorturl\.at|tiny\.cc|t\.ly|s\.id|v\.gd|buff\.ly|rebrand\.ly|bitly\.com|lnkd\.in|tr\.ee|qr\.ae)$' then
      return 'acortadores de links';
    end if;
    if host ~ '\.(zip|mov|top|click|tk|ml|ga|cf|gq|xyz|work|country|loan|rest|cam|icu|sbs|cfd|monster|quest|lol)$' then
      return 'ese dominio';
    end if;
    if url ~ '\.(apk|exe|bat|cmd|scr|msi|jar|vbs|ps1|dmg|pkg|xapk|apks)([?#]|$)' then
      return 'links a archivos que se instalan';
    end if;
  end loop;
  return null;
end;
$$;

-- Hitos que se pueden presumir.
create function public.hitos() returns int[] language sql immutable as $$
  select array[10, 30, 50, 100, 200, 300, 500, 1000];
$$;

create function public.validar_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  total bigint;
  malo text;
  t text;
  c record;
  d record;
begin
  new.user_id := auth.uid();
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
  -- En la sala global, nada de teléfonos ni correos.
  if new.sala = 'global' and (new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}') then
    raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
  end if;

  -- Las tarjetas las arma el servidor con datos reales: no se puede presumir lo que no tienes.
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
    else
      raise exception 'Tarjeta desconocida' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger mensajes_validar before insert on public.mensajes
  for each row execute function public.validar_mensaje();

-- Con 3 reportes el mensaje se oculta solo hasta que un admin lo revise.
create function public.contar_reportes_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.mensaje_reportes r where r.mensaje_id = new.mensaje_id) >= 3 then
    update public.mensajes set oculto = true where id = new.mensaje_id and not oculto;
  end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'reporte_chat', 'mensaje_id', new.mensaje_id, 'motivo', new.motivo)
  );
  return new;
end;
$$;
create trigger mensaje_reportes_contar after insert on public.mensaje_reportes
  for each row execute function public.contar_reportes_mensaje();

-- Soporte: aviso push al otro lado del hilo.
create function public.avisar_soporte()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.sala <> 'soporte' then return new; end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'soporte', 'id', new.id)
  );
  return new;
end;
$$;
create trigger mensajes_avisar_soporte after insert on public.mensajes
  for each row execute function public.avisar_soporte();

-- Bandeja de soporte para admins: último mensaje de cada hilo.
create function public.hilos_soporte()
returns table (hilo uuid, username text, avatar text, texto text, es_bug boolean, created_at timestamptz, del_usuario boolean)
language sql stable security definer set search_path = '' as $$
  select distinct on (m.hilo) m.hilo, p.username, p.avatar, m.texto, m.es_bug, m.created_at, m.user_id = m.hilo
  from public.mensajes m join public.profiles p on p.id = m.hilo
  where m.sala = 'soporte' and public.es_admin()
  order by m.hilo, m.created_at desc;
$$;

alter publication supabase_realtime add table public.mensajes;

-- Quién es admin, para marcar sus mensajes con la etiqueta ADMIN.
create function public.admins_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select user_id from public.admins;
$$;
