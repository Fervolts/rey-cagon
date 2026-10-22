-- Los anuncios pasan a ser pop-ups armables desde la app (pantalla de admin): emoji, botón
-- opcional con link, hasta cuándo sale y si además manda push a todos.
alter table public.anuncios
  add column emoji text not null default '📢' check (char_length(emoji) between 1 and 16),
  add column boton_texto text check (char_length(btrim(boton_texto)) between 1 and 30),
  add column boton_url text check (boton_url ~ '^https://[^\s<>"]+$'),
  add column push boolean not null default true,
  add column hasta timestamptz not null default now() + interval '7 days',
  add constraint anuncios_boton_completo check ((boton_texto is null) = (boton_url is null));

-- Sin push: solo sale como pop-up al abrir la app.
create or replace function public.avisar_anuncio()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not new.push then return new; end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'anuncio', 'id', new.id)
  );
  return new;
end;
$$;

-- Apagar un pop-up antes de tiempo: el admin le cambia `hasta`.
create policy anuncios_update on public.anuncios for update to authenticated
  using (public.es_admin()) with check (public.es_admin());
grant update (hasta) on public.anuncios to authenticated;
