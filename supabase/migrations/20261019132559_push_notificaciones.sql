create extension if not exists pg_net;

-- Token FCM de cada teléfono. Un usuario puede tener varios.
create table public.push_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  updated_at timestamptz not null default now()
);
create index on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;

create policy push_tokens_select_own on public.push_tokens
  for select to authenticated using ((select auth.uid()) = user_id);
create policy push_tokens_insert_own on public.push_tokens
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy push_tokens_update_own on public.push_tokens
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy push_tokens_delete_own on public.push_tokens
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Cada cagada nueva avisa a la Edge Function notificar-cagada, que manda el push a los demás.
create or replace function public.avisar_cagada()
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
    body := jsonb_build_object('user_id', new.user_id, 'id', new.id)
  );
  return new;
end;
$$;
revoke execute on function public.avisar_cagada() from public, anon, authenticated;

create trigger cagadas_avisar
  after insert on public.cagadas
  for each row execute function public.avisar_cagada();
