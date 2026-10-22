-- Centro de avisos: cada push que manda la Edge Function notificaciones queda guardado aquí,
-- para verlo en la app aunque el teléfono tenga los avisos apagados.
-- Y anuncios: los admins le escriben a todo el mundo (push a todos + aviso dentro de la app).

create table public.notificaciones (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  tipo text not null,
  titulo text not null,
  cuerpo text not null default '',
  datos jsonb not null default '{}',
  leida boolean not null default false,
  created_at timestamptz not null default now()
);
create index on public.notificaciones (user_id, created_at desc);
alter table public.notificaciones enable row level security;

-- Las escribe solo el servidor (service role). Cada quien lee, marca como leídas y borra las suyas.
create policy notificaciones_select on public.notificaciones for select to authenticated
  using (user_id = (select auth.uid()));
create policy notificaciones_update on public.notificaciones for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy notificaciones_delete on public.notificaciones for delete to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update on public.notificaciones from authenticated;
grant update (leida) on public.notificaciones to authenticated;

create table public.anuncios (
  id bigint generated always as identity primary key,
  user_id uuid default auth.uid() references public.profiles (id) on delete set null,
  titulo text not null check (char_length(btrim(titulo)) between 1 and 80),
  texto text not null check (char_length(btrim(texto)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index on public.anuncios (created_at desc);
alter table public.anuncios enable row level security;

create policy anuncios_select on public.anuncios for select to authenticated using (true);
create policy anuncios_insert on public.anuncios for insert to authenticated
  with check (public.es_admin() and user_id = (select auth.uid()));
create policy anuncios_delete on public.anuncios for delete to authenticated using (public.es_admin());
revoke update on public.anuncios from authenticated;

create function public.avisar_anuncio()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
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
create trigger anuncios_avisar after insert on public.anuncios
  for each row execute function public.avisar_anuncio();

alter publication supabase_realtime add table public.notificaciones;
alter publication supabase_realtime add table public.anuncios;

-- Los avisos viejos no hacen falta: se borran a los 60 días.
select cron.schedule('limpiar_notificaciones', '30 4 * * *',
  $$delete from public.notificaciones where created_at < now() - interval '60 days'$$);
