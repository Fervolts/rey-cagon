-- Aviso del secreto: cuando una cagada pasa de no calificada a calificada.
create function public.avisar_placer()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (old.placer is null and old.etiquetas = '{}')
     and (new.placer is not null or new.etiquetas <> '{}') then
    perform net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
      ),
      body := jsonb_build_object('tipo', 'placer', 'id', new.id)
    );
  end if;
  return new;
end;
$$;
revoke execute on function public.avisar_placer() from public, anon, authenticated;

create trigger cagadas_calificar after update of placer, etiquetas on public.cagadas
  for each row execute function public.avisar_placer();

-- El ranking secreto solo muestra a quienes también encontraron el secreto.
create or replace function public.ranking_placer(period text, solo_siguiendo boolean default false)
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
    and p.placer_desbloqueado
    and (not solo_siguiendo
         or p.id = (select auth.uid())
         or exists (select 1 from public.follows f where f.follower = (select auth.uid()) and f.followed = p.id))
  group by p.id;
$$;
grant execute on function public.ranking_placer(text, boolean) to authenticated;
