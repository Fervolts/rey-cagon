-- Anuncios fijados arriba del chat: un admin fija un mensaje de la sala global por un tiempo.
-- Distinto de los pop-ups (public.anuncios): no manda push ni sale al abrir la app, se queda
-- arriba de la sala hasta `fijado_hasta`.
alter table public.mensajes
  add column fijado_hasta timestamptz,
  add constraint mensajes_fijado_solo_global check (fijado_hasta is null or sala = 'global');
create index on public.mensajes (fijado_hasta) where fijado_hasta is not null;

-- Fijar o desfijar: solo admins (la política mensajes_update ya exige es_admin()).
grant update (fijado_hasta) on public.mensajes to authenticated;

-- Nadie puede mandar un mensaje ya fijado.
create function public.mensaje_sin_fijar()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.fijado_hasta := null;
  return new;
end;
$$;
create trigger mensajes_sin_fijar before insert on public.mensajes
  for each row execute function public.mensaje_sin_fijar();
