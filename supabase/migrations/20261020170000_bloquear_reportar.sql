-- Bloquear y reportar usuarios (Google Play lo exige en apps donde la gente ve lo que otros publican).
create table public.bloqueos (
  bloqueador uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  bloqueado uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bloqueador, bloqueado),
  check (bloqueador <> bloqueado)
);
alter table public.bloqueos enable row level security;
create policy bloqueos_propios_leer on public.bloqueos for select to authenticated using ((select auth.uid()) = bloqueador);
create policy bloqueos_propios_crear on public.bloqueos for insert to authenticated with check ((select auth.uid()) = bloqueador);
create policy bloqueos_propios_borrar on public.bloqueos for delete to authenticated using ((select auth.uid()) = bloqueador);

-- Al bloquear se cortan los follows en los dos sentidos.
create function public.cortar_follows() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.follows
  where (follower = new.bloqueador and followed = new.bloqueado)
     or (follower = new.bloqueado and followed = new.bloqueador);
  return new;
end;
$$;
revoke execute on function public.cortar_follows() from public, anon, authenticated;
create trigger bloqueos_cortar_follows after insert on public.bloqueos
  for each row execute function public.cortar_follows();

-- Nadie puede seguir a quien lo bloqueó ni a quien bloqueó.
create policy follows_sin_bloqueo on public.follows as restrictive for insert to authenticated
  with check (not exists (select 1 from public.bloqueos b
                          where (b.bloqueador = follower and b.bloqueado = followed)
                             or (b.bloqueador = followed and b.bloqueado = follower)));

-- Reportes: se guardan para revisarlos a mano. Nadie los puede leer desde la app.
create table public.reportes (
  id bigint generated always as identity primary key,
  reportante uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  reportado uuid not null references public.profiles(id) on delete cascade,
  motivo text not null check (char_length(motivo) between 1 and 300),
  created_at timestamptz not null default now()
);
alter table public.reportes enable row level security;
create policy reportes_crear on public.reportes for insert to authenticated with check ((select auth.uid()) = reportante);

-- Los rankings no muestran a quien bloqueaste ni a quien te bloqueó.

create or replace function public.leaderboard(period text, solo_siguiendo boolean DEFAULT false)
 RETURNS TABLE(user_id uuid, username text, avatar text, total bigint, sombrero text, lentes text, mascota text, cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p.id, p.username, p.avatar, count(c.id) as total, p.sombrero, p.lentes, p.mascota,
         p.cagadas, p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
    and not exists (select 1 from public.bloqueos b
                    where (b.bloqueador = (select auth.uid()) and b.bloqueado = p.id)
                       or (b.bloqueador = p.id and b.bloqueado = (select auth.uid())))
  group by p.id
  order by total desc, p.username;
$function$;

create or replace function public.ranking_placer(period text, solo_siguiendo boolean DEFAULT false)
 RETURNS TABLE(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text, cagadas integer, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real, lentes_escala real, sombrero_escala real, placenteras bigint, destructivas bigint, calificadas bigint, promedio numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p.id, p.username, p.avatar, p.sombrero, p.lentes, p.mascota,
         p.cagadas, p.lentes_x, p.lentes_y, p.sombrero_x, p.sombrero_y, p.lentes_escala, p.sombrero_escala,
         count(c.id) filter (where c.placer >= 5),
         count(c.id) filter (where c.placer <= 3),
         count(c.placer),
         round(avg(c.placer), 1)
  from public.profiles p
  left join public.cagadas c
    on c.user_id = p.id
   and c.created_at >= date_trunc(period, now() at time zone 'America/Caracas') at time zone 'America/Caracas'
  where period in ('day', 'week', 'month', 'quarter', 'year')
    and exists (select 1 from public.profiles yo where yo.id = (select auth.uid()) and yo.placer_desbloqueado)
    and p.placer_desbloqueado
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
    and not exists (select 1 from public.bloqueos b
                    where (b.bloqueador = (select auth.uid()) and b.bloqueado = p.id)
                       or (b.bloqueador = p.id and b.bloqueado = (select auth.uid())))
  group by p.id;
$function$;
