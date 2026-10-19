-- La Edge Function notificar-cagada pasó a llamarse notificaciones (también avisa follows y versiones).
create or replace function public.avisar_cagada()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://TU-PROYECTO.supabase.co/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('user_id', new.user_id, 'id', new.id)
  );
  return new;
end;
$$;

create or replace function public.avisar_follow()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://TU-PROYECTO.supabase.co/functions/v1/notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'follow', 'follower', new.follower, 'followed', new.followed)
  );
  return new;
end;
$$;
