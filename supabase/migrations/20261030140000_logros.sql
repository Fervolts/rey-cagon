-- Logros que no salen de las cagadas: los de los easter eggs que pasan en la pantalla
-- (tocar el "psst", tocar la corona). Los que se calculan con las cagadas (rachas, horas raras,
-- fechas) no se guardan aquí: el cliente los deriva. Así sobreviven a un cambio de teléfono.
create table if not exists public.logros (
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  clave text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, clave),
  -- Solo las claves que conoce la app. Las que empiezan con placer_ son del lado secreto.
  constraint logros_clave_valida check (clave in ('psst_meon', 'psst_pulcro', 'psst_todas', 'corona', 'placer_lado'))
);

alter table public.logros enable row level security;

-- Se ven en el perfil de cualquiera (la vitrina de otros los muestra), menos los del lado secreto:
-- esos solo los ve el dueño o quien también tenga el secreto desbloqueado.
drop policy if exists logros_leer on public.logros;
create policy logros_leer on public.logros for select to authenticated using (
  clave not like 'placer\_%'
  or user_id = (select auth.uid())
  or exists (select 1 from public.profiles yo where yo.id = (select auth.uid()) and yo.placer_desbloqueado)
);

-- Cada quien guarda los suyos. Un logro del lado secreto solo si de verdad lo tiene.
drop policy if exists logros_guardar on public.logros;
create policy logros_guardar on public.logros for insert to authenticated with check (
  user_id = (select auth.uid())
  and (
    clave not like 'placer\_%'
    or exists (select 1 from public.profiles yo where yo.id = (select auth.uid()) and yo.placer_desbloqueado)
  )
);

-- No se editan ni se borran desde la app (se van con la cuenta por el cascade).
revoke update, delete on public.logros from anon, authenticated;
grant select, insert on public.logros to authenticated;
