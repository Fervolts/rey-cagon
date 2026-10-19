-- Rating secreto: qué tan placentera fue cada cagada (1 = destructiva, 7 = celestial).
alter table public.cagadas add column placer smallint check (placer between 1 and 7);

-- El usuario solo puede cambiar el tipo y el placer de sus cagadas (antes podía tocar created_at
-- y saltarse el límite de una por hora).
revoke update on public.cagadas from anon, authenticated;
grant update (tipo, placer) on public.cagadas to authenticated;

-- Se pone en true cuando encuentra el easter egg de la hoja en Tips.
alter table public.profiles add column placer_desbloqueado boolean not null default false;
grant update (placer_desbloqueado) on public.profiles to authenticated;

-- Ranking secreto: placenteras (5 a 7) contra destructivas (1 a 3). Vacío si quien pregunta
-- no lo ha desbloqueado.
create function public.ranking_placer(period text, solo_siguiendo boolean default false)
returns table(user_id uuid, username text, avatar text, sombrero text, lentes text, mascota text,
              cagadas int, lentes_x real, lentes_y real, sombrero_x real, sombrero_y real,
              lentes_escala real, sombrero_escala real,
              placenteras bigint, destructivas bigint, calificadas bigint, promedio numeric)
language sql stable set search_path = ''
as $$
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
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
  group by p.id;
$$;
revoke execute on function public.ranking_placer(text, boolean) from public, anon;
grant execute on function public.ranking_placer(text, boolean) to authenticated;

-- Etiquetas del rating: lo destructivo (dolorosa, sangrante, ardiente) y lo placentero
-- (virtuosa, placentera, liberadora).
alter table public.cagadas add column etiquetas text[] not null default '{}'
  check (etiquetas <@ array['dolorosa', 'sangrante', 'ardiente', 'virtuosa', 'placentera', 'liberadora']);
grant update (etiquetas) on public.cagadas to authenticated;
