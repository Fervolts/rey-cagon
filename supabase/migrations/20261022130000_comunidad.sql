-- Links a la comunidad oficial (por ahora el canal de WhatsApp). Se cambian o se apagan aquí
-- sin sacar versión de la app. Solo se editan por SQL: la app únicamente los lee.
create table public.comunidad (
  id text primary key check (id in ('whatsapp', 'discord')),
  url text not null check (url ~ '^https://(whatsapp\.com/channel/|discord\.gg/|discord\.com/invite/)[A-Za-z0-9_-]+$'),
  activo boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.comunidad enable row level security;
create policy comunidad_select on public.comunidad for select to authenticated using (activo);
