-- Respuestas en hilos de las salas públicas: aviso al dueño del mensaje padre y a los que ya
-- respondieron en ese hilo (máx. 20). Se salta a quien escribe, los bloqueos en cualquier sentido
-- y a quien ya recibe el aviso de mención por este mismo mensaje (avisar_mencion), para no
-- mandarle dos. El soporte tiene su propio aviso.
create function public.avisar_respuesta()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  ids uuid[];
begin
  if new.responde_a is null or not public.sala_publica(new.sala) then return new; end if;
  select array_agg(u.id) into ids from (
    select distinct x.user_id as id from (
      select m.user_id from public.mensajes m where m.id = new.responde_a
      union
      select m.user_id from public.mensajes m where m.responde_a = new.responde_a and m.id <> new.id
    ) x
    where x.user_id <> new.user_id
      and not exists (select 1 from public.bloqueos b
                      where (b.bloqueador = x.user_id and b.bloqueado = new.user_id)
                         or (b.bloqueador = new.user_id and b.bloqueado = x.user_id))
      and not exists (select 1 from public.profiles p
                      join public.follows f on f.follower = new.user_id and f.followed = p.id
                      where p.id = x.user_id and position('@' || lower(p.username) in lower(new.texto)) > 0)
    limit 20
  ) u;
  if ids is null then return new; end if;
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'respuesta', 'id', new.id, 'para', to_jsonb(ids))
  );
  return new;
end;
$$;
create trigger mensajes_avisar_respuesta after insert on public.mensajes
  for each row execute function public.avisar_respuesta();
