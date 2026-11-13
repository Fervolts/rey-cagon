-- Muro del baño: publicaciones de texto y/o dibujo (lib/muro.dart). No se suben fotos: el dibujo es
-- una lista de trazos en jsonb que el trigger valida al detalle, así que solo puede ser un dibujo.
-- Formato (igual que lib/muro_dibujo.dart):
--   {"v":1,"fondo":0..15,"trazos":[{"c":0..15,"g":1..4,"p":[x,y,x,y,...]}]}
--   coordenadas enteras 0..1000, cada trazo 2..4000 números (pares), hasta 400 trazos y 30000 números.

create table public.muro (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  texto text check (char_length(texto) <= 500),
  dibujo jsonb,
  created_at timestamptz not null default now(),
  oculto boolean not null default false,
  check (texto is not null or dibujo is not null)
);
create index on public.muro (created_at desc);
create index on public.muro (user_id, created_at desc);
alter table public.muro enable row level security;

create policy muro_select on public.muro for select to authenticated using (
  not public.hay_bloqueo(user_id)
  and (not oculto or user_id = (select auth.uid()) or public.es_admin())
);
create policy muro_insert on public.muro for insert to authenticated with check (user_id = (select auth.uid()));
create policy muro_delete on public.muro for delete to authenticated using (user_id = (select auth.uid()) or public.es_admin());
-- Ocultar o mostrar: solo admins.
create policy muro_update on public.muro for update to authenticated using (public.es_admin()) with check (public.es_admin());
revoke update on public.muro from authenticated;
grant update (oculto) on public.muro to authenticated;

-- El dibujo con el formato exacto o nada. Devuelve el motivo del rechazo (null = válido).
create function public.dibujo_invalido(d jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  t jsonb;
  n int;
  total int := 0;
begin
  if jsonb_typeof(d) <> 'object' then return 'no es un objeto'; end if;
  if (select array_agg(k order by k) from jsonb_object_keys(d) k) <> array['fondo', 'trazos', 'v'] then
    return 'claves de más o de menos';
  end if;
  if d -> 'v' <> '1'::jsonb then return 'versión desconocida'; end if;
  if jsonb_typeof(d -> 'fondo') <> 'number' or (d ->> 'fondo') !~ '^\d{1,2}$' or (d ->> 'fondo')::int > 15 then
    return 'fondo fuera de rango';
  end if;
  if jsonb_typeof(d -> 'trazos') <> 'array' then return 'trazos no es una lista'; end if;
  n := jsonb_array_length(d -> 'trazos');
  if n < 1 or n > 400 then return 'entre 1 y 400 trazos'; end if;
  for t in select x from jsonb_array_elements(d -> 'trazos') x loop
    if jsonb_typeof(t) <> 'object' then return 'trazo que no es objeto'; end if;
    if (select array_agg(k order by k) from jsonb_object_keys(t) k) <> array['c', 'g', 'p'] then
      return 'trazo con claves de más o de menos';
    end if;
    if jsonb_typeof(t -> 'c') <> 'number' or (t ->> 'c') !~ '^\d{1,2}$' or (t ->> 'c')::int > 15 then
      return 'color fuera de rango';
    end if;
    if jsonb_typeof(t -> 'g') <> 'number' or (t ->> 'g') !~ '^[1-4]$' then return 'grosor fuera de rango'; end if;
    if jsonb_typeof(t -> 'p') <> 'array' then return 'puntos no es una lista'; end if;
    n := jsonb_array_length(t -> 'p');
    if n < 2 or n > 4000 or n % 2 <> 0 then return 'trazo con número de puntos inválido'; end if;
    total := total + n;
    if total > 30000 then return 'demasiados puntos'; end if;
    if exists (select 1 from jsonb_array_elements(t -> 'p') e
               where jsonb_typeof(e) <> 'number' or e::text !~ '^\d{1,4}$' or e::text::int > 1000) then
      return 'coordenada fuera de rango';
    end if;
  end loop;
  return null;
end;
$$;

create function public.validar_muro()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  malo text;
begin
  if new.user_id is distinct from auth.uid() then
    raise exception 'Solo puedes publicar a tu nombre' using errcode = 'P0001';
  end if;
  new.oculto := false;
  new.created_at := now();
  new.texto := nullif(btrim(new.texto), '');
  if new.texto is null and new.dibujo is null then
    raise exception 'Publicación vacía' using errcode = 'P0001';
  end if;
  if new.texto is not null then
    if char_length(new.texto) > 500 then raise exception 'Texto muy largo' using errcode = 'P0001'; end if;
    malo := public.link_peligroso(new.texto);
    if malo is not null then
      raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
    end if;
    if new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
      raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
    end if;
  end if;
  if new.dibujo is not null then
    malo := public.dibujo_invalido(new.dibujo);
    if malo is not null then
      raise exception 'Dibujo inválido: %', malo using errcode = 'P0001';
    end if;
  end if;
  -- Dos publicaciones a la vez no se saltan el tope.
  perform pg_advisory_xact_lock(hashtext('muro:' || new.user_id::text));
  if (select count(*) from public.muro m where m.user_id = new.user_id and m.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Ya publicaste mucho esta hora. Espera un rato.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.validar_muro() from public, anon, authenticated;
create trigger muro_validar before insert on public.muro for each row execute function public.validar_muro();

-- Likes (💩 en la app). Solo se ven los propios; los conteos salen de muro_feed.
create table public.muro_likes (
  post_id bigint not null references public.muro (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index on public.muro_likes (user_id);
alter table public.muro_likes enable row level security;
create policy muro_likes_select on public.muro_likes for select to authenticated using (user_id = (select auth.uid()));
-- El exists pasa por el RLS de muro: no se le da like a lo oculto ni a quien te bloqueó.
create policy muro_likes_insert on public.muro_likes for insert to authenticated with check (
  user_id = (select auth.uid()) and exists (select 1 from public.muro m where m.id = post_id)
);
create policy muro_likes_delete on public.muro_likes for delete to authenticated using (user_id = (select auth.uid()));

create table public.muro_comentarios (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.muro (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 300),
  created_at timestamptz not null default now()
);
create index on public.muro_comentarios (post_id, created_at);
create index on public.muro_comentarios (user_id, created_at desc);
alter table public.muro_comentarios enable row level security;
create policy muro_comentarios_select on public.muro_comentarios for select to authenticated using (
  not public.hay_bloqueo(user_id) and exists (select 1 from public.muro m where m.id = post_id)
);
create policy muro_comentarios_insert on public.muro_comentarios for insert to authenticated with check (
  user_id = (select auth.uid()) and exists (select 1 from public.muro m where m.id = post_id)
);
-- Borra el autor del comentario, el dueño de la publicación o un admin.
create policy muro_comentarios_delete on public.muro_comentarios for delete to authenticated using (
  user_id = (select auth.uid()) or public.es_admin()
  or exists (select 1 from public.muro m where m.id = post_id and m.user_id = (select auth.uid()))
);

create function public.validar_muro_comentario()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  malo text;
begin
  if new.user_id is distinct from auth.uid() then
    raise exception 'Solo puedes comentar a tu nombre' using errcode = 'P0001';
  end if;
  new.created_at := now();
  new.texto := btrim(new.texto);
  if new.texto = '' then raise exception 'Comentario vacío' using errcode = 'P0001'; end if;
  malo := public.link_peligroso(new.texto);
  if malo is not null then
    raise exception 'Link bloqueado: no se permiten %', malo using errcode = 'P0001';
  end if;
  if new.texto ~ '\+?\d[\d\s().-]{8,}\d' or new.texto ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
    raise exception 'No compartas teléfonos ni correos en el chat' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('muro_com:' || new.user_id::text));
  if (select count(*) from public.muro_comentarios c where c.user_id = new.user_id and c.created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Ya comentaste mucho esta hora. Espera un rato.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke execute on function public.validar_muro_comentario() from public, anon, authenticated;
create trigger muro_comentarios_validar before insert on public.muro_comentarios
  for each row execute function public.validar_muro_comentario();

-- Reportes: como mensaje_reportes, con 3 la publicación se oculta hasta que un admin la revise.
create table public.muro_reportes (
  post_id bigint not null references public.muro (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.muro_reportes enable row level security;
create policy muro_reportes_insert on public.muro_reportes for insert to authenticated with check (
  user_id = (select auth.uid()) and exists (select 1 from public.muro m where m.id = post_id)
);
create policy muro_reportes_select on public.muro_reportes for select to authenticated using (
  user_id = (select auth.uid()) or public.es_admin()
);

create function public.contar_reportes_muro()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.muro_reportes r where r.post_id = new.post_id) >= 3 then
    update public.muro set oculto = true where id = new.post_id and not oculto;
  end if;
  return new;
end;
$$;
revoke execute on function public.contar_reportes_muro() from public, anon, authenticated;
create trigger muro_reportes_contar after insert on public.muro_reportes
  for each row execute function public.contar_reportes_muro();

-- Feed: lo más nuevo primero, paginado con p_antes (created_at del último que ya tienes).
-- p_amigos: solo a quien sigues y lo tuyo. Mismas reglas que el RLS (oculto, bloqueos).
create function public.muro_feed(p_antes timestamptz default null, p_amigos boolean default false, p_limite int default 20)
returns table (
  id bigint, user_id uuid, texto text, dibujo jsonb, created_at timestamptz,
  likes bigint, yo_like boolean, comentarios bigint,
  username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer,
  lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.user_id, m.texto, m.dibujo, m.created_at,
         (select count(*) from public.muro_likes l where l.post_id = m.id),
         exists (select 1 from public.muro_likes l where l.post_id = m.id and l.user_id = (select auth.uid())),
         (select count(*) from public.muro_comentarios c where c.post_id = m.id and not public.hay_bloqueo(c.user_id)),
         p.username, p.avatar, p.sombrero, p.lentes, p.mascota, p.cagadas,
         p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala
  from public.muro m
  join public.profiles p on p.id = m.user_id
  where (select auth.uid()) is not null
    and (p_antes is null or m.created_at < p_antes)
    and (not m.oculto or m.user_id = (select auth.uid()) or public.es_admin())
    and not public.hay_bloqueo(m.user_id)
    and (not p_amigos
         or m.user_id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = m.user_id))
  order by m.created_at desc, m.id desc
  limit least(greatest(coalesce(p_limite, 20), 1), 50);
$$;
revoke execute on function public.muro_feed(timestamptz, boolean, int) from public, anon;
grant execute on function public.muro_feed(timestamptz, boolean, int) to authenticated;

-- Los comentarios de una publicación se leen con un select normal (RLS de arriba):
--   muro_comentarios?select=id,user_id,texto,created_at,profiles(...)&post_id=eq.N&order=created_at
