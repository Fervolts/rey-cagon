-- Menciones en la sala global: "@username" avisa por push a esa persona (máx. 10 por mensaje,
-- sin avisarse a uno mismo ni saltarse bloqueos).
create function public.avisar_mencion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  ids uuid[];
begin
  if new.sala <> 'global' or position('@' in new.texto) = 0 then return new; end if;
  select array_agg(p.id) into ids from (
    select p.id from public.profiles p
    where p.id <> new.user_id
      and position('@' || lower(p.username) in lower(new.texto)) > 0
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
create trigger mensajes_avisar_mencion after insert on public.mensajes
  for each row execute function public.avisar_mencion();
