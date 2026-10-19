-- Push "X te empezó a seguir" vía la misma Edge Function.
create or replace function public.avisar_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://TU-PROYECTO.supabase.co/functions/v1/notificar-cagada',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'webhook_secret')
    ),
    body := jsonb_build_object('tipo', 'follow', 'follower', new.follower, 'followed', new.followed)
  );
  return new;
end;
$$;
revoke execute on function public.avisar_follow() from public, anon, authenticated;

create trigger follows_avisar
  after insert on public.follows
  for each row execute function public.avisar_follow();
