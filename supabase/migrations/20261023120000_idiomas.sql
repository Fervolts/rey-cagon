-- Salas por idioma: además de la general ('global') hay una en español ('es') y otra en inglés ('en').
-- Las tres son públicas y siguen las mismas reglas; los retos se siguen anunciando en la general.
-- Y el idioma de cada teléfono, para mandarle los avisos en su idioma.

create function public.sala_publica(s text)
returns boolean language sql immutable set search_path = '' as $$
  select s in ('global', 'es', 'en')
$$;

alter table public.mensajes drop constraint mensajes_sala_check;
alter table public.mensajes add constraint mensajes_sala_check check (sala in ('global', 'es', 'en', 'soporte'));
alter table public.mensajes drop constraint mensajes_fijado_solo_global;
alter table public.mensajes add constraint mensajes_fijado_solo_global
  check (fijado_hasta is null or public.sala_publica(sala));

drop policy mensajes_select on public.mensajes;
create policy mensajes_select on public.mensajes for select to authenticated using (
  (public.sala_publica(sala) and not public.hay_bloqueo(user_id)
    and (not oculto or user_id = (select auth.uid()) or public.es_admin()))
  or (sala = 'soporte' and (hilo = (select auth.uid()) or public.es_admin())));
drop policy mensajes_insert on public.mensajes;
create policy mensajes_insert on public.mensajes for insert to authenticated with check (
  user_id = (select auth.uid())
  and (public.sala_publica(sala) or hilo = (select auth.uid()) or public.es_admin()));

CREATE OR REPLACE FUNCTION public.validar_mensaje()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
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

CREATE OR REPLACE FUNCTION public.avisar_mencion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  ids uuid[];
begin
  if not public.sala_publica(new.sala) or position('@' in new.texto) = 0 then return new; end if;
  select array_agg(p.id) into ids from (
    select p.id from public.profiles p
    join public.follows f on f.follower = new.user_id and f.followed = p.id
    where position('@' || lower(p.username) in lower(new.texto)) > 0
      and not exists (select 1 from public.bloqueos b
                      where (b.bloqueador = p.id and b.bloqueado = new.user_id)
                         or (b.bloqueador = new.user_id and b.bloqueado = p.id))
    limit 10
  ) p;
  if ids is null then return new; end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'mencion', 'id', new.id, 'para', to_jsonb(ids))
  );
  return new;
end;
$$;

-- Idioma del teléfono: los push salen en el idioma de cada token.
alter table public.push_tokens add column idioma text not null default 'es' check (idioma in ('es', 'en'));
grant insert (idioma), update (idioma) on public.push_tokens to authenticated;

-- El centro de avisos guarda el texto en los dos idiomas.
alter table public.notificaciones add column titulo_en text, add column cuerpo_en text;

-- Pop-ups para un solo idioma (null = para todos).
alter table public.anuncios add column idioma text check (idioma in ('es', 'en'));
-- Los pop-ups de antes se escribieron en español.
update public.anuncios set idioma = 'es' where idioma is null;
